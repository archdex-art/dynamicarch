import AppKit
import SwiftUI

/// The timer's logical state. Deliberately a value type describing *instants*,
/// not a countdown that is stepped: `remaining` is always derived from the
/// wall clock, so the UI can render at any frame rate - or not at all while
/// the island is closed - and never drift from the truth.
struct TimerState: Codable, Equatable {
    enum Phase: String, Codable {
        case idle, running, paused, completed
    }

    var phase: Phase = .idle
    /// What Reset restores.
    var configuredDuration: TimeInterval = 0
    var label: String = "Timer"
    /// Set while running: the instant the timer hits zero.
    var endsAt: Date?
    /// Set while paused: what was left at the moment of pausing.
    var remainingWhenPaused: TimeInterval?
    var completedAt: Date?

    var isActive: Bool { phase == .running || phase == .paused }
    var isVisible: Bool { phase != .idle }

    /// Seconds left, clamped. The single value every visual derives from.
    func remaining(at now: Date = .now) -> TimeInterval {
        switch phase {
        case .idle: configuredDuration
        case .running: max(0, endsAt.map { $0.timeIntervalSince(now) } ?? 0)
        case .paused: max(0, remainingWhenPaused ?? 0)
        case .completed: 0
        }
    }

    /// 0 at the start, 1 at zero. Progress, not remaining, so the bar fills.
    func progress(at now: Date = .now) -> Double {
        guard configuredDuration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining(at: now) / configuredDuration))
    }

    func display(at now: Date = .now) -> String {
        let seconds = Int(remaining(at: now).rounded(.up))
        let hours = seconds / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Owns the timer. Nothing here polls: transitions schedule a single one-shot
/// completion task, and the views read `state` and the clock.
@MainActor
@Observable
final class TimerStore {
    static let shared = TimerStore()

    private(set) var state = TimerState()
    /// Set briefly when the timer hits zero, so the island can celebrate.
    private(set) var justCompleted = false

    private var completion: DispatchWorkItem?
    private var celebration: DispatchWorkItem?
    /// Retires a finished timer once it has finished announcing itself.
    private var retirement: DispatchWorkItem?
    private var wakeObserver: NSObjectProtocol?
    private let storageKey = "timerState"

    private init() {
        restore()
    }

    // MARK: - Lifecycle

    func start() {
        // The machine sleeping does not stop the clock, so re-evaluate on wake
        // instead of trusting a scheduled task to have fired on time.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
        // A completion restored from a previous session has already had its
        // moment; it must not greet the user on launch.
        if state.phase == .completed { clear() }
        reconcile()
    }

    func stop() {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        completion?.cancel()
        completion = nil
    }

    // MARK: - Commands

    /// Arms and starts a fresh timer. Idempotent in the sense that starting
    /// again simply replaces what was running - there is only ever one.
    func start(duration: TimeInterval, label: String? = nil) {
        guard duration > 0 else { return }
        var next = TimerState()
        next.phase = .running
        next.configuredDuration = duration
        next.label = label ?? Self.defaultLabel(for: duration)
        next.endsAt = .now.addingTimeInterval(duration)
        apply(next)
        Haptics.tap()
    }

    func pause() {
        guard state.phase == .running else { return }
        var next = state
        next.remainingWhenPaused = state.remaining()
        next.endsAt = nil
        next.phase = .paused
        apply(next)
        Haptics.tick()
    }

    func resume() {
        guard state.phase == .paused else { return }
        let remaining = state.remaining()
        guard remaining > 0 else {
            complete()
            return
        }
        var next = state
        next.endsAt = .now.addingTimeInterval(remaining)
        next.remainingWhenPaused = nil
        next.phase = .running
        apply(next)
        Haptics.tick()
    }

    /// Safe against being hammered: each call just re-derives from the phase.
    func togglePause() {
        switch state.phase {
        case .running: pause()
        case .paused: resume()
        case .completed: reset()
        case .idle: break
        }
    }

    /// Back to the configured duration, stopped. Works from any phase,
    /// including after completion, and clears every derived visual.
    func reset() {
        guard state.configuredDuration > 0 else {
            clear()
            return
        }
        var next = state
        next.phase = .paused
        next.endsAt = nil
        next.remainingWhenPaused = state.configuredDuration
        next.completedAt = nil
        apply(next)
        justCompleted = false
        Haptics.tap()
    }

    /// Reset and start again in one action, for "run it again".
    func restart() {
        let duration = state.configuredDuration
        guard duration > 0 else { return }
        start(duration: duration, label: state.label)
    }

    func extend(by seconds: TimeInterval) {
        guard state.isVisible else { return }
        var next = state
        next.configuredDuration += seconds
        switch state.phase {
        case .running:
            next.endsAt = (state.endsAt ?? .now).addingTimeInterval(seconds)
        case .paused:
            next.remainingWhenPaused = state.remaining() + seconds
        case .completed:
            next.phase = .running
            next.endsAt = .now.addingTimeInterval(seconds)
            next.completedAt = nil
            justCompleted = false
        case .idle:
            break
        }
        apply(next)
        Haptics.tap()
    }

    /// Dismisses the timer entirely.
    /// How long a finished timer stays on screen, blinking, before it retires.
    /// Matched to the blink in `TimerViews`.
    static let announcementDuration: TimeInterval = 4.6

    func clear() {
        apply(TimerState())
        justCompleted = false
        IslandModel.shared.setTimerMinimal(false)
    }

    // MARK: - Transitions

    private func apply(_ next: TimerState) {
        // Any transition invalidates a pending retirement: the user has taken
        // the timer somewhere else.
        retirement?.cancel()
        retirement = nil
        withAnimation(Motion.content) { state = next }
        scheduleCompletion()
        persist()
        IslandModel.shared.timerStateChanged(next)
    }

    private func scheduleCompletion() {
        completion?.cancel()
        completion = nil
        guard state.phase == .running, let endsAt = state.endsAt else { return }
        let work = DispatchWorkItem { [weak self] in self?.complete() }
        completion = work
        // One scheduled task per run, fired at the exact instant - no ticking.
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, endsAt.timeIntervalSinceNow),
                                      execute: work)
    }

    private func complete() {
        guard state.phase == .running || state.phase == .paused else { return }
        var next = state
        next.phase = .completed
        next.endsAt = nil
        next.remainingWhenPaused = nil
        next.completedAt = .now
        apply(next)

        justCompleted = true
        celebration?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(Motion.content) { self?.justCompleted = false }
        }
        celebration = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)

        // Retire after the announcement. Without this a finished timer stays
        // on the island for ever, because `isVisible` is true in this phase.
        let retire = DispatchWorkItem { [weak self] in
            guard let self, state.phase == .completed else { return }
            clear()
        }
        retirement = retire
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.announcementDuration, execute: retire)

        // No separate "finished" badge: an activity outranks the timer in the
        // compact slot, so it hid the very thing that is meant to blink - and
        // said the same thing twice, truncated.
        NSSound(named: "Glass")?.play()
        Haptics.success()
    }

    /// Catches a timer whose deadline passed while the machine was asleep or
    /// the app was not running.
    func reconcile() {
        guard state.phase == .running, let endsAt = state.endsAt else { return }
        if endsAt <= .now {
            complete()
        } else {
            scheduleCompletion()
        }
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(TimerState.self, from: data)
        else { return }
        state = stored
        // A relaunch must not resurrect a finished timer as if it were live.
        if stored.phase == .running, let endsAt = stored.endsAt, endsAt <= .now {
            state.phase = .completed
            state.endsAt = nil
            state.completedAt = endsAt
        }
    }

    private static func defaultLabel(for duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            return minutes % 60 == 0 ? "\(hours) h" : "\(hours) h \(minutes % 60) min"
        }
        return minutes > 0 ? "\(minutes) min" : "\(Int(duration)) s"
    }

    /// Preset durations offered in the UI.
    static let presets: [TimeInterval] = [60, 300, 600, 900, 1500, 2700, 3600]
}

/// Reduced-motion awareness, read once per view update rather than per frame.
enum MotionPreference {
    static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Continuous animation timelines collapse to a one-second tick when the
    /// user has asked for less motion: the timer stays accurate, it just stops
    /// moving between seconds.
    static var timelineInterval: Double { reducesMotion ? 1.0 : 1.0 / 30.0 }
}
