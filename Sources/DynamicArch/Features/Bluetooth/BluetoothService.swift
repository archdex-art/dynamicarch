import AppKit
import IOBluetooth

/// AirPods and other Bluetooth devices connecting or disconnecting, with
/// battery level when the device publishes one to the IO registry.
@MainActor
final class BluetoothService: NSObject {
    static let shared = BluetoothService()

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    private override init() { super.init() }

    func start() {
        guard Preferences.shared.bluetoothEnabled, connectNotification == nil else { return }
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(deviceConnected(_:device:)))
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        announce(device: device, connected: true)
        let address = device.addressString ?? UUID().uuidString
        disconnectNotifications[address]?.unregister()
        disconnectNotifications[address] = device.register(forDisconnectNotification: self,
                                                           selector: #selector(deviceDisconnected(_:device:)))
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        announce(device: device, connected: false)
        if let address = device.addressString {
            disconnectNotifications[address]?.unregister()
            disconnectNotifications[address] = nil
        }
    }

    private func announce(device: IOBluetoothDevice, connected: Bool) {
        guard Preferences.shared.bluetoothEnabled else { return }
        let name = device.name ?? device.addressString ?? "Device"
        let battery = BluetoothBattery.percentage(forAddress: device.addressString)
        let subtitle: String? = connected
            ? battery.map { "Connected · \($0)%" } ?? "Connected"
            : "Disconnected"

        ActivityCenter.shared.present(
            IslandActivity(kind: .bluetooth,
                           content: .badge(symbol: Self.symbol(for: device),
                                           image: nil,
                                           title: name,
                                           subtitle: subtitle,
                                           tint: connected ? Palette.accent : Palette.secondaryText),
                           duration: 2.6)
        )
    }

    private static func symbol(for device: IOBluetoothDevice) -> String {
        let name = (device.name ?? "").lowercased()
        if name.contains("airpods max") { return "airpods.max" }
        if name.contains("airpods pro") { return "airpods.pro" }
        if name.contains("airpod") { return "airpods" }
        if name.contains("beats") || name.contains("headphone") { return "headphones" }
        if name.contains("keyboard") { return "keyboard" }
        if name.contains("mouse") { return "magicmouse" }
        if name.contains("trackpad") { return "trackpad" }
        if name.contains("watch") { return "applewatch" }
        if name.contains("iphone") { return "iphone" }
        return "dot.radiowaves.left.and.right"
    }
}

/// Battery percentages for Bluetooth accessories are not exposed by a public
/// API; they are published as IO registry properties on the device node.
enum BluetoothBattery {
    static func percentage(forAddress address: String?) -> Int? {
        guard let address else { return nil }
        let normalised = address.replacingOccurrences(of: ":", with: "-").lowercased()

        var iterator = io_iterator_t()
        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dictionary = properties?.takeRetainedValue() as? [String: Any]
            else { continue }

            let deviceAddress = (dictionary["DeviceAddress"] as? String)?
                .replacingOccurrences(of: ":", with: "-").lowercased()
            guard deviceAddress == normalised else { continue }

            for key in ["BatteryPercentCombined", "BatteryPercentSingle", "BatteryPercentCase"] {
                if let value = dictionary[key] as? Int { return value }
            }
        }
        return nil
    }
}
