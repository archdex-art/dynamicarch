import AppKit

/// Starts and stops every background feature in one place, so the app has a
/// single, auditable lifecycle.
@MainActor
final class Services {
    static let shared = Services()

    private var pointer: PointerTracker?

    private init() {}

    /// Set by the app delegate so preference changes can reach the panel.
    weak var displays: DisplayCoordinator?

    func start(model: IslandModel) {
        ActivityCenter.shared.attach(model: model)

        pointer = PointerTracker(model: model)
        pointer?.start()
        model.startInteractivityGuard()

        AppsStore.shared.start()
        TimerStore.shared.start()
        ShelfStore.shared.start()
        ShelfStore.shared.validate()

        if Preferences.shared.mediaEnabled { MediaStore.shared.start() }
        if Preferences.shared.hudEnabled {
            AudioService.shared.start()
            HUDService.shared.start()
        }
        if Preferences.shared.batteryEnabled { PowerStore.shared.start() }
        if Preferences.shared.bluetoothEnabled { BluetoothService.shared.start() }
        if Preferences.shared.clipboardEnabled { ClipboardStore.shared.start() }
        if Preferences.shared.calendarEnabled { CalendarStore.shared.start() }
        if Preferences.shared.weatherEnabled { WeatherStore.shared.start() }
        if Preferences.shared.notificationsEnabled { NotificationMirror.shared.start() }
        ShortcutsStore.shared.refresh()
    }

    /// Brings running services in line with the current preferences. Safe to
    /// call repeatedly: every service's start/stop is idempotent, so a settings
    /// toggle takes effect immediately instead of at the next launch.
    func refresh() {
        let preferences = Preferences.shared
        displays?.updateCaptureVisibility()
        displays?.applyTheme()

        preferences.mediaEnabled ? MediaStore.shared.start() : MediaStore.shared.stop()

        if preferences.hudEnabled {
            AudioService.shared.start()
            HUDService.shared.start()
        } else {
            AudioService.shared.stop()
            HUDService.shared.stop()
        }

        preferences.batteryEnabled ? PowerStore.shared.start() : PowerStore.shared.stop()
        preferences.bluetoothEnabled ? BluetoothService.shared.start() : BluetoothService.shared.stop()
        preferences.clipboardEnabled ? ClipboardStore.shared.start() : ClipboardStore.shared.stop()
        preferences.calendarEnabled ? CalendarStore.shared.start() : CalendarStore.shared.stop()
        preferences.weatherEnabled ? WeatherStore.shared.start() : WeatherStore.shared.stop()
        preferences.notificationsEnabled ? NotificationMirror.shared.start() : NotificationMirror.shared.stop()
    }

    func stop() {
        IslandModel.shared.stopInteractivityGuard()
        pointer?.stop()
        MediaStore.shared.stop()
        AudioService.shared.stop()
        HUDService.shared.stop()
        PowerStore.shared.stop()
        BluetoothService.shared.stop()
        ClipboardStore.shared.stop()
        CalendarStore.shared.stop()
        WeatherStore.shared.stop()
        ShelfStore.shared.stop()
        AppsStore.shared.stop()
        TimerStore.shared.stop()
        NotificationMirror.shared.stop()
    }
}
