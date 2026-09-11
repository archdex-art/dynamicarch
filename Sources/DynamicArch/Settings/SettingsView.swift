import SwiftUI

struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general, appearance, features, shelf, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: "General"
            case .appearance: "Appearance"
            case .features: "Features"
            case .shelf: "Shelf"
            case .about: "About"
            }
        }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .appearance: "paintpalette"
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
                case .appearance: AppearanceSettings(preferences: preferences)
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

/// Theme picker with live previews, so the choice is made by looking rather
/// than by reading.
private struct AppearanceSettings: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section("Theme") {
                HStack(spacing: 12) {
                    ForEach(IslandTheme.allCases) { theme in
                        ThemeSwatch(theme: theme, selected: preferences.theme == theme) {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                preferences.theme = theme
                            }
                            Services.shared.refresh()
                        }
                    }
                }
                .padding(.vertical, 4)

                Text(preferences.theme.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Island") {
                Toggle("Hide from screen recordings", isOn: $preferences.hideFromScreenCapture)
                Toggle("Waveform visualiser", isOn: $preferences.mediaVisualizer)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ThemeSwatch: View {
    let theme: IslandTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(background)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12),
                                          lineWidth: selected ? 2 : 1)
                    }
                if theme == .glass {
                    // Hint of what glass does: a bright rim over a blurred
                    // gradient, the same recipe as the real surface.
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.15)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1
                        )
                        .padding(3)
                }
                Capsule()
                    .fill(theme == .light ? Color.black.opacity(0.75) : Color.white.opacity(0.85))
                    .frame(width: 34, height: 9)
                Image(systemName: theme.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme == .light ? .black : .white)
                    .offset(y: 20)
            }
            .frame(width: 92, height: 62)

            Text(theme.title)
                .font(.caption)
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    private var background: AnyShapeStyle {
        switch theme {
        case .dark:
            AnyShapeStyle(Color.black)
        case .light:
            AnyShapeStyle(Color(white: 0.95))
        case .glass:
            AnyShapeStyle(
                LinearGradient(colors: [Color.teal.opacity(0.55), Color.purple.opacity(0.45)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        }
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
            Section("Battery") {
                Toggle("Battery and charging activities", isOn: $preferences.batteryEnabled)
                Toggle("Charging animation", isOn: $preferences.chargingAnimationEnabled)
                    .disabled(!preferences.batteryEnabled)
                Toggle("Low battery alert", isOn: $preferences.lowBatteryAlertEnabled)
                    .disabled(!preferences.batteryEnabled)
                Picker("Warn below", selection: $preferences.lowBatteryThreshold) {
                    ForEach([10, 15, 20, 25, 30, 40, 50], id: \.self) { value in
                        Text("\(value)%").tag(value)
                    }
                }
                .disabled(!preferences.batteryEnabled || !preferences.lowBatteryAlertEnabled)
                Text("A second, louder warning follows at a quarter of this level.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("System") {
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
            Section("Running apps") {
                Toggle("Apps section", isOn: $preferences.appsEnabled)
                Picker("Quit idle apps after", selection: $preferences.autoQuitIdleMinutes) {
                    Text("Never").tag(0)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("3 hours").tag(180)
                }
                .disabled(!preferences.appsEnabled)
                Text("Idle apps are always quit the normal way, so they can still ask you to save. Protected and system apps are never touched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !preferences.protectedBundleIdentifiers.isEmpty {
                    LabeledContent("Protected") {
                        Text("\(preferences.protectedBundleIdentifiers.count) app\(preferences.protectedBundleIdentifiers.count == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                    }
                    Button("Clear protected apps") { preferences.protectedBundleIdentifiers = [] }
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
