import AppKit
import ApplicationServices
import CryptoKit
import SwiftUI

/// Mirrors system notification banners - including incoming calls - into the
/// island.
///
/// macOS exposes no API for reading other apps' notifications. The two routes
/// used in practice are reading the Notification Centre database (needs Full
/// Disk Access and only sees records after delivery) and observing the banner
/// windows through the Accessibility API. We use the latter: it is live, it
/// carries the banner's own action buttons, and it rides on one permission the
/// user can revoke at any time.
@MainActor
final class NotificationMirror {
    static let shared = NotificationMirror()

    private var observer: AXObserver?
    private var workspaceObserver: NSObjectProtocol?
    /// Banners already mirrored, so a re-layout does not re-announce them.
    private var seen: Set<String> = []

    private init() {}

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt. Only ever called from an explicit user action.
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        guard Preferences.shared.notificationsEnabled, Self.isTrusted, workspaceObserver == nil else { return }
        attach()
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == "com.apple.notificationcenterui" else { return }
                self?.attach()
            }
        }
    }

    func stop() {
        detach()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        workspaceObserver = nil
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
    }

    private func attach() {
        detach()
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.notificationcenterui").first else { return }
        let pid = app.processIdentifier
        let application = AXUIElementCreateApplication(pid)

        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let mirror = Unmanaged<NotificationMirror>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in mirror.handle(window: element) }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        observer = created

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXWindowCreatedNotification, kAXCreatedNotification] {
            AXObserverAddNotification(created, application, notification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)

        // Catch banners that were already on screen when we attached.
        if let windows = copy(application, kAXWindowsAttribute) as? [AXUIElement] {
            windows.forEach { handle(window: $0) }
        }
    }

    // MARK: - Banner parsing

    private func handle(window: AXUIElement) {
        guard Preferences.shared.notificationsEnabled else { return }
        let texts = staticTexts(in: window)
        guard !texts.isEmpty else { return }

        // Hash rather than retain: the dedupe cache would otherwise hold the
        // plaintext of the last forty banners, which is often the most
        // sensitive text on the machine.
        let identity = Self.fingerprint(texts)
        guard !seen.contains(identity) else { return }
        seen.insert(identity)
        if seen.count > 40 { seen.removeAll(keepingCapacity: true) }

        // Banner layout is [app name, title, body] with optional extras.
        let appName = texts[0]
        let title = texts.count > 1 ? texts[1] : appName
        let body = texts.count > 2 ? texts[2...].joined(separator: " ") : nil

        let actions = buttons(in: window)
        let bundle = bundleIdentifier(for: appName)
        // Only apps that actually place calls get the call takeover, which
        // wires buttons to Accept/Decline. Matching on a button titled
        // "accept" let any app impersonate an incoming call in the island.
        let isCall = bundle.map(Self.callBundleIdentifiers.contains) ?? false

        let icon = bundle
            .flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first?.icon }

        if isCall {
            CallCenter.shared.present(caller: title, subtitle: body ?? appName, icon: icon, actions: actions)
            return
        }

        ActivityCenter.shared.present(
            IslandActivity(kind: .notification,
                           content: .badge(symbol: icon == nil ? "bell.badge.fill" : nil,
                                           image: icon,
                                           title: title,
                                           subtitle: body,
                                           tint: Palette.accent),
                           duration: 3.4)
        )

        if Preferences.shared.dismissSystemBanners { dismiss(window: window) }
    }

    /// Apps whose banners may be treated as an incoming call.
    private static let callBundleIdentifiers: Set<String> = [
        "com.apple.FaceTime",
        "com.apple.iChat",
        "com.apple.mobilephone",
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.google.Chrome",          // Meet runs in the browser
        "com.apple.Safari",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "net.whatsapp.WhatsApp",
    ]

    private func bundleIdentifier(for appName: String) -> String? {
        NSWorkspace.shared.runningApplications.first { $0.localizedName == appName }?.bundleIdentifier
    }

    private static func fingerprint(_ texts: [String]) -> String {
        let digest = SHA256.hash(data: Data(texts.joined(separator: "|").utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    struct BannerAction {
        let title: String
        let element: AXUIElement

        @MainActor func press() {
            AXUIElementPerformAction(element, kAXPressAction as CFString)
        }
    }

    private func staticTexts(in element: AXUIElement, depth: Int = 0) -> [String] {
        guard depth < 8 else { return [] }
        var result: [String] = []
        if let role = copy(element, kAXRoleAttribute) as? String, role == kAXStaticTextRole,
           let value = copy(element, kAXValueAttribute) as? String,
           value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            result.append(value)
        }
        if let children = copy(element, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children { result.append(contentsOf: staticTexts(in: child, depth: depth + 1)) }
        }
        return result
    }

    private func buttons(in element: AXUIElement, depth: Int = 0) -> [BannerAction] {
        guard depth < 8 else { return [] }
        var result: [BannerAction] = []
        if let role = copy(element, kAXRoleAttribute) as? String, role == kAXButtonRole {
            let title = (copy(element, kAXTitleAttribute) as? String)
                ?? (copy(element, kAXDescriptionAttribute) as? String) ?? ""
            if !title.isEmpty { result.append(BannerAction(title: title, element: element)) }
        }
        if let children = copy(element, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children { result.append(contentsOf: buttons(in: child, depth: depth + 1)) }
        }
        return result
    }

    /// Dismisses the banner without pressing anything inside it.
    ///
    /// The previous version pressed the first button whose *title* contained
    /// "close", "clear" or "dismiss" - but those titles are free text supplied
    /// by the notifying app, and pressing an action runs that app's handler.
    /// A malicious notification could therefore name a destructive action
    /// "Dismiss" and have it invoked with no user interaction. Cancelling the
    /// window uses Notification Center's own affordance instead.
    private func dismiss(window: AXUIElement) {
        AXUIElementPerformAction(window, kAXCancelAction as CFString)
    }

    private func copy(_ element: AXUIElement, _ attribute: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}

/// Incoming calls take over the island: caller, source, and the banner's own
/// Accept/Decline actions wired to the real buttons.
@MainActor
@Observable
final class CallCenter {
    static let shared = CallCenter()

    struct Call: Equatable {
        let id = UUID()
        var caller: String
        var subtitle: String
        var icon: NSImage?
        var acceptTitle: String?
        var declineTitle: String?

        static func == (lhs: Call, rhs: Call) -> Bool { lhs.id == rhs.id }
    }

    private(set) var call: Call?
    private var actions: [NotificationMirror.BannerAction] = []
    private var expiry: DispatchWorkItem?

    private init() {}

    func present(caller: String, subtitle: String, icon: NSImage?, actions: [NotificationMirror.BannerAction]) {
        self.actions = actions
        let accept = actions.first { $0.title.localizedCaseInsensitiveContains("accept") }
        let decline = actions.first {
            $0.title.localizedCaseInsensitiveContains("decline") || $0.title.localizedCaseInsensitiveContains("reject")
        }
        withAnimation(Motion.activity) {
            call = Call(caller: caller, subtitle: subtitle, icon: icon,
                        acceptTitle: accept?.title, declineTitle: decline?.title)
        }
        IslandModel.shared.open(tab: .home)

        expiry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.clear() }
        expiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: work)
    }

    func accept() {
        actions.first { $0.title.localizedCaseInsensitiveContains("accept") }?.press()
        clear()
    }

    func decline() {
        actions.first {
            $0.title.localizedCaseInsensitiveContains("decline") || $0.title.localizedCaseInsensitiveContains("reject")
        }?.press()
        clear()
    }

    func clear() {
        expiry?.cancel()
        expiry = nil
        actions = []
        withAnimation(Motion.activity) { call = nil }
        IslandModel.shared.close()
    }
}
