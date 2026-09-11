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
    private var lastLowBatteryWarning: Int?

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

        // Charger plugged in or pulled out.
        if let lastPluggedIn, lastPluggedIn != next.isPluggedIn {
            let title = next.isPluggedIn ? "Charging" : "On Battery"
            let subtitle = next.remainingDescription.map {
                next.isPluggedIn ? "\($0) to full" : "\($0) left"
            } ?? "\(Int(next.level * 100))%"
            ActivityCenter.shared.present(
                IslandActivity(kind: .power,
                               content: .badge(symbol: next.isPluggedIn ? "bolt.fill" : "battery.50",
                                               image: nil,
                                               title: title,
                                               subtitle: subtitle,
                                               tint: next.isPluggedIn ? Palette.positive : Palette.secondaryText),
                               duration: 2.8)
            )
        }
        lastPluggedIn = next.isPluggedIn

        // Low battery thresholds, once each.
        let percent = Int(next.level * 100)
        for threshold in [20, 10, 5] where percent <= threshold && !next.isPluggedIn {
            if lastLowBatteryWarning == threshold { break }
            lastLowBatteryWarning = threshold
            ActivityCenter.shared.present(
                IslandActivity(kind: .battery,
                               content: .badge(symbol: "battery.25",
                                               image: nil,
                                               title: "\(percent)% Battery",
                                               subtitle: next.remainingDescription.map { "\($0) left" },
                                               tint: threshold <= 10 ? Palette.danger : Palette.warning),
                               duration: 3.4)
            )
            break
        }
        if next.isPluggedIn { lastLowBatteryWarning = nil }
    }
}
