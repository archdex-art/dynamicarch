import AppKit

/// Entry point. The app is an accessory (menu-bar) process: it never owns a
/// dock tile and never becomes the active app unless the user explicitly
/// interacts with a control that needs key focus.
@main
enum AppMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
