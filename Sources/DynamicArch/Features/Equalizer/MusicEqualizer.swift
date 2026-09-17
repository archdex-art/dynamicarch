import ApplicationServices
import AppKit

/// Drives Apple Music's built-in graphic equaliser.
///
/// Why this shape, empirically established on macOS 26 / Music 1.6.6:
///
/// - There is no public system-wide audio EQ on macOS. Changing what you hear
///   from outside a player means either shipping a CoreAudio driver (an
///   admin-installed HAL plug-in, which can wedge the whole audio stack) or
///   driving a player's own equaliser. This does the latter.
/// - Music's Apple Events interface *looks* like the right door and is not:
///   `EQ enabled` cannot be set (-10006) and `current EQ preset` can neither
///   be read nor written (-1728/-1731) on this version. Writing band values
///   into a preset object works, but Music only loads a preset's values into
///   the audio engine when the preset is *selected*, so edits to the live
///   preset are ignored.
/// - Music's own Equaliser window is the engine's control surface. Setting a
///   slider through Accessibility is exactly what a user dragging it does, and
///   it takes effect immediately - confirmed by reading the values back out of
///   Music's "Manual" preset over Apple Events after an Accessibility write.
///
/// So: Accessibility only. No Apple Events, no automation consent prompt, and
/// nothing is installed. The window is parked minimised, because it has to
/// exist for its controls to exist.
final class MusicEqualizer {
    static let shared = MusicEqualizer()

    enum Availability: Equatable {
        case ready
        case musicNotRunning
        case needsAccessibility
        /// Music is running but its equaliser could not be reached - a future
        /// redesign of that window, most likely.
        case unavailable
    }

    struct Reading: Equatable {
        var isEnabled: Bool
        var preamp: Double
        var gains: [Double]
    }

    /// Music's sliders carry decibels scaled by 100 (5.5 dB reads as 550).
    private static let scale: Double = 100
    /// Preamp plus ten bands.
    private static let sliderCount = EqualizerState.bandCount + 1
    /// ⌥⌘E opens the Equaliser in every localisation, so the menu item is
    /// found by its shortcut rather than by matching a translated title.
    private static let menuShortcut = "E"
    private static let menuModifiers = 2

    /// Serialises every Accessibility conversation; these are cross-process
    /// calls and must never run on the main thread.
    private let queue = DispatchQueue(label: "app.dynamicarch.equalizer", qos: .userInitiated)
    /// Set when we were the ones who opened the window, so we only minimise
    /// (and later close) a window the user did not ask for.
    private var openedByUs = false

    private init() {}

    // MARK: - Public surface

    func apply(_ state: EqualizerState, completion: @escaping (Availability) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let result = write(state)
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Reads Music's current curve so the island can show what is actually in
    /// effect - including changes the user made in Music itself.
    func read(completion: @escaping (Availability, Reading?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let (availability, reading) = readCurrent()
            DispatchQueue.main.async { completion(availability, reading) }
        }
    }

    /// Releases the window we opened. Called when the user turns the equaliser
    /// off, so we do not leave Music's UI parked in their Dock.
    func release() {
        queue.async { [weak self] in
            guard let self, openedByUs else { return }
            guard let window = equaliserWindow(open: false) else {
                openedByUs = false
                return
            }
            // The window publishes its own close button; asking for it by
            // attribute beats scanning children for a subrole.
            if let close = copy(window, kAXCloseButtonAttribute) as! AXUIElement? {
                AXUIElementPerformAction(close, kAXPressAction as CFString)
            }
            openedByUs = false
        }
    }

    // MARK: - Work

    private func write(_ state: EqualizerState) -> Availability {
        guard AXIsProcessTrusted() else { return .needsAccessibility }
        guard musicProcessIdentifier != nil else { return .musicNotRunning }
        guard let window = equaliserWindow(open: true) else { return .unavailable }
        let sliders = sliders(in: window)
        guard sliders.count == Self.sliderCount else { return .unavailable }

        let normalised = state.normalised
        set(slider: sliders[0], decibels: normalised.preamp)
        for index in 0..<EqualizerState.bandCount {
            set(slider: sliders[index + 1], decibels: normalised.gains[index])
        }
        setPower(in: window, on: normalised.isEnabled)
        return .ready
    }

    private func readCurrent() -> (Availability, Reading?) {
        guard AXIsProcessTrusted() else { return (.needsAccessibility, nil) }
        guard musicProcessIdentifier != nil else { return (.musicNotRunning, nil) }
        // Never opens the window: reading must not have a side effect on the
        // user's screen.
        guard let window = equaliserWindow(open: false) else { return (.unavailable, nil) }
        let sliders = sliders(in: window)
        guard sliders.count == Self.sliderCount else { return (.unavailable, nil) }

        let values = sliders.map { decibels(of: $0) }
        let power = checkbox(in: window).flatMap { value(of: $0) } ?? 0
        let reading = Reading(isEnabled: power != 0,
                              preamp: EqualizerState.quantise(values[0]),
                              gains: values.dropFirst().map(EqualizerState.quantise))
        return (.ready, reading)
    }

    // MARK: - Elements

    private var musicProcessIdentifier: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
            .first { !$0.isTerminated }?
            .processIdentifier
    }

    /// Finds the Equaliser window structurally - the window carrying a preamp
    /// plus ten band sliders - so no window title is ever matched against a
    /// localised string.
    private func equaliserWindow(open: Bool) -> AXUIElement? {
        guard let pid = musicProcessIdentifier else { return nil }
        let application = AXUIElementCreateApplication(pid)

        if let existing = findEqualiserWindow(in: application) { return existing }
        guard open, let item = equaliserMenuItem(in: application) else { return nil }

        AXUIElementPerformAction(item, kAXPressAction as CFString)
        // The window is created asynchronously; poll briefly rather than
        // sleeping for a fixed, guessed interval.
        for _ in 0..<20 {
            usleep(50_000)
            if let window = findEqualiserWindow(in: application) {
                openedByUs = true
                // Parked minimised: the controls have to exist to be driven,
                // but the user asked for an equaliser in the island, not for
                // Music's window on their screen.
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
                return window
            }
        }
        return nil
    }

    private func findEqualiserWindow(in application: AXUIElement) -> AXUIElement? {
        for window in children(of: application, attribute: kAXWindowsAttribute)
        where sliders(in: window).count == Self.sliderCount && checkbox(in: window) != nil {
            return window
        }
        return nil
    }

    /// The Window menu's ⌥⌘E item, wherever it happens to sit.
    private func equaliserMenuItem(in application: AXUIElement) -> AXUIElement? {
        guard let menuBar = copy(application, kAXMenuBarAttribute) as! AXUIElement? else { return nil }
        for barItem in children(of: menuBar, attribute: kAXChildrenAttribute) {
            for menu in children(of: barItem, attribute: kAXChildrenAttribute) {
                for item in children(of: menu, attribute: kAXChildrenAttribute) {
                    guard let character = copy(item, "AXMenuItemCmdChar") as? String,
                          character.caseInsensitiveCompare(Self.menuShortcut) == .orderedSame,
                          let modifiers = copy(item, "AXMenuItemCmdModifiers") as? Int,
                          modifiers == Self.menuModifiers
                    else { continue }
                    return item
                }
            }
        }
        return nil
    }

    private func sliders(in window: AXUIElement) -> [AXUIElement] {
        children(of: window, attribute: kAXChildrenAttribute).filter {
            (copy($0, kAXRoleAttribute) as? String) == kAXSliderRole
        }
    }

    private func checkbox(in window: AXUIElement) -> AXUIElement? {
        children(of: window, attribute: kAXChildrenAttribute).first {
            (copy($0, kAXRoleAttribute) as? String) == kAXCheckBoxRole
        }
    }

    // MARK: - Values

    private func set(slider: AXUIElement, decibels: Double) {
        let scaled = (decibels * Self.scale).rounded()
        AXUIElementSetAttributeValue(slider, kAXValueAttribute as CFString, NSNumber(value: scaled))
    }

    private func decibels(of slider: AXUIElement) -> Double {
        (value(of: slider) ?? 0) / Self.scale
    }

    private func value(of element: AXUIElement) -> Double? {
        (copy(element, kAXValueAttribute) as? NSNumber)?.doubleValue
    }

    /// The power tick box only responds to a press; setting its value is
    /// silently ignored, which is why this reads first and presses only on a
    /// mismatch instead of writing unconditionally.
    private func setPower(in window: AXUIElement, on: Bool) {
        guard let box = checkbox(in: window), let current = value(of: box) else { return }
        guard (current != 0) != on else { return }
        AXUIElementPerformAction(box, kAXPressAction as CFString)
    }

    // MARK: - Accessibility plumbing

    private func children(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        copy(element, attribute) as? [AXUIElement] ?? []
    }

    private func copy(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}
