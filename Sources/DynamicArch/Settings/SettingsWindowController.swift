import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        // The island floats above the menu bar, so it would otherwise cover the
        // settings window's tab bar and swallow the clicks meant for it. Close
        // the island and place the window clear of it.
        IslandModel.shared.close()

        if let window {
            activate()
            window.makeKeyAndOrderFront(nil)
            position(window)
            return
        }

        // The style mask must be final *before* the hosting controller is
        // installed: changing it afterwards re-lays out the content view and
        // leaves SwiftUI's tab strip drawn in one place and hit-tested in
        // another, so tab clicks silently do nothing.
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.title = "DynamicArch Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        activate()
        window.makeKeyAndOrderFront(nil)
        // SwiftUI settles the window's size on the next pass; place it then.
        DispatchQueue.main.async { [weak self] in self?.position(window) }
    }

    /// A menu-bar app never activates on its own; the settings window needs
    /// real focus for pickers, text fields, and the keyboard, so we become a
    /// regular app for exactly as long as it is open.
    private func activate() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func position(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        // Anchor by the top-left corner: the window's height is decided by
        // SwiftUI after the first layout pass, so positioning by origin lands
        // in the wrong place and the island ends up covering the controls.
        let clearance = screen.menuBarHeight + IslandModel.Layout.openTallHeight + 24
        let topLeft = NSPoint(x: (visible.midX - window.frame.width / 2).rounded(),
                              y: (screen.frame.maxY - clearance).rounded())
        window.setFrameTopLeftPoint(topLeft)

        // If the content grew past the bottom of the screen, pull it back up.
        var frame = window.frame
        if frame.minY < visible.minY + 16 {
            frame.origin.y = visible.minY + 16
            window.setFrame(frame, display: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Windows created by an accessory app still need to declare that they accept
/// key status; without it the controls render but ignore clicks and keys.
private final class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
