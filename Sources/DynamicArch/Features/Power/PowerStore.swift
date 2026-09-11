import SwiftUI
import AppKit
import IOKit.ps

/// Battery level, charging state, and the transitions worth surfacing.
@MainActor
@Observable
final class PowerStore {
    static let shared = PowerStore()

    struct Snapshot: Equatable {
        var level: Double
        var isCharging: Bool
        var isPluggedIn: Bool
        var timeToEmpty: Int
        var timeToFull: Int
        var isLowPowerMode: Bool

        var symbolName: String {
            if isCharging { return "battery.100.bolt" }
            switch level {
            case ..<0.1: return "battery.0"
            case ..<0.35: return "battery.25"
            case ..<0.65: return "battery.50"
            case ..<0.9: return "battery.75"
            default: return "battery.100"
            }
        }

        var tint: Color {
            if isCharging { return Palette.positive }
            if level < 0.1 { return Palette.danger }
            if level < 0.2 { return Palette.warning }
            return Palette.secondaryText
        }

        @MainActor
        var isLowBattery: Bool {
            Int((level * 100).rounded()) <= Preferences.shared.lowBatteryThreshold
        }

        var remainingDescription: String? {
            let minutes = isCharging ? timeToFull : timeToEmpty
            guard minutes > 0 else { return nil }
            let hours = minutes / 60
            let mins = minutes % 60
            return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
        }
    }

    private(set) var snapshot: Snapshot?
    private var runLoopSource: CFRunLoopSource?
    private var lastPluggedIn: Bool?
    private var lowBatteryWarningIssued = false
    private var criticalWarningIssued = false

    private init() {}

    func start() {
        refresh()
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let store = Unmanaged<PowerStore>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in store.refresh() }
        }, context)?.takeRetainedValue() else { return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
    }

    func refresh() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                as? [String: Any] else { continue }
            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let state = description[kIOPSPowerSourceStateKey] as? String
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false

            let next = Snapshot(
                level: max > 0 ? Double(current) / Double(max) : 0,
                isCharging: charging,
                isPluggedIn: state == kIOPSACPowerValue,
                timeToEmpty: description[kIOPSTimeToEmptyKey] as? Int ?? -1,
                timeToFull: description[kIOPSTimeToFullChargeKey] as? Int ?? -1,
                isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
            )

            let previous = snapshot
            snapshot = next
            announce(previous: previous, next: next)
            return
        }
    }

    private func announce(previous: Snapshot?, next: Snapshot) {
        guard Preferences.shared.batteryEnabled else { return }
        let percent = Int((next.level * 100).rounded())

        // Plugged in or unplugged: the state change itself is the event.
        if let lastPluggedIn, lastPluggedIn != next.isPluggedIn {
            if next.isPluggedIn {
                if Preferences.shared.chargingAnimationEnabled {
                    present(state: next.level >= 0.995 ? .charged : .charging,
                            level: next.level,
                            detail: next.remainingDescription.map { "\($0) to full" },
                            duration: 3.4)
                }
            } else {
                present(state: next.isLowBattery ? .low : .unplugged,
                        level: next.level,
                        detail: next.remainingDescription.map { "\($0) remaining" },
                        duration: 2.8)
            }
            lowBatteryWarningIssued = next.isPluggedIn ? false : lowBatteryWarningIssued
        }
        lastPluggedIn = next.isPluggedIn

        // Reaching full while plugged in is worth one quiet confirmation.
        if next.isPluggedIn, next.level >= 0.995, previous.map({ $0.level < 0.995 }) ?? false {
            present(state: .charged, level: next.level, detail: nil, duration: 2.6)
        }

        guard !next.isPluggedIn, Preferences.shared.lowBatteryAlertEnabled else {
            if next.isPluggedIn { lowBatteryWarningIssued = false; criticalWarningIssued = false }
            return
        }

        // Warning at the user's threshold, then once more at a quarter of it
        // (floor 5 %), which is where "low" becomes "act now".
        let threshold = max(5, min(50, Preferences.shared.lowBatteryThreshold))
        let criticalThreshold = max(3, threshold / 4)

        if percent <= criticalThreshold, !criticalWarningIssued {
            criticalWarningIssued = true
            lowBatteryWarningIssued = true
            present(state: .critical, level: next.level,
                    detail: next.remainingDescription.map { "\($0) remaining" } ?? "Connect power now",
                    duration: 4.2)
        } else if percent <= threshold, !lowBatteryWarningIssued {
            lowBatteryWarningIssued = true
            present(state: .low, level: next.level,
                    detail: next.remainingDescription.map { "\($0) remaining" },
                    duration: 3.6)
        } else if percent > threshold + 3 {
            // Hysteresis: only re-arm once the charge is clearly back above the
            // threshold, so a battery hovering on the line cannot spam.
            lowBatteryWarningIssued = false
            criticalWarningIssued = false
        }
    }

    private func present(state: IslandActivity.BatteryState,
                         level: Double,
                         detail: String?,
                         duration: TimeInterval) {
        ActivityCenter.shared.present(
            IslandActivity(kind: state.isWarning ? .battery : .power,
                           content: .battery(level: level, state: state, detail: detail),
                           duration: duration)
        )
        Haptics.tap()
    }
}
