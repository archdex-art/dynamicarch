import AppKit

/// Decides which display hosts the island and rebuilds it when the hardware
/// layout changes (monitor plugged in, resolution change, pointer moved to a
/// different screen while "follows pointer" is on).
@MainActor
final class DisplayCoordinator {
    private let model: IslandModel
    private var controller: IslandWindowController?
    private var observers: [NSObjectProtocol] = []
    private var pointerScreenCheck: Timer?

    init(model: IslandModel) {
        self.model = model
    }

    func start() {
        rebuild()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        })

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller?.reassertLevel() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        })

        // "Follows pointer" needs polling: there is no notification for the
        // pointer crossing displays. 4 Hz is invisible in Activity Monitor and
        // more than fast enough for a window move.
        pointerScreenCheck = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Preferences.shared.displayTarget == .followsMouse else { return }
                guard let screen = NSScreen.mouseScreen,
                      let current = self.controller?.metrics.displayID,
                      screen.displayID != current else { return }
                self.rebuild()
            }
        }
    }

    func stop() {
        pointerScreenCheck?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        controller?.close()
        controller = nil
    }

    func rebuild() {
        let screen = targetScreen()
        guard let screen else { return }
        if let controller, controller.metrics == ScreenMetrics(screen: screen) {
            controller.refreshFrame()
            controller.reassertLevel()
            return
        }
        controller?.close()
        controller = IslandWindowController(screen: screen, model: model)
    }

    func updateCaptureVisibility() { controller?.updateCaptureVisibility() }
    func applyTheme() { controller?.applyTheme() }
    private func targetScreen() -> NSScreen? {
        switch Preferences.shared.displayTarget {
        case .builtIn:
            return NSScreen.screens.first(where: { $0.hardwareNotchSize != nil })
                ?? NSScreen.screens.first(where: { $0.displayID == CGMainDisplayID() })
                ?? NSScreen.main
        case .primary:
            return NSScreen.screens.first(where: { $0.displayID == CGMainDisplayID() }) ?? NSScreen.main
        case .followsMouse:
            return NSScreen.mouseScreen ?? NSScreen.main
        }
    }
}
