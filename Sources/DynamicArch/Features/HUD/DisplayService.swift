import AppKit

/// Display brightness and keyboard backlight through the same private
/// interfaces the system HUD itself uses. Everything is resolved with dlsym at
/// runtime and degrades to "unsupported" rather than crashing if Apple moves it.
@MainActor
final class DisplayService {
    static let shared = DisplayService()

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChangeBrightness = @convention(c) (CGDirectDisplayID) -> Bool

    private var getBrightness: GetBrightness?
    private var setBrightnessFn: SetBrightness?
    private var canChange: CanChangeBrightness?

    private var keyboardClient: AnyObject?

    private init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        if let handle {
            getBrightness = dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetBrightness.self) }
            setBrightnessFn = dlsym(handle, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetBrightness.self) }
            canChange = dlsym(handle, "DisplayServicesCanChangeBrightness").map { unsafeBitCast($0, to: CanChangeBrightness.self) }
        }

        // Keyboard backlight lives in CoreBrightness; the class is ObjC so we
        // can reach it without a header.
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        if let clientClass = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
            keyboardClient = clientClass.init()
        }
    }

    var supportsBrightness: Bool { getBrightness != nil }

    func brightness(for displayID: CGDirectDisplayID = CGMainDisplayID()) -> Double? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        guard getBrightness(displayID, &value) == 0 else { return nil }
        return Double(value)
    }

    func setBrightness(_ value: Double, for displayID: CGDirectDisplayID = CGMainDisplayID()) {
        guard let setBrightnessFn else { return }
        if let canChange, !canChange(displayID) { return }
        _ = setBrightnessFn(displayID, Float(max(0, min(1, value))))
    }

    var supportsKeyboardBacklight: Bool {
        guard let keyboardClient else { return false }
        return keyboardClient.responds(to: NSSelectorFromString("brightnessForKeyboard:"))
    }

    func keyboardBacklight() -> Double? {
        guard let keyboardClient,
              keyboardClient.responds(to: NSSelectorFromString("brightnessForKeyboard:"))
        else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector, UInt64) -> Float
        let selector = NSSelectorFromString("brightnessForKeyboard:")
        guard let implementation = keyboardClient.method(for: selector) else { return nil }
        let function = unsafeBitCast(implementation, to: Getter.self)
        return Double(function(keyboardClient, selector, 1))
    }

    func setKeyboardBacklight(_ value: Double) {
        guard let keyboardClient else { return }
        let selector = NSSelectorFromString("setBrightness:forKeyboard:")
        guard keyboardClient.responds(to: selector),
              let implementation = keyboardClient.method(for: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Float, UInt64) -> Void
        let function = unsafeBitCast(implementation, to: Setter.self)
        function(keyboardClient, selector, Float(max(0, min(1, value))), 1)
    }
}
