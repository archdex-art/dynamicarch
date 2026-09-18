import AppKit

/// The window the island lives in.
///
/// Design notes:
/// * `NSPanel` + `.nonactivatingPanel` so clicking the island never steals focus
///   from the app the user is working in.
/// * Level `.mainMenu + 3` puts it above the menu bar and above status items
///   while staying below system alerts and the screen saver.
/// * The panel is *fixed size* for the lifetime of the display: it spans the
///   maximum island bounds plus shadow headroom, and the island animates
///   **inside** it. Resizing a window every frame is the single biggest source
///   of jank in notch apps - the window server has to re-create backing stores;
///   animating layer geometry inside a static surface stays on the GPU.
final class IslandPanel: NSPanel {
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: backing,
                   defer: flag)

        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        // Critical: the panel is a large surface pinned over the top of the
        // screen, and AppKit does *not* forward clicks a window declines to the
        // window underneath - it drops them. So the panel ignores mouse events
        // entirely and only becomes interactive while the pointer is actually
        // over the island (see IslandModel.interactivityHandler).
        ignoresMouseEvents = true
        animationBehavior = .none
        level = .mainMenu + 3
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // The island's chrome is chosen by the user's theme, never inherited
        // from the system appearance.
        appearance = NSAppearance(named: Preferences.shared.theme.appearance)
    }

    /// The island never takes key focus: it must not pull the user out of the
    /// app they are working in. Controls that genuinely need focus (Quick Look,
    /// settings) open their own window and borrow activation explicitly.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
