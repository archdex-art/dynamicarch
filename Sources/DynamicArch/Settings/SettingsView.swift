import SwiftUI

struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general, features, shelf, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: "General"
            case .features: "Features"
            case .shelf: "Shelf"
            case .about: "About"
            }
        }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .features: "square.grid.2x2"
            case .shelf: "tray.full"
            case .about: "info.circle"
            }
        }
    }

    @State private var preferences = Preferences.shared
    @State private var section: Section = .general
    @State private var permissions = PermissionSnapshot()

    var body: some View {
        VStack(spacing: 0) {
            // An explicit picker rather than TabView: on macOS 26 a hosted
            // TabView renders its tabs into the window toolbar, where they draw
            // correctly but never receive clicks.
            Picker("", selection: $section) {
                ForEach(Section.allCases) { item in
                    Text(item.title)
                        .accessibilityLabel(item.title)
                        .tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            Group {
                switch section {
                case .general: GeneralSettings(preferences: preferences, permissions: $permissions)
                case .features: FeatureSettings(preferences: preferences, permissions: $permissions)
                case .shelf: ShelfSettings(preferences: preferences)
                case .about: AboutSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 560, minHeight: 560)
        // Any switch flipped here starts or stops the matching service now, and
        // only then does its permission prompt appear.
        .onChange(of: featureFingerprint) { _, _ in
            Services.shared.refresh()
            permissions.refresh()
        }
        .onAppear { permissions.refresh() }
    }

    private var featureFingerprint: String {
        [preferences.mediaEnabled, preferences.hudEnabled, preferences.batteryEnabled,
         preferences.bluetoothEnabled, preferences.clipboardEnabled, preferences.calendarEnabled,
         preferences.weatherEnabled, preferences.notificationsEnabled, preferences.mirrorEnabled]
            .map { $0 ? "1" : "0" }.joined()
    }
}

/// System permission and login-item state.
///
/// `AXIsProcessTrusted()` and `SMAppService.status` are cross-process calls.
/// Reading them from inside a view body means SwiftUI performs IPC on the main
/// thread on every layout pass, which is exactly how a settings pane ends up
/// beachballing. They are sampled here instead, on appear and after a change.
@MainActor
struct PermissionSnapshot {
    var accessibilityTrusted = false
    var launchAtLogin = false

    mutating func refresh() {
        accessibilityTrusted = NotificationMirror.isTrusted
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}

private struct GeneralSettings: View {
    @Bindable var preferences: Preferences
    @Binding var permissions: PermissionSnapshot

    var body: some View {
        Form {
            Section("Island") {
                Picker("Show on", selection: $preferences.displayTarget) {
                    ForEach(IslandDisplayTarget.allCases) { target in
                        Text(target.title).tag(target)
                    }
                }
                Toggle("Open on hover", isOn: $preferences.openOnHover)
                Toggle("Close when the pointer leaves", isOn: $preferences.closeOnPointerExit)
                Toggle("Scroll and swipe gestures", isOn: $preferences.gesturesEnabled)
                Toggle("Haptic feedback", isOn: $preferences.hapticsEnabled)
                Toggle("Hide from screen recordings", isOn: $preferences.hideFromScreenCapture)
            }

            Section("Live activities") {
                Toggle("Show live activities", isOn: $preferences.activitiesEnabled)
                Toggle("Replace the system volume and brightness HUD", isOn: $preferences.hudEnabled)
                Toggle("Suppress the macOS HUD overlay", isOn: $preferences.suppressSystemHUD)
                    .disabled(!preferences.hudEnabled)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { permissions.launchAtLogin },
                    set: { _ in
                        LaunchAtLogin.toggle()
                        permissions.refresh()
                    }
                ))
            }
        }
        .formStyle(.grouped)
    }
}

private struct FeatureSettings: View {
    @Bindable var preferences: Preferences
    @Binding var permissions: PermissionSnapshot

    var body: some View {
        Form {
            Section("Media") {
                Toggle("Now Playing", isOn: $preferences.mediaEnabled)
                Toggle("Waveform visualiser", isOn: $preferences.mediaVisualizer)
                Toggle("Show artwork around the notch while playing", isOn: $preferences.mediaCompactWhilePlaying)
            }
            Section("System") {
                Toggle("Battery and charging", isOn: $preferences.batteryEnabled)
                Toggle("Bluetooth devices", isOn: $preferences.bluetoothEnabled)
            }
            Section("Notifications & calls") {
                Toggle("Mirror notifications and calls in the island", isOn: $preferences.notificationsEnabled)
                Toggle("Dismiss the duplicate system banner", isOn: $preferences.dismissSystemBanners)
                    .disabled(!preferences.notificationsEnabled)
                if preferences.notificationsEnabled, permissions.accessibilityTrusted == false {
                    HStack {
                        Text("Requires Accessibility access")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Grant Access") {
                            NotificationMirror.requestTrust()
                            permissions.refresh()
                        }
                    }
                }
            }
            Section("Panels") {
                Toggle("File shelf", isOn: $preferences.shelfEnabled)
                Toggle("Clipboard history", isOn: $preferences.clipboardEnabled)
                Toggle("Calendar", isOn: $preferences.calendarEnabled)
                Toggle("Weather", isOn: $preferences.weatherEnabled)
                Toggle("Camera mirror", isOn: $preferences.mirrorEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShelfSettings: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section("Storage") {
                Toggle("Copy files into the shelf", isOn: $preferences.shelfCopiesFiles)
                Text("Copies keep working after the original is moved, renamed, or deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Keep items for", selection: $preferences.shelfRetentionHours) {
                    Text("1 hour").tag(1)
                    Text("12 hours").tag(12)
                    Text("1 day").tag(24)
                    Text("3 days").tag(72)
                    Text("1 week").tag(168)
                    Text("Forever").tag(0)
                }
            }
            Section {
                Button("Clear the shelf now", role: .destructive) { ShelfStore.shared.removeAll() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "capsule.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("DynamicArch")
                .font(.title2.bold())
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .foregroundStyle(.secondary)
            Text("A dynamic island for macOS: media, live activities, a file shelf, clipboard, calendar, weather, and a mirror - all in the notch.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            Spacer()
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
