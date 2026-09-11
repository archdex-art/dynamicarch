import AppKit
import SwiftUI

enum IslandDisplayTarget: String, CaseIterable, Identifiable, Codable {
    case builtIn, primary, followsMouse
    var id: String { rawValue }
    var title: String {
        switch self {
        case .builtIn: "Built-in display"
        case .primary: "Primary display"
        case .followsMouse: "Display with pointer"
        }
    }
}

/// User settings. Backed by UserDefaults, observed by SwiftUI, and readable
/// from any service without a dependency graph.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private var loaded = false

    // Shell
    var displayTarget: IslandDisplayTarget = .builtIn { didSet { persist(\.displayTarget) } }
    var openOnHover = false { didSet { persist(\.openOnHover) } }
    var closeOnPointerExit = true { didSet { persist(\.closeOnPointerExit) } }
    var hapticsEnabled = true { didSet { persist(\.hapticsEnabled) } }
    var activitiesEnabled = true { didSet { persist(\.activitiesEnabled) } }
    var gesturesEnabled = true { didSet { persist(\.gesturesEnabled) } }
    var hideFromScreenCapture = false { didSet { persist(\.hideFromScreenCapture) } }
    var theme: IslandTheme = .dark {
        didSet {
            // Mirror into the palette so every view - and the panel itself -
            // resolves colours against the active theme.
            Palette.theme = theme
            persist(\.theme)
        }
    }

    // Features
    var mediaEnabled = true { didSet { persist(\.mediaEnabled) } }
    var mediaVisualizer = true { didSet { persist(\.mediaVisualizer) } }
    var mediaCompactWhilePlaying = true { didSet { persist(\.mediaCompactWhilePlaying) } }
    var shelfEnabled = true { didSet { persist(\.shelfEnabled) } }
    var clipboardEnabled = true { didSet { persist(\.clipboardEnabled) } }
    var calendarEnabled = false { didSet { persist(\.calendarEnabled) } }
    var weatherEnabled = true { didSet { persist(\.weatherEnabled) } }
    var hudEnabled = true { didSet { persist(\.hudEnabled) } }
    var suppressSystemHUD = true { didSet { persist(\.suppressSystemHUD) } }
    var batteryEnabled = true { didSet { persist(\.batteryEnabled) } }
    var chargingAnimationEnabled = true { didSet { persist(\.chargingAnimationEnabled) } }
    var lowBatteryAlertEnabled = true { didSet { persist(\.lowBatteryAlertEnabled) } }
    /// Percentage at which the island starts warning. 20 % matches the system.
    var lowBatteryThreshold = 20 { didSet { persist(\.lowBatteryThreshold) } }
    /// Off by default: registering for Bluetooth events triggers a TCC
    /// prompt, which must never appear unasked at launch.
    var bluetoothEnabled = false { didSet { persist(\.bluetoothEnabled) } }
    var mirrorEnabled = false { didSet { persist(\.mirrorEnabled) } }
    var appsEnabled = true { didSet { persist(\.appsEnabled) } }
    /// Apps that bulk quit and force quit must never touch.
    var protectedBundleIdentifiers: [String] = [] {
        didSet { defaults.set(protectedBundleIdentifiers, forKey: "protectedBundleIdentifiers") }
    }
    /// Quit apps left untouched for this many minutes. 0 disables it.
    var autoQuitIdleMinutes = 0 {
        didSet {
            persist(\.autoQuitIdleMinutes)
            AppsStore.shared.reloadAutoQuitSchedule()
        }
    }
    var notificationsEnabled = false { didSet { persist(\.notificationsEnabled) } }
    var dismissSystemBanners = false { didSet { persist(\.dismissSystemBanners) } }

    // Shelf
    var shelfRetentionHours: Int = 24 { didSet { persist(\.shelfRetentionHours) } }
    var shelfCopiesFiles = true { didSet { persist(\.shelfCopiesFiles) } }

    private func persist<T>(_ key: KeyPath<Preferences, T>) {
        guard loaded, let name = Self.names[key] else { return }
        let value = self[keyPath: key]
        if let encodable = value as? any RawRepresentable, let raw = encodable.rawValue as? String {
            defaults.set(raw, forKey: name)
        } else {
            defaults.set(value, forKey: name)
        }
    }

    private static let names: [PartialKeyPath<Preferences>: String] = [
        \Preferences.displayTarget: "displayTarget",
        \Preferences.openOnHover: "openOnHover",
        \Preferences.closeOnPointerExit: "closeOnPointerExit",
        \Preferences.hapticsEnabled: "hapticsEnabled",
        \Preferences.activitiesEnabled: "activitiesEnabled",
        \Preferences.gesturesEnabled: "gesturesEnabled",
        \Preferences.hideFromScreenCapture: "hideFromScreenCapture",
        \Preferences.theme: "theme",
        \Preferences.appsEnabled: "appsEnabled",
        \Preferences.autoQuitIdleMinutes: "autoQuitIdleMinutes",
        \Preferences.mediaEnabled: "mediaEnabled",
        \Preferences.mediaVisualizer: "mediaVisualizer",
        \Preferences.mediaCompactWhilePlaying: "mediaCompactWhilePlaying",
        \Preferences.shelfEnabled: "shelfEnabled",
        \Preferences.clipboardEnabled: "clipboardEnabled",
        \Preferences.calendarEnabled: "calendarEnabled",
        \Preferences.weatherEnabled: "weatherEnabled",
        \Preferences.hudEnabled: "hudEnabled",
        \Preferences.suppressSystemHUD: "suppressSystemHUD",
        \Preferences.batteryEnabled: "batteryEnabled",
        \Preferences.chargingAnimationEnabled: "chargingAnimationEnabled",
        \Preferences.lowBatteryAlertEnabled: "lowBatteryAlertEnabled",
        \Preferences.lowBatteryThreshold: "lowBatteryThreshold",
        \Preferences.bluetoothEnabled: "bluetoothEnabled",
        \Preferences.mirrorEnabled: "mirrorEnabled",
        \Preferences.notificationsEnabled: "notificationsEnabled",
        \Preferences.dismissSystemBanners: "dismissSystemBanners",
        \Preferences.shelfRetentionHours: "shelfRetentionHours",
        \Preferences.shelfCopiesFiles: "shelfCopiesFiles",
    ]

    private init() {}

    func load() {
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) as? Bool ?? fallback
        }
        displayTarget = (defaults.string(forKey: "displayTarget").flatMap(IslandDisplayTarget.init)) ?? .builtIn
        openOnHover = bool("openOnHover", false)
        closeOnPointerExit = bool("closeOnPointerExit", true)
        hapticsEnabled = bool("hapticsEnabled", true)
        activitiesEnabled = bool("activitiesEnabled", true)
        gesturesEnabled = bool("gesturesEnabled", true)
        hideFromScreenCapture = bool("hideFromScreenCapture", false)
        theme = (defaults.string(forKey: "theme").flatMap(IslandTheme.init)) ?? .dark
        Palette.theme = theme
        appsEnabled = bool("appsEnabled", true)
        protectedBundleIdentifiers = defaults.stringArray(forKey: "protectedBundleIdentifiers") ?? []
        autoQuitIdleMinutes = defaults.object(forKey: "autoQuitIdleMinutes") as? Int ?? 0
        mediaEnabled = bool("mediaEnabled", true)
        mediaVisualizer = bool("mediaVisualizer", true)
        mediaCompactWhilePlaying = bool("mediaCompactWhilePlaying", true)
        shelfEnabled = bool("shelfEnabled", true)
        clipboardEnabled = bool("clipboardEnabled", true)
        calendarEnabled = bool("calendarEnabled", false)
        weatherEnabled = bool("weatherEnabled", true)
        hudEnabled = bool("hudEnabled", true)
        suppressSystemHUD = bool("suppressSystemHUD", true)
        batteryEnabled = bool("batteryEnabled", true)
        chargingAnimationEnabled = bool("chargingAnimationEnabled", true)
        lowBatteryAlertEnabled = bool("lowBatteryAlertEnabled", true)
        lowBatteryThreshold = defaults.object(forKey: "lowBatteryThreshold") as? Int ?? 20
        bluetoothEnabled = bool("bluetoothEnabled", false)
        mirrorEnabled = bool("mirrorEnabled", false)
        notificationsEnabled = bool("notificationsEnabled", false)
        dismissSystemBanners = bool("dismissSystemBanners", false)
        shelfRetentionHours = defaults.object(forKey: "shelfRetentionHours") as? Int ?? 24
        shelfCopiesFiles = bool("shelfCopiesFiles", true)
        loaded = true
    }
}
