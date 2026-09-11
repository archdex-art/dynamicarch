import AppKit
import SwiftUI

/// Replaces the system's translucent square with an island activity.
///
/// The hardware keys are observed as `.systemDefined` events (no Accessibility
/// permission required); the resulting value is read back from the real system
/// state so third-party changes and Control Centre stay in sync.
@MainActor
final class HUDService {
    static let shared = HUDService()

    enum Event {
        case volume(level: Double, muted: Bool)
        case brightness(level: Double)
        case keyboardBacklight(level: Double)
    }

    private var keyMonitor: GlobalEventMonitor?
    private var pollTimer: Timer?
    private var lastBrightness: Double?
    private var lastKeyboardBacklight: Double?

    private init() {}

    func start() {
        guard keyMonitor == nil else { return }
        keyMonitor = GlobalEventMonitor(mask: [.systemDefined]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(systemEvent: event) }
        }
        keyMonitor?.start()
        lastBrightness = DisplayService.shared.brightness()
        lastKeyboardBacklight = DisplayService.shared.keyboardBacklight()
    }

    func stop() {
        keyMonitor?.stop()
        keyMonitor = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // NX_SYSDEFINED subtype 8 carries the media/function keys.
    private enum KeyType: Int {
        case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3
        case mute = 7, illuminationUp = 21, illuminationDown = 22, illuminationToggle = 23
    }

    private func handle(systemEvent event: NSEvent) {
        guard Preferences.shared.hudEnabled, event.subtype.rawValue == 8 else { return }
        let data = event.data1
        let keyCode = Int((data & 0xFFFF_0000) >> 16)
        let keyState = ((data & 0xFF00) >> 8) == 0x0A  // key down
        guard keyState, let key = KeyType(rawValue: keyCode) else { return }

        switch key {
        case .soundUp, .soundDown, .mute:
            // The system applies the change itself; read it back a beat later.
            scheduleSample(.volume)
        case .brightnessUp, .brightnessDown:
            scheduleSample(.brightness)
        case .illuminationUp, .illuminationDown, .illuminationToggle:
            scheduleSample(.keyboard)
        }

        OSDSuppressor.shared.suppress()
    }

    private enum Sample { case volume, brightness, keyboard }

    private func scheduleSample(_ sample: Sample) {
        // Two reads: one immediately after the system applies the step, one
        // slightly later to catch key-repeat runs.
        for delay in [0.02, 0.12] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                switch sample {
                case .volume:
                    let audio = AudioService.shared
                    present(.volume(level: Double(audio.currentVolume()), muted: audio.currentMute()))
                case .brightness:
                    guard let level = DisplayService.shared.brightness() else { return }
                    present(.brightness(level: level))
                case .keyboard:
                    guard let level = DisplayService.shared.keyboardBacklight() else { return }
                    present(.keyboardBacklight(level: level))
                }
            }
        }
    }

    func present(_ event: Event) {
        guard Preferences.shared.hudEnabled else { return }
        switch event {
        case .volume(let level, let muted):
            let symbol = muted || level < 0.001 ? "speaker.slash.fill"
                : level < 0.33 ? "speaker.wave.1.fill"
                : level < 0.66 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
            ActivityCenter.shared.present(
                IslandActivity(kind: .volume,
                               content: .level(symbol: symbol,
                                               value: muted ? 0 : level,
                                               tint: .white,
                                               label: nil),
                               duration: 1.5)
            )
        case .brightness(let level):
            guard lastBrightness.map({ abs($0 - level) > 0.001 }) ?? true else { return }
            lastBrightness = level
            ActivityCenter.shared.present(
                IslandActivity(kind: .brightness,
                               content: .level(symbol: "sun.max.fill", value: level, tint: .white, label: nil),
                               duration: 1.5)
            )
        case .keyboardBacklight(let level):
            guard lastKeyboardBacklight.map({ abs($0 - level) > 0.001 }) ?? true else { return }
            lastKeyboardBacklight = level
            ActivityCenter.shared.present(
                IslandActivity(kind: .keyboardBacklight,
                               content: .level(symbol: "keyboard.fill", value: level, tint: .white, label: nil),
                               duration: 1.5)
            )
        }
    }
}

/// The system OSD is a separate on-demand agent. When our HUD is on, we stop it
/// from painting over the screen; the moment the feature is switched off the
/// system takes over again with no cleanup needed.
@MainActor
final class OSDSuppressor {
    static let shared = OSDSuppressor()

    private var lastKill: TimeInterval = 0

    private init() {}

    func suppress() {
        guard Preferences.shared.suppressSystemHUD, Preferences.shared.hudEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastKill > 0.05 else { return }
        lastKill = now
        Task.detached(priority: .userInitiated) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            task.arguments = ["-9", "OSDUIHelper"]
            task.standardError = FileHandle.nullDevice
            task.standardOutput = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }
    }
}
