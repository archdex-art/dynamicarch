import AppKit
import Observation

/// Owns the equaliser curve and pushes it to Apple Music.
///
/// The curve is the app's own state and survives Music not being open: a
/// preset chosen with Music closed is stored and applied the moment it can be.
/// Writes are coalesced, because dragging a band emits a value per frame and
/// each apply is a cross-process Accessibility conversation.
@MainActor
@Observable
final class EqualizerStore {
    static let shared = EqualizerStore()

    private(set) var state: EqualizerState
    private(set) var availability: MusicEqualizer.Availability = .musicNotRunning
    /// Set while a band is being dragged, so the curve follows the finger
    /// exactly instead of being animated toward each intermediate value.
    var isAdjusting = false

    private var pendingApply: DispatchWorkItem?
    private var launchObserver: NSObjectProtocol?

    /// One frame at 120 Hz is 8 ms; 40 ms coalesces a drag into a handful of
    /// writes while still feeling immediate.
    private static let applyDelay: TimeInterval = 0.04

    private init() {
        state = Preferences.shared.equalizerState.normalised
        observeMusicLaunches()
    }

    // MARK: - Status

    var activePreset: EqualizerPreset? { EqualizerPreset.preset(id: state.presetID) }

    /// What the island tells the user, in plain terms. The equaliser applies
    /// to Apple Music playback only - macOS has no system-wide audio EQ for a
    /// third-party app to hook into - and pretending otherwise would be worse
    /// than saying so.
    var statusDescription: String {
        switch availability {
        case .needsAccessibility: "Needs Accessibility access"
        case .musicNotRunning: "Apple Music is not running"
        case .unavailable: "Music's equaliser is unavailable"
        case .ready: state.isEnabled ? "Live in Apple Music" : "Off"
        }
    }

    var isLive: Bool { availability == .ready && state.isEnabled }

    /// True when something other than Music is playing, which the equaliser
    /// cannot affect. Surfaced in the UI rather than failing quietly.
    var otherPlayerIsActive: Bool {
        guard let bundle = MediaStore.shared.track?.bundleIdentifier else { return false }
        return bundle != "com.apple.Music"
    }

    // MARK: - Editing

    func setEnabled(_ enabled: Bool) {
        state.isEnabled = enabled
        persist()
        if enabled {
            apply(immediately: true)
        } else {
            // Turn Music's unit off first, then let go of its window.
            apply(immediately: true) { MusicEqualizer.shared.release() }
        }
    }

    func select(_ preset: EqualizerPreset) {
        state.presetID = preset.id
        state.gains = preset.gains.map(EqualizerState.quantise)
        state.preamp = EqualizerState.quantise(preset.preamp)
        persist()
        apply(immediately: true)
    }

    func setGain(_ value: Double, forBand index: Int) {
        guard state.gains.indices.contains(index) else { return }
        let quantised = EqualizerState.quantise(value)
        guard state.gains[index] != quantised else { return }
        state.gains[index] = quantised
        // The curve is the user's own the moment they move a band.
        state.presetID = nil
        persist()
        apply()
    }

    func setPreamp(_ value: Double) {
        let quantised = EqualizerState.quantise(value)
        guard state.preamp != quantised else { return }
        state.preamp = quantised
        state.presetID = nil
        persist()
        apply()
    }

    func reset() {
        if let flat = EqualizerPreset.preset(id: "flat") {
            select(flat)
        }
    }

    // MARK: - Syncing

    /// Called when the section appears: adopts whatever is actually in Music,
    /// so a curve the user set there does not get silently overwritten by a
    /// stale copy of ours.
    func sync() {
        MusicEqualizer.shared.read { [weak self] availability, reading in
            guard let self else { return }
            self.availability = availability
            guard let reading else { return }
            guard reading.gains.count == EqualizerState.bandCount else { return }
            // Ours wins while the user is dragging; theirs wins otherwise.
            guard !isAdjusting else { return }
            if reading.gains != state.gains || reading.preamp != state.preamp {
                state.gains = reading.gains
                state.preamp = reading.preamp
                state.presetID = Self.matchingPresetID(gains: reading.gains, preamp: reading.preamp)
            }
            state.isEnabled = reading.isEnabled
            persist()
        }
    }

    /// Recognises a curve that matches a preset exactly, so adopting Music's
    /// state still highlights the right chip.
    private static func matchingPresetID(gains: [Double], preamp: Double) -> String? {
        EqualizerPreset.all.first {
            $0.gains.map(EqualizerState.quantise) == gains
                && EqualizerState.quantise($0.preamp) == preamp
        }?.id
    }

    private func observeMusicLaunches() {
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { note in
            MainActor.assumeIsolated {
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == "com.apple.Music"
                else { return }
                // Music just appeared: push the stored curve into it.
                let store = EqualizerStore.shared
                guard store.state.isEnabled else {
                    store.availability = .ready
                    return
                }
                store.apply(immediately: true)
            }
        }
    }

    // MARK: - Applying

    private func apply(immediately: Bool = false, then completion: (() -> Void)? = nil) {
        pendingApply?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            MusicEqualizer.shared.apply(state) { [weak self] result in
                self?.availability = result
                completion?()
            }
        }
        pendingApply = work
        if immediately {
            work.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.applyDelay, execute: work)
        }
    }

    private func persist() {
        Preferences.shared.equalizerState = state
    }
}
