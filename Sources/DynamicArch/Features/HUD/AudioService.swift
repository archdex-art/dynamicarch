import AppKit
import AudioToolbox
import CoreAudio

/// System output volume: read it, write it, and know the instant it changes -
/// including changes made by the hardware keys, Control Centre, or another app.
@MainActor
final class AudioService {
    static let shared = AudioService()

    private(set) var volume: Float = 0
    private(set) var isMuted = false
    private var deviceID = AudioDeviceID(0)
    private var listening = false
    private var listenedAddresses: [AudioObjectPropertyAddress] = []

    private init() {}

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    func start() {
        guard !listening else { return }
        // The HAL creates its proxy objects lazily. Registering a listener on a
        // device the process has never enumerated silently produces a dead
        // listener ("HALC_Object_PropertyListener: not initialized"), so we
        // force the object graph to exist first and register afterwards.
        primeHardwareAbstractionLayer()
        refreshDevice()
        installDefaultDeviceListener()
    }

    private func primeHardwareAbstractionLayer() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr, size > 0 else { return }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &devices) == noErr else { return }
        // Touching a property on each device is what actually instantiates the
        // proxy objects that listeners attach to.
        for device in devices {
            var name = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
            var value: CFString = "" as CFString
            var valueSize = UInt32(MemoryLayout<CFString?>.size)
            _ = withUnsafeMutablePointer(to: &value) { pointer in
                AudioObjectGetPropertyData(device, &name, 0, nil, &valueSize, pointer)
            }
        }
    }

    func stop() {
        removeDeviceListeners()
        AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject),
                                          &Self.defaultDeviceAddress,
                                          Self.deviceListener,
                                          Unmanaged.passUnretained(self).toOpaque())
    }

    // MARK: - Values

    func currentVolume() -> Float {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &Self.volumeAddress, 0, nil, &size, &value)
        return status == noErr ? value : volume
    }

    func currentMute() -> Bool {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &Self.muteAddress, 0, nil, &size, &value)
        return status == noErr ? value == 1 : isMuted
    }

    func setVolume(_ newValue: Float) {
        var value = max(0, min(1, newValue))
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(deviceID, &Self.volumeAddress, 0, nil, size, &value)
        volume = value
    }

    func setMuted(_ muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(deviceID, &Self.muteAddress, 0, nil, size, &value)
        isMuted = muted
    }

    var outputDeviceName: String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? (name as String) : "Output"
    }

    // MARK: - Listeners

    private func refreshDevice() {
        removeDeviceListeners()
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &Self.defaultDeviceAddress, 0, nil, &size, &device)
        guard status == noErr else { return }
        deviceID = device
        volume = currentVolume()
        isMuted = currentMute()
        installDeviceListeners()
    }

    /// `VirtualMainVolume` is an AudioToolbox convenience that reads and writes
    /// fine but never posts notifications. Change notifications come from the
    /// real device properties: the master element and the individual channels,
    /// because which of them a device actually publishes varies by hardware.
    private static func scalarAddress(element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: element)
    }

    private static let listenedElements: [UInt32] = [kAudioObjectPropertyElementMain, 1, 2]

    /// Registered with the C-callback API rather than the block API: the block
    /// variant silently never fires for this process, and a plain function
    /// pointer plus a context pointer has no bridging ambiguity at all.
    private static let listener: AudioObjectPropertyListenerProc = { _, _, _, context in
        guard let context else { return noErr }
        let service = Unmanaged<AudioService>.fromOpaque(context).takeUnretainedValue()
        DispatchQueue.main.async { MainActor.assumeIsolated { service.volumeChanged() } }
        return noErr
    }

    fileprivate func volumeChanged() {
        let value = currentVolume()
        let muted = currentMute()
        guard abs(value - volume) > 0.0005 || muted != isMuted else { return }
        volume = value
        isMuted = muted
        HUDService.shared.present(.volume(level: Double(value), muted: muted))
    }

    private func installDeviceListeners() {
        guard deviceID != 0, !listening else { return }
        listening = true
        let context = Unmanaged.passUnretained(self).toOpaque()

        for element in Self.listenedElements {
            var address = Self.scalarAddress(element: element)
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            guard AudioObjectAddPropertyListener(deviceID, &address, Self.listener, context) == noErr
            else { continue }
            listenedAddresses.append(address)
        }

        var mute = Self.muteAddress
        if AudioObjectHasProperty(deviceID, &mute),
           AudioObjectAddPropertyListener(deviceID, &mute, Self.listener, context) == noErr {
            listenedAddresses.append(mute)
        }
    }

    private func removeDeviceListeners() {
        guard listening, deviceID != 0 else { return }
        listening = false
        let context = Unmanaged.passUnretained(self).toOpaque()
        for var address in listenedAddresses {
            AudioObjectRemovePropertyListener(deviceID, &address, Self.listener, context)
        }
        listenedAddresses.removeAll()
    }

    private static let deviceListener: AudioObjectPropertyListenerProc = { _, _, _, context in
        guard let context else { return noErr }
        let service = Unmanaged<AudioService>.fromOpaque(context).takeUnretainedValue()
        DispatchQueue.main.async { MainActor.assumeIsolated { service.defaultDeviceChanged() } }
        return noErr
    }

    fileprivate func defaultDeviceChanged() {
        refreshDevice()
        ActivityCenter.shared.present(
            IslandActivity(kind: .bluetooth,
                           content: .badge(symbol: "hifispeaker.fill", image: nil,
                                           title: outputDeviceName, subtitle: "Output",
                                           tint: Palette.accent),
                           duration: 2.2)
        )
    }

    private func installDefaultDeviceListener() {
        AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject),
                                       &Self.defaultDeviceAddress,
                                       Self.deviceListener,
                                       Unmanaged.passUnretained(self).toOpaque())
    }
}
