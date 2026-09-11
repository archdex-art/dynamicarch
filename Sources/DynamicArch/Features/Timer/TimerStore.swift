import AppKit
import Foundation
import SwiftUI

/// A timer that wraps the island. Deliberately self-contained: the system Clock
/// app exposes no API to observe its timers, and inventing one would be a lie.
@MainActor
@Observable
final class TimerStore {
    static let shared = TimerStore()

    struct Running: Equatable {
        var label: String
        var total: TimeInterval
        var endsAt: Date
        var paused: Bool
        var pausedRemaining: TimeInterval

        var remaining: TimeInterval {
            paused ? pausedRemaining : max(0, endsAt.timeIntervalSinceNow)
        }

        var fraction: Double {
            guard total > 0 else { return 0 }
            return 1 - min(1, max(0, remaining / total))
        }

        var display: String {
            let seconds = Int(remaining.rounded())
            let hours = seconds / 3600
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, (seconds % 3600) / 60, seconds % 60)
            }
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
    }

    private(set) var running: Running?
    private var ticker: Timer?

    private init() {}

    func start(duration: TimeInterval, label: String = "Timer") {
        running = Running(label: label, total: duration, endsAt: .now.addingTimeInterval(duration),
                          paused: false, pausedRemaining: duration)
        installTicker()
        announce()
    }

    func pause() {
        guard var current = running, !current.paused else { return }
        current.pausedRemaining = current.remaining
        current.paused = true
        running = current
        announce()
    }

    func resume() {
        guard var current = running, current.paused else { return }
        current.endsAt = .now.addingTimeInterval(current.pausedRemaining)
        current.paused = false
        running = current
        installTicker()
        announce()
    }

    func cancel() {
        running = nil
        ticker?.invalidate()
        ticker = nil
        ActivityCenter.shared.dismiss(kind: .timer)
    }

    private func installTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let current = self.running else { return }
                if current.remaining <= 0 { self.fire() }
            }
        }
    }

    private func fire() {
        ticker?.invalidate()
        ticker = nil
        running = nil
        ActivityCenter.shared.present(
            IslandActivity(kind: .timer,
                           content: .badge(symbol: "timer", image: nil, title: "Time's up",
                                           subtitle: nil, tint: Palette.warning),
                           duration: 4)
        )
        NSSound(named: "Glass")?.play()
    }

    private func announce() {
        guard let current = running else { return }
        ActivityCenter.shared.present(
            IslandActivity(kind: .timer,
                           content: .progress(symbol: "timer", fraction: current.fraction,
                                              label: current.display, tint: Palette.warning),
                           duration: 2)
        )
    }
}
