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
    /// A trackpad swipe arrives as a burst of events; one gesture must produce
    /// at most one section change.
    private var gestureConsumed = false
    private var lastSwipeTime: TimeInterval = 0

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
        let isOpen = model.stage == .open
        let onIsland = isOpen
            ? model.islandScreenRect().insetBy(dx: -12, dy: -12).contains(location)
            : model.triggerScreenRect().insetBy(dx: -8, dy: -4).contains(location)
        guard onIsland else { return }

        // Trackpad gestures report a phase; a new gesture resets the budget.
        // A mouse wheel has no phase, so fall back to an idle timeout.
        let now = ProcessInfo.processInfo.systemUptime
        if event.phase.contains(.began) || event.momentumPhase.contains(.began) {
            scrollAccumulator = 0
            gestureConsumed = false
        } else if now - lastScrollTime > 0.30 {
            scrollAccumulator = 0
            gestureConsumed = false
        }
        lastScrollTime = now
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            scrollAccumulator = 0
            gestureConsumed = false
            return
        }
        // Ignore inertia: the flick has already been acted on.
        guard !event.momentumPhase.contains(.changed) else { return }

        let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.2

        if horizontal {
            scrollAccumulator += event.scrollingDeltaX
            let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 26 : 14
            guard abs(scrollAccumulator) >= threshold, !gestureConsumed else { return }
            // Natural direction: swiping left moves forward through sections,
            // the same way pages move under your fingers.
            let forward = scrollAccumulator < 0
            scrollAccumulator = 0
            gestureConsumed = true

            if isOpen {
                guard now - lastSwipeTime > 0.18 else { return }
                lastSwipeTime = now
                model.switchTab(by: forward ? 1 : -1)
            } else {
                forward ? MediaStore.shared.nextTrack() : MediaStore.shared.previousTrack()
                Haptics.tap()
            }
        } else {
            scrollAccumulator += event.scrollingDeltaY
            guard !gestureConsumed else { return }
            if scrollAccumulator < -22, !isOpen {
                scrollAccumulator = 0
                gestureConsumed = true
                model.open()
            } else if scrollAccumulator > 22, isOpen {
                scrollAccumulator = 0
                gestureConsumed = true
                model.close()
            }
        }
    }
}
