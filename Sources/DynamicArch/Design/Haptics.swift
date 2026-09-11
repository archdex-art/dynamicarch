import AppKit

/// Trackpad haptics. Cheap, throttled, and silent on machines without a
/// haptic-capable trackpad.
@MainActor
enum Haptics {
    private static var lastFire: TimeInterval = 0

    private static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern, minInterval: TimeInterval) {
        guard Preferences.shared.hapticsEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFire > minInterval else { return }
        lastFire = now
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    static func tick() { perform(.alignment, minInterval: 0.35) }
    static func tap() { perform(.levelChange, minInterval: 0.12) }
    static func success() { perform(.generic, minInterval: 0.12) }
}
