import AppKit

/// Thin wrapper that installs both a global and a local monitor, so the island
/// sees events regardless of which app owns them - including its own panel.
/// Mouse-only masks need no Accessibility permission.
final class GlobalEventMonitor {
    private var global: Any?
    private var local: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent) -> Void

    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        self.mask = mask
        self.handler = handler
    }

    deinit { stop() }

    func start() {
        guard global == nil else { return }
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [handler] event in
            handler(event)
        }
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { [handler] event in
            handler(event)
            return event
        }
    }

    func stop() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil
        local = nil
    }
}
