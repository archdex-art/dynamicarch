import AppKit
import SwiftUI

/// Where the island currently is in its lifecycle.
enum IslandStage: Equatable {
    /// Resting: the island is exactly the notch (invisible on notched Macs) or a
    /// slim pill on displays without a cutout.
    case closed
    /// Pointer is on the island, or a live activity wants attention: the island
    /// grows just enough to hint at content.
    case peek
    /// Full panel.
    case open
}

enum IslandTab: String, CaseIterable, Identifiable, Codable {
    case home, shelf, clipboard, calendar, mirror

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "rectangle.on.rectangle.angled"
        case .shelf: "tray.full"
        case .clipboard: "doc.on.clipboard"
        case .calendar: "calendar"
        case .mirror: "web.camera"
        }
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .shelf: "Shelf"
        case .clipboard: "Clipboard"
        case .calendar: "Calendar"
        case .mirror: "Mirror"
        }
    }
}

/// Geometry of the island for a given state. Single source of truth: the
/// SwiftUI layer renders it and the AppKit layer hit-tests against it, so the
/// visible shape and the interactive shape can never disagree.
struct IslandLayout: Equatable {
    var size: CGSize
    var topRadius: CGFloat
    var bottomRadius: CGFloat
}

@MainActor
@Observable
final class IslandModel {
    static let shared = IslandModel()

    // MARK: Display

    private(set) var metrics: ScreenMetrics?
    /// Fixed panel size. Large enough for every island state plus shadow bleed.
    private(set) var stageSize: CGSize = .zero

    // MARK: Interaction state

    private(set) var stage: IslandStage = .closed
    var tab: IslandTab = .home
    /// Transient thing being shown while closed (volume, battery, track change…).
    var activity: IslandActivity?
    /// True while the pointer is inside the island's hover zone.
    private(set) var hovering = false
    /// A drag session carrying droppable content is in flight somewhere on screen.
    private(set) var dragInFlight = false
    /// The drag is currently over our drop area.
    private(set) var dropTargeted = false
    /// Blocks auto-close (menus, text entry, an in-flight file operation).
    var interactionLock = 0

    /// Bumped whenever the island content should re-measure; lets views animate
    /// layout changes coherently with the shell.
    var contentRevision = 0

    // MARK: Feature surfaces

    let shelf = ShelfStore.shared
    let media = MediaStore.shared

    /// Installed by the window controller; toggles whether the panel claims
    /// mouse events at all.
    var interactivityHandler: ((Bool) -> Void)?

    private var closeWorkItem: DispatchWorkItem?
    private var dragFailsafe: DispatchWorkItem?
    private var interactivityGuard: Timer?
    private var peekWorkItem: DispatchWorkItem?

    private init() {}

    // MARK: - Display wiring

    func attach(metrics: ScreenMetrics) {
        self.metrics = metrics
        stageSize = CGSize(width: min(metrics.frame.width, Layout.stageWidth),
                           height: Layout.stageHeight)
    }

    // MARK: - Layout

    enum Layout {
        static let stageWidth: CGFloat = 980
        static let stageHeight: CGFloat = 420
        static let openWidth: CGFloat = 620
        static let openHeight: CGFloat = 188
        static let openTallHeight: CGFloat = 236
        /// Extra slop around the island where the pointer still counts as "on" it.
        static let hoverSlop: CGFloat = 6
        /// Slop before an open island auto-closes.
        static let closeSlop: CGFloat = 42
    }

    /// What the island shows while at rest. A live activity outranks the
    /// always-on media pill, and both outrank an empty notch.
    enum CompactPresentation: Equatable {
        case none
        case activity(IslandActivity)
        case media(MediaStore.Track)
    }

    var compactPresentation: CompactPresentation {
        if let activity { return .activity(activity) }
        if Preferences.shared.mediaEnabled,
           Preferences.shared.mediaCompactWhilePlaying,
           let track = media.track, track.isPlaying {
            return .media(track)
        }
        return .none
    }

    var layout: IslandLayout {
        guard let metrics else {
            return IslandLayout(size: .init(width: 190, height: 32), topRadius: 8, bottomRadius: 14)
        }
        let resting = metrics.restingSize

        switch stage {
        case .closed:
            switch compactPresentation {
            case .activity(let activity):
                let extra = activity.compactSideWidth
                return IslandLayout(size: CGSize(width: resting.width + extra * 2,
                                                 height: resting.height + activity.compactHeightBump),
                                    topRadius: metrics.hasHardwareNotch ? 10 : 12,
                                    bottomRadius: resting.height / 2 + 4)
            case .media:
                return IslandLayout(size: CGSize(width: resting.width + 74, height: resting.height + 4),
                                    topRadius: metrics.hasHardwareNotch ? 8 : 12,
                                    bottomRadius: resting.height / 2 + 2)
            case .none:
                return IslandLayout(size: resting,
                                    topRadius: metrics.hasHardwareNotch ? 6 : 10,
                                    bottomRadius: metrics.hasHardwareNotch ? 12 : resting.height / 2)
            }
        case .peek:
            let width = resting.width + 86
            let height = resting.height + 14
            return IslandLayout(size: CGSize(width: width, height: height),
                                topRadius: 12,
                                bottomRadius: height / 2)

        case .open:
            let height = tab == .home ? Layout.openHeight : Layout.openTallHeight
            let width = Layout.openWidth
            return IslandLayout(size: CGSize(width: width, height: height),
                                topRadius: 14,
                                bottomRadius: 30)
        }
    }

    /// Island rect inside the stage view (AppKit coordinates, origin bottom-left).
    func islandRect(inStage bounds: CGRect) -> CGRect {
        let size = layout.size
        return CGRect(x: (bounds.width - size.width) / 2,
                      y: bounds.height - size.height,
                      width: size.width,
                      height: size.height)
    }

    /// What the panel accepts clicks on. Everything else falls through to the
    /// windows (and menu bar) underneath.
    func interactiveRect(inStage bounds: CGRect) -> CGRect {
        if dragInFlight { return dropRect(inStage: bounds) }
        return islandRect(inStage: bounds).insetBy(dx: -Layout.hoverSlop, dy: -Layout.hoverSlop)
    }

    /// Generous catch area used while a drag is in flight.
    func dropRect(inStage bounds: CGRect) -> CGRect {
        let rect = islandRect(inStage: bounds)
        return CGRect(x: rect.minX - 40, y: rect.minY - 40,
                      width: rect.width + 80, height: rect.height + 40)
            .intersection(bounds)
    }

    /// Island rect in global screen coordinates.
    func islandScreenRect() -> CGRect {
        guard let metrics else { return .zero }
        let size = layout.size
        return CGRect(x: metrics.notchCenterX - size.width / 2,
                      y: metrics.frame.maxY - size.height,
                      width: size.width,
                      height: size.height)
    }

    /// The only region where the panel is allowed to claim mouse events.
    /// Everything else on screen - menu bar, other apps, our own settings
    /// window - must stay clickable.
    func interactiveScreenRect() -> CGRect {
        guard metrics != nil else { return .zero }
        if dragInFlight || dropTargeted {
            let rect = islandScreenRect()
            return CGRect(x: rect.minX - 90, y: rect.minY - 90,
                          width: rect.width + 180, height: rect.height + 90)
        }
        let rect = islandScreenRect().union(triggerScreenRect())
        return CGRect(x: rect.minX - Layout.hoverSlop,
                      y: rect.minY - Layout.hoverSlop,
                      width: rect.width + Layout.hoverSlop * 2,
                      height: rect.height + Layout.hoverSlop)
    }

    func refreshInteractivity(pointer: CGPoint? = nil) {
        let location = pointer ?? NSEvent.mouseLocation
        interactivityHandler?(interactiveScreenRect().contains(location) || dragInFlight)
    }

    /// Belt and braces: even if an event is missed - a Space switch, a
    /// screen-lock, a dropped monitor callback - the panel's click-through
    /// state is re-derived from the real pointer position every second.
    func startInteractivityGuard() {
        guard interactivityGuard == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshInteractivity() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        interactivityGuard = timer
    }

    func stopInteractivityGuard() {
        interactivityGuard?.invalidate()
        interactivityGuard = nil
    }

    /// Zone that wakes the island from rest.
    func triggerScreenRect() -> CGRect {
        guard let metrics else { return .zero }
        let resting = metrics.restingRect
        return CGRect(x: resting.minX - 4,
                      y: resting.minY - 2,
                      width: resting.width + 8,
                      height: resting.height + 2)
    }

    // MARK: - Transitions

    func setStage(_ next: IslandStage, animated: Bool = true) {
        guard stage != next else { return }
        defer { refreshInteractivity() }
        let animation: Animation = switch (stage, next) {
        case (_, .open): Motion.expand
        case (.open, _): Motion.collapse
        default: Motion.peek
        }
        if animated {
            withAnimation(animation) { stage = next }
        } else {
            stage = next
        }
    }

    func open(tab: IslandTab? = nil) {
        cancelPendingClose()
        if let tab { self.tab = tab }
        setStage(.open)
        Haptics.tap()
    }

    func close() {
        cancelPendingClose()
        guard interactionLock == 0 else { return }
        setStage(hovering ? .peek : .closed)
        // Never resume straight back into the camera: reopening the island
        // should not silently switch the webcam on.
        if tab == .mirror { tab = .home }
    }

    func toggle() {
        stage == .open ? close() : open()
    }

    private func cancelPendingClose() {
        closeWorkItem?.cancel()
        closeWorkItem = nil
    }

    func scheduleClose(after delay: TimeInterval = 0.28) {
        cancelPendingClose()
        let work = DispatchWorkItem { [weak self] in
            guard let self, interactionLock == 0, !dragInFlight else { return }
            setStage(hovering ? .peek : .closed)
        }
        closeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Pointer

    func pointerMoved(to location: CGPoint) {
        guard metrics != nil else { return }
        refreshInteractivity(pointer: location)
        switch stage {
        case .closed:
            if triggerScreenRect().contains(location) {
                hovering = true
                setStage(Preferences.shared.openOnHover ? .open : .peek)
                Haptics.tick()
            }
        case .peek:
            let inside = islandScreenRect().insetBy(dx: -Layout.hoverSlop, dy: -Layout.hoverSlop).contains(location)
                || triggerScreenRect().contains(location)
            hovering = inside
            if inside {
                if Preferences.shared.openOnHover { setStage(.open) }
            } else {
                setStage(.closed)
            }
        case .open:
            let inside = islandScreenRect().insetBy(dx: -Layout.closeSlop, dy: -Layout.closeSlop).contains(location)
            hovering = inside
            if inside {
                cancelPendingClose()
            } else if closeWorkItem == nil, Preferences.shared.closeOnPointerExit {
                scheduleClose(after: 0.32)
            }
        }
    }

    func pointerClickedOutside(_ location: CGPoint) {
        guard stage == .open else { return }
        guard !islandScreenRect().contains(location) else { return }
        close()
    }

    // MARK: - Drag & drop

    func setDragInFlight(_ active: Bool) {
        guard dragInFlight != active else { return }
        dragInFlight = active
        refreshInteractivity()
        dragFailsafe?.cancel()
        if active {
            // A drag that never reports its end would leave the panel claiming
            // mouse events forever, which would eat clicks across the top of
            // the screen. Time it out.
            let work = DispatchWorkItem { [weak self] in self?.setDragInFlight(false) }
            dragFailsafe = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: work)
        }
        guard Preferences.shared.shelfEnabled else { return }
        if active {
            if stage != .open {
                tab = .shelf
                setStage(.open)
                Haptics.tick()
            }
        } else {
            dropTargeted = false
            if stage == .open, !hovering, interactionLock == 0 {
                scheduleClose(after: 0.45)
            }
        }
    }

    func beginShelfTargeting() {
        cancelPendingClose()
        if stage != .open {
            tab = .shelf
            setStage(.open)
        }
        withAnimation(Motion.content) { dropTargeted = true }
    }

    func updateShelfTargeting(inside: Bool) {
        guard dropTargeted != inside else { return }
        withAnimation(Motion.content) { dropTargeted = inside }
    }

    func endShelfTargeting() {
        guard dropTargeted else { return }
        withAnimation(Motion.content) { dropTargeted = false }
    }

    @discardableResult
    func acceptDrop(pasteboard: NSPasteboard) -> Bool {
        let accepted = shelf.ingest(pasteboard: pasteboard)
        if accepted {
            tab = .shelf
            Haptics.success()
            scheduleClose(after: 1.6)
        }
        return accepted
    }
}
