import Foundation

enum HeadsetDiagramModel: String, CaseIterable, Codable {
    case evolve230 = "evolve2-30", evolve230SE = "evolve2-30se", evolve240 = "evolve2-40", evolve240SE = "evolve2-40se"
    case evolve250 = "evolve2-50", evolve255 = "evolve2-55", evolve2 = "evolve2", evolve265Flex = "evolve2-65-flex"
    case evolve275 = "evolve2-75", evolve285 = "evolve2-85", evolve2Buds = "evolve2-buds"
    case evolve345 = "evolve3-45", evolve365 = "evolve3-65", evolve365Flex = "evolve3-65-flex", evolve3 = "evolve3", evolve385 = "evolve3-85"
    var assetName: String { self == .evolve2 ? "evolve2-65" : self == .evolve3 ? "evolve3-75" : rawValue }
    var family: String { assetName.hasPrefix("evolve2") ? "Evolve2" : "Evolve3" }
    var variant: String {
        assetName.replacingOccurrences(of: "evolve2-", with: "").replacingOccurrences(of: "evolve3-", with: "")
            .replacingOccurrences(of: "-flex", with: " Flex").replacingOccurrences(of: "se", with: " SE").replacingOccurrences(of: "buds", with: "Buds")
    }
    var title: String { "\(family) \(variant)" }
    static func defaultForAdapter(_ productID: Int) -> Self? {
        switch productID { case 0x24C8: return .evolve2; case 0x2E57: return .evolve3; default: return nil }
    }
    static func defaultForDevice(_ device: ConnectedHeadset) -> Self? {
        let name = device.name.lowercased().filter { $0.isLetter || $0.isNumber }
        if name.contains("link390") { return .evolve3 }
        if name.contains("link380") { return .evolve2 }
        return defaultForAdapter(device.productID)
    }
    var hasBoom: Bool { ![Self.evolve2Buds, .evolve365Flex, .evolve3, .evolve385].contains(self) }
    static func detect(name: String) -> Self? {
        let normalized = name.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !normalized.contains("jabralink") else { return nil }
        return allCases.sorted { $0.title.count > $1.title.count }.first {
            let needle = $0.title.lowercased().filter { $0.isLetter || $0.isNumber }
            guard let range = normalized.range(of: needle) else { return false }
            return range.upperBound == normalized.endIndex || !normalized[range.upperBound].isNumber
        }
    }
}

/// An explicit choice is tied to one device, not guessed from its Link adapter model.
struct HeadsetModelAssignments: Codable, Equatable {
    static let defaultsKey = "headsetModelAssignments.v1"
    private var models: [String: HeadsetDiagramModel] = [:]
    func assignedModel(for deviceID: String) -> HeadsetDiagramModel? { models[deviceID] }
    func model(for device: ConnectedHeadset) -> HeadsetDiagramModel? {
        HeadsetDiagramModel.detect(name: device.name) ?? models[device.id] ?? HeadsetDiagramModel.defaultForDevice(device)
    }
    mutating func set(_ model: HeadsetDiagramModel, for deviceID: String) { models[deviceID] = model }
    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: defaultsKey), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    func save(to defaults: UserDefaults = .standard) throws { defaults.set(try JSONEncoder().encode(self), forKey: Self.defaultsKey) }
}

struct ButtonAvailability: Codable, Equatable {
    static let defaultsKey = "buttonAvailabilityByHeadset.v1"
    private var hiddenByModel: [String: [String]] = [:]
    func hiddenIDs(for model: HeadsetDiagramModel) -> Set<String> { Set(hiddenByModel[model.rawValue] ?? []) }
    func isAvailable(_ id: String, model: HeadsetDiagramModel?) -> Bool {
        guard let model else { return true }
        return !hiddenIDs(for: model).contains(id)
    }
    mutating func setAvailable(_ available: Bool, id: String, model: HeadsetDiagramModel) {
        var ids = hiddenIDs(for: model)
        if available { ids.remove(id) } else { ids.insert(id) }
        hiddenByModel[model.rawValue] = ids.sorted()
    }
    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: defaultsKey), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    func save(to defaults: UserDefaults = .standard) throws { defaults.set(try JSONEncoder().encode(self), forKey: Self.defaultsKey) }
}
