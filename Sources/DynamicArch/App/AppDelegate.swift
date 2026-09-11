import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var displays: DisplayCoordinator!
    private var menuBar: MenuBarController!
    private var signalSources: [DispatchSourceSignal] = []
    private var didShutDown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.shared.load()

        let model = IslandModel.shared
        displays = DisplayCoordinator(model: model)
        displays.start()

        menuBar = MenuBarController(model: model)
        menuBar.install()

        Services.shared.displays = displays
        Services.shared.start(model: model)
        installSignalHandlers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutdown()
    }

    /// `pkill`, a crash reporter, or a logout can end the process without
    /// AppKit's orderly termination; the helper must not outlive us either way.
    private func installSignalHandlers() {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
            source.resume()
            signalSources.append(source)
        }
    }

    private func shutdown() {
        guard !didShutDown else { return }
        didShutDown = true
        Services.shared.stop()
        displays.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
