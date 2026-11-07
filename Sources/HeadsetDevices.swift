import Foundation

struct ConnectedHeadset: Equatable, Identifiable {
    let productID: Int
    let locationID: Int
    let name: String
    var serialNumber: String? = nil
    var id: String { "\(productID):\(locationID)" }
}

struct HeadsetInputSelection: Equatable {
    static let defaultsKey = "selectedHeadsetInput.v1"
    var deviceID: String?

    func accepts(_ device: ConnectedHeadset) -> Bool { deviceID == nil || deviceID == device.id }
    static func load(from defaults: UserDefaults = .standard) -> Self { Self(deviceID: defaults.string(forKey: defaultsKey)) }
    func save(to defaults: UserDefaults = .standard) {
        if let deviceID { defaults.set(deviceID, forKey: Self.defaultsKey) }
        else { defaults.removeObject(forKey: Self.defaultsKey) }
    }
}

/// Match the USB model and serial exposed by CoreAudio to the selected HID adapter.
/// Unknown identity fails closed instead of borrowing another headset's audio state.
enum HeadsetAudioRoute {
    static func matches(modelUID: String, deviceUID: String, selected: ConnectedHeadset) -> Bool? {
        let modelSuffix = String(format: ":0B0E:%04X", selected.productID)
        guard modelUID.uppercased().hasSuffix(modelSuffix) else { return false }
        guard let serial = selected.serialNumber, !serial.isEmpty else { return nil }
        return deviceUID.range(of: ":" + serial + ":", options: .caseInsensitive) != nil
    }
}
