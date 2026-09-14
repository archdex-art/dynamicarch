import AppKit
import SwiftUI

/// Runs the user's own Shortcuts from the island. Enumerated through the
/// `shortcuts` CLI that ships with macOS, so there is nothing to configure.
@MainActor
@Observable
final class ShortcutsStore {
    static let shared = ShortcutsStore()

    private(set) var names: [String] = []
    private(set) var isLoading = false
    private(set) var pinned: [String] = UserDefaults.standard.stringArray(forKey: "pinnedShortcuts") ?? []
    private(set) var isRunning: String?

    private init() {}

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .utility) {
            let output = Self.run(["list"])
            let list = output.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            await MainActor.run { [weak self] in
                guard let self else { return }
                isLoading = false
                withAnimation(Motion.content) { names = list }
            }
        }
    }

    func pin(_ name: String) {
        guard !pinned.contains(name) else { return }
        pinned.append(name)
        if pinned.count > 4 { pinned.removeFirst() }
        UserDefaults.standard.set(pinned, forKey: "pinnedShortcuts")
    }

    func unpin(_ name: String) {
        pinned.removeAll { $0 == name }
        UserDefaults.standard.set(pinned, forKey: "pinnedShortcuts")
    }

    func run(_ name: String) {
        isRunning = name
        Task.detached(priority: .userInitiated) {
            _ = Self.run(["run", name])
            await MainActor.run { [weak self] in
                self?.isRunning = nil
                Haptics.success()
            }
        }
    }

    /// Nothing to run yet is a normal state, not an error - the picker says so
    /// and offers the one action that helps.
    var hasShortcuts: Bool { !names.isEmpty }

    func openShortcutsApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private nonisolated static func run(_ arguments: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
