import AppKit

/// Translates raw pointer activity into island intent: hover, click-outside,
/// scroll gestures, and "a drag is happening somewhere on screen".
@MainActor
final class PointerTracker {
    private let model: IslandModel
    private var moveMonitor: GlobalEventMonitor?
    private var buttonMonitor: GlobalEventMonitor?
    private var scrollMonitor: GlobalEventMonitor?

    private var lastLocation: CGPoint = .zero
    private var dragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
    private var scrollAccumulator: CGFloat = 0
    private var lastScrollTime: TimeInterval = 0

    init(model: IslandModel) {
        self.model = model
    }

    func start() {
        moveMonitor = GlobalEventMonitor(mask: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleMove(event) }
        }
        buttonMonitor = GlobalEventMonitor(mask: [.leftMouseDown, .leftMouseUp, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleButton(event) }
        }
        scrollMonitor = GlobalEventMonitor(mask: [.scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleScroll(event) }
        }
        moveMonitor?.start()
        buttonMonitor?.start()
        scrollMonitor?.start()
    }

    func stop() {
        moveMonitor?.stop()
        buttonMonitor?.stop()
        scrollMonitor?.stop()
        moveMonitor = nil
        buttonMonitor = nil
        scrollMonitor = nil
    }

    private func handleMove(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        // Sub-point jitter is not worth a state evaluation at 1000 Hz mice.
        if abs(location.x - lastLocation.x) < 0.5, abs(location.y - lastLocation.y) < 0.5 { return }
        lastLocation = location

        if event.type == .leftMouseDragged { detectDragSession() }
        model.pointerMoved(to: location)
    }

    private func handleButton(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            model.pointerClickedOutside(NSEvent.mouseLocation)
        case .leftMouseUp:
            if model.dragInFlight {
                // Give AppKit a beat to deliver performDragOperation first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    self?.model.setDragInFlight(false)
                }
            }
        default:
            break
        }
    }

    /// A file/image drag is in flight when the drag pasteboard gains content.
    private func detectDragSession() {
        guard !model.dragInFlight, Preferences.shared.shelfEnabled else { return }
        let pasteboard = NSPasteboard(name: .drag)
        let changeCount = pasteboard.changeCount
        guard changeCount != dragPasteboardChangeCount else { return }
        dragPasteboardChangeCount = changeCount
        Diagnostics.drag.info("drag pasteboard changed count=\(changeCount) types=\(pasteboard.types?.map(\.rawValue) ?? [], privacy: .public)")
        guard let types = pasteboard.types, !types.isEmpty else { return }
        let droppable: Set<NSPasteboard.PasteboardType> = [.fileURL, .URL, .png, .tiff, .pdf, .rtf, .string, .html]
        guard types.contains(where: { droppable.contains($0) || $0.rawValue.hasPrefix("public.") }) else { return }
        Diagnostics.drag.info("drag session detected -> opening shelf")
        model.setDragInFlight(true)
    }

    private func handleScroll(_ event: NSEvent) {
        guard Preferences.shared.gesturesEnabled else { return }
        let location = NSEvent.mouseLocation
        let onIsland = model.stage == .open
            ? model.islandScreenRect().contains(location)
            : model.triggerScreenRect().insetBy(dx: -8, dy: -4).contains(location)
        guard onIsland else { return }

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastScrollTime > 0.35 { scrollAccumulator = 0 }
        lastScrollTime = now

        // Horizontal swipe on the closed island skips tracks; vertical opens
        // and closes it.
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            scrollAccumulator += event.scrollingDeltaX
            if scrollAccumulator > 28 {
                scrollAccumulator = 0
                MediaStore.shared.previousTrack()
                Haptics.tap()
            } else if scrollAccumulator < -28 {
                scrollAccumulator = 0
                MediaStore.shared.nextTrack()
                Haptics.tap()
            }
        } else {
            scrollAccumulator += event.scrollingDeltaY
            if scrollAccumulator < -22, model.stage != .open {
                scrollAccumulator = 0
                model.open()
            } else if scrollAccumulator > 22, model.stage == .open {
                scrollAccumulator = 0
                model.close()
            }
        }
    }
}
