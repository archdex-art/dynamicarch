import AppKit
import ApplicationServices
import SwiftUI

/// Everything running on the machine, what it costs, and how to get rid of it
/// safely.
///
/// Safety is the whole point of this feature, so it is layered:
/// 1. Quitting is *graceful* by default - the app gets its normal termination
///    path and macOS still asks the user about unsaved work.
/// 2. Force quit is a separate, explicit action that always confirms, and warns
///    harder when the target is healthy (i.e. killing it can lose data).
/// 3. System-critical processes and anything the user has protected are never
///    force-quit and never included in bulk actions.
/// 4. Bulk quits are staggered, so fifty apps do not all throw save dialogs and
///    thrash the machine at the same instant.
@MainActor
@Observable
final class AppsStore {
    static let shared = AppsStore()

    struct Entry: Identifiable, Equatable {
        let id: pid_t
        var bundleIdentifier: String?
        var name: String
        var icon: NSImage?
        var isActive: Bool
        var isHidden: Bool
        var isAccessory: Bool
        /// Percent of one core, as reported by the kernel.
        var cpu: Double
        /// Resident memory in bytes.
        var memory: Int64
        /// Nil when we cannot tell (no Accessibility access).
        var isResponding: Bool?
        var launchDate: Date?
        /// Last time this app was frontmost, for idle auto-quit.
        var lastActive: Date

        var memoryDescription: String {
            ByteCountFormatter.string(fromByteCount: memory, countStyle: .memory)
        }

        var cpuDescription: String { String(format: "%.0f%%", cpu) }
    }

    /// Processes that must never be force-quit: killing them degrades or hangs
    /// the desktop, and none of them are what a user means by "an app".
    static let criticalBundleIdentifiers: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.loginwindow",
        "com.apple.SecurityAgent",
        "com.apple.coreservices.uiagent",
        "com.apple.Spotlight",
        "com.apple.WindowServer",
        "com.apple.universalaccessAuthWarning",
        "app.dynamicarch.DynamicArch",
    ]

    private(set) var entries: [Entry] = []
    private(set) var lastActionMessage: String?
    /// Bulk action in progress, so the UI can show progress instead of lying.
    private(set) var isQuitting = false

    var showsBackgroundApps = false
    /// Live only while the section is on screen; sampling costs a process spawn.
    private var sampleTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastActiveByPID: [pid_t: Date] = [:]
    private var autoQuitTimer: Timer?

    private init() {}

    // MARK: - Lifecycle

    func start() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        scheduleAutoQuit()
    }

    func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        endLiveSampling()
        autoQuitTimer?.invalidate()
        autoQuitTimer = nil
    }

    /// Called when the apps section appears and disappears.
    func beginLiveSampling() {
        guard sampleTimer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        sampleTimer = timer
    }

    func endLiveSampling() {
        sampleTimer?.invalidate()
        sampleTimer = nil
    }

    // MARK: - Inventory

    var visibleEntries: [Entry] {
        entries
            .filter { showsBackgroundApps || !$0.isAccessory }
            .sorted { $0.memory > $1.memory }
    }

    var totalMemory: Int64 {
        visibleEntries.reduce(0) { $0 + $1.memory }
    }

    func isProtected(_ entry: Entry) -> Bool {
        guard let bundleIdentifier = entry.bundleIdentifier else { return false }
        return Self.criticalBundleIdentifiers.contains(bundleIdentifier)
            || Preferences.shared.protectedBundleIdentifiers.contains(bundleIdentifier)
    }

    func isCritical(_ entry: Entry) -> Bool {
        guard let bundleIdentifier = entry.bundleIdentifier else { return false }
        return Self.criticalBundleIdentifiers.contains(bundleIdentifier)
    }

    func toggleProtection(_ entry: Entry) {
        guard let bundleIdentifier = entry.bundleIdentifier, !isCritical(entry) else { return }
        var protected = Preferences.shared.protectedBundleIdentifiers
        if protected.contains(bundleIdentifier) {
            protected.removeAll { $0 == bundleIdentifier }
        } else {
            protected.append(bundleIdentifier)
        }
        Preferences.shared.protectedBundleIdentifiers = protected
        Haptics.tap()
    }

    func refresh() {
        let now = Date.now
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy != .prohibited && $0.processIdentifier > 0
        }

        var previous: [pid_t: Entry] = [:]
        for entry in entries { previous[entry.id] = entry }

        entries = running.map { app in
            let pid = app.processIdentifier
            if app.isActive { lastActiveByPID[pid] = now }
            let old = previous[pid]
            return Entry(
                id: pid,
                bundleIdentifier: app.bundleIdentifier,
                name: app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? "Unknown",
                icon: app.icon,
                isActive: app.isActive,
                isHidden: app.isHidden,
                isAccessory: app.activationPolicy == .accessory,
                cpu: old?.cpu ?? 0,
                memory: old?.memory ?? 0,
                isResponding: old?.isResponding,
                launchDate: app.launchDate,
                lastActive: lastActiveByPID[pid] ?? app.launchDate ?? now
            )
        }

        // Drop bookkeeping for processes that are gone.
        let live = Set(entries.map(\.id))
        lastActiveByPID = lastActiveByPID.filter { live.contains($0.key) }
    }

    /// One `ps` call per tick is far cheaper than per-process `proc_pid_rusage`
    /// and needs no special privileges.
    private func sample() {
        refresh()
        let pids = entries.map(\.id)
        Task.detached(priority: .utility) {
            let usage = Self.sampleUsage()
            let responding = Self.sampleResponsiveness(pids: pids)
            await MainActor.run { [weak self] in
                guard let self else { return }
                entries = entries.map { entry in
                    var updated = entry
                    if let stats = usage[entry.id] {
                        updated.cpu = stats.cpu
                        updated.memory = stats.memory
                    }
                    updated.isResponding = responding[entry.id]
                    return updated
                }
            }
        }
    }

    private nonisolated static func sampleUsage() -> [pid_t: (cpu: Double, memory: Int64)] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-A", "-o", "pid=,pcpu=,rss="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        var result: [pid_t: (Double, Int64)] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3,
                  let pid = pid_t(fields[0]),
                  let cpu = Double(fields[1]),
                  let rss = Int64(fields[2])
            else { continue }
            result[pid] = (cpu, rss * 1024)
        }
        return result
    }

    /// A hung app stops answering Accessibility requests. With a short
    /// messaging timeout that is a reliable "not responding" probe - and
    /// without Accessibility access we report nothing rather than guessing.
    private nonisolated static func sampleResponsiveness(pids: [pid_t]) -> [pid_t: Bool] {
        guard AXIsProcessTrusted() else { return [:] }
        var result: [pid_t: Bool] = [:]
        for pid in pids {
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.25)
            var value: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
            switch status {
            case .success, .noValue, .attributeUnsupported:
                result[pid] = true
            case .cannotComplete:
                result[pid] = false
            default:
                break
            }
        }
        return result
    }

    // MARK: - Actions

    func activate(_ entry: Entry) {
        NSRunningApplication(processIdentifier: entry.id)?.activate(options: [.activateAllWindows])
    }

    func hide(_ entry: Entry) {
        NSRunningApplication(processIdentifier: entry.id)?.hide()
        refresh()
    }

    /// The safe path: the app runs its own termination, so unsaved work still
    /// gets a save prompt.
    @discardableResult
    func quit(_ entry: Entry) -> Bool {
        guard !isCritical(entry) else {
            lastActionMessage = "\(entry.name) is required by macOS"
            return false
        }
        guard let app = NSRunningApplication(processIdentifier: entry.id) else { return false }
        let quit = app.terminate()
        lastActionMessage = quit ? "Quitting \(entry.name)…" : "\(entry.name) refused to quit"
        Haptics.tap()
        return quit
    }

    /// The unsafe path, and it is treated as such: never for critical or
    /// protected apps, and the caller is expected to have confirmed.
    @discardableResult
    func forceQuit(_ entry: Entry) -> Bool {
        guard !isCritical(entry) else {
            lastActionMessage = "\(entry.name) is required by macOS"
            return false
        }
        guard !isProtected(entry) else {
            lastActionMessage = "\(entry.name) is protected"
            return false
        }
        guard let app = NSRunningApplication(processIdentifier: entry.id) else { return false }
        let killed = app.forceTerminate()
        lastActionMessage = killed ? "Force quit \(entry.name)" : "Could not force quit \(entry.name)"
        Haptics.success()
        refresh()
        return killed
    }

    /// Graceful quit with escalation: if the app has not exited after the grace
    /// period it is almost certainly hung, and only then do we force it.
    func quitThenForce(_ entry: Entry, grace: TimeInterval = 4) {
        guard quit(entry) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + grace) { [weak self] in
            guard let self,
                  let app = NSRunningApplication(processIdentifier: entry.id),
                  app.isTerminated == false
            else { return }
            _ = forceQuit(entry)
        }
    }

    var bulkQuitCandidates: [Entry] {
        entries.filter { entry in
            isProtected(entry) == false
                && !entry.isAccessory
                && entry.bundleIdentifier != Bundle.main.bundleIdentifier
        }
    }

    /// Quits everything eligible, spaced out so the machine is not hit with a
    /// wall of termination handlers and save dialogs at once.
    func quitAll(force: Bool = false) {
        let targets = bulkQuitCandidates
        guard !targets.isEmpty else {
            lastActionMessage = "Nothing to quit"
            return
        }
        isQuitting = true
        lastActionMessage = "Quitting \(targets.count) app\(targets.count == 1 ? "" : "s")…"

        for (index, entry) in targets.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.15) { [weak self] in
                guard let self else { return }
                if force { _ = forceQuit(entry) } else { _ = quit(entry) }
                if index == targets.count - 1 {
                    isQuitting = false
                    refresh()
                }
            }
        }
    }

    // MARK: - Idle auto-quit

    private func scheduleAutoQuit() {
        autoQuitTimer?.invalidate()
        guard Preferences.shared.autoQuitIdleMinutes > 0 else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.quitIdleApps() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        autoQuitTimer = timer
    }

    func reloadAutoQuitSchedule() { scheduleAutoQuit() }

    private func quitIdleApps() {
        let minutes = Preferences.shared.autoQuitIdleMinutes
        guard minutes > 0 else { return }
        let cutoff = Date.now.addingTimeInterval(-Double(minutes) * 60)
        refresh()
        for entry in bulkQuitCandidates where entry.lastActive < cutoff && !entry.isActive {
            // Always the graceful path: an automatic action must never be able
            // to throw away work.
            quit(entry)
        }
    }
}
