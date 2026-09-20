import AppKit
import SwiftUI

/// A transient thing the island shows while it is otherwise at rest: a volume
/// change, a charger being plugged in, AirPods connecting, a track change.
struct IslandActivity: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case volume, brightness, keyboardBacklight, battery, power, bluetooth
        case media, timer, shelf, clipboard, notification, custom

        /// Higher wins when two activities compete for the island.
        var priority: Int {
            switch self {
            case .notification: 90
            case .power, .battery: 70
            case .bluetooth: 65
            case .volume, .brightness, .keyboardBacklight: 60
            case .timer: 50
            case .clipboard: 55
            case .media: 40
            case .shelf: 45
            case .custom: 30
            }
        }
    }

    enum Content: Equatable {
        /// Symbol + 0...1 level, drawn as an inline slider (volume/brightness).
        case level(symbol: String, value: Double, tint: Color, label: String?)
        /// Leading glyph/artwork + text, drawn as a compact capsule.
        case badge(symbol: String?, image: NSImage?, title: String, subtitle: String?, tint: Color)
        /// Album art + waveform, used for track changes.
        case media(artwork: NSImage?, title: String, artist: String?, tint: Color)
        /// Circular progress (timer).
        case progress(symbol: String, fraction: Double, label: String, tint: Color)
        /// Battery state with its own animated treatment.
        case battery(level: Double, state: BatteryState, detail: String?)
    }

    enum BatteryState: Equatable {
        case charging
        case charged
        case unplugged
        case low
        case critical

        var tint: Color {
            switch self {
            case .charging, .charged: Palette.positive
            case .unplugged: Palette.secondaryText
            case .low: Palette.warning
            case .critical: Palette.danger
            }
        }

        var isCharging: Bool { self == .charging }
        var isWarning: Bool { self == .low || self == .critical }
    }

    let id: UUID
    var kind: Kind
    var content: Content
    /// Seconds on screen; refreshed when a same-kind activity replaces it.
    var duration: TimeInterval

    init(id: UUID = UUID(), kind: Kind, content: Content, duration: TimeInterval = 1.8) {
        self.id = id
        self.kind = kind
        self.content = content
        self.duration = duration
    }

    var priority: Int { kind.priority }

    /// Everything except plain media uses the compact "grow around the notch" look.
    var wantsCompactPresentation: Bool { true }

    var compactSideWidth: CGFloat {
        switch content {
        case .level:
            return 84
        case .badge(_, _, let title, let subtitle, _):
            // "Markdown text file · 7.8 KB" is a normal subtitle now that the
            // clipboard reports type and size, so the cap has to fit it.
            let base: CGFloat = 46
            let text = max(CGFloat(title.count), CGFloat(subtitle?.count ?? 0))
            return min(190, base + text * 3.6)
        case .media:
            return 92
        case .progress:
            return 70
        case .battery(_, _, let detail):
            // "Battery Critical" is the longest title; the slot must fit it
            // even when there is no detail line to widen things.
            return min(184, 84 + max(CGFloat(detail?.count ?? 0), 17) * 3.6)
        }
    }

    var compactHeightBump: CGFloat {
        switch content {
        case .level: 6
        case .badge: 8
        case .media: 10
        case .progress: 8
        case .battery: 10
        }
    }
}

/// Serialises activities onto the island: highest priority wins, same-kind
/// updates coalesce instead of queueing, and everything auto-expires.
@MainActor
final class ActivityCenter {
    static let shared = ActivityCenter()

    private weak var model: IslandModel?
    private var expiry: DispatchWorkItem?
    private var pending: [IslandActivity] = []

    private init() {}

    func attach(model: IslandModel) { self.model = model }

    func present(_ activity: IslandActivity) {
        guard let model else { return }
        guard Preferences.shared.activitiesEnabled else { return }

        if let current = model.activity {
            if current.kind == activity.kind {
                // Coalesce: same source updating itself (e.g. volume being held).
                withAnimation(Motion.content) { model.activity = activity }
                scheduleExpiry(after: activity.duration)
                return
            }
            if current.priority > activity.priority {
                pending.removeAll { $0.kind == activity.kind }
                pending.append(activity)
                return
            }
        }

        withAnimation(Motion.activity) { model.activity = activity }
        scheduleExpiry(after: activity.duration)
    }

    func dismiss(kind: IslandActivity.Kind) {
        guard let model, model.activity?.kind == kind else { return }
        expire()
    }

    private func scheduleExpiry(after delay: TimeInterval) {
        expiry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.expire() }
        expiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func expire() {
        guard let model else { return }
        expiry?.cancel()
        expiry = nil
        if let next = pending.max(by: { $0.priority < $1.priority }) {
            pending.removeAll { $0.id == next.id }
            withAnimation(Motion.activity) { model.activity = next }
            scheduleExpiry(after: next.duration)
        } else {
            withAnimation(Motion.activity) { model.activity = nil }
        }
    }
}
