import Foundation

struct ConnectedHeadset: Equatable, Identifiable {
    let productID: Int
    let locationID: Int
    let name: String
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
