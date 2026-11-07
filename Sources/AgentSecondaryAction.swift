import Foundation

struct AgentActionReference: Equatable {
    let profileID: UUID
    let actionID: UUID
    var encoded: String { "\(profileID.uuidString)/\(actionID.uuidString)" }
    init(profileID: UUID, actionID: UUID) { self.profileID = profileID; self.actionID = actionID }
    init?(_ value: String) {
        let pieces = value.split(separator: "/")
        guard pieces.count == 2, let profile = UUID(uuidString: String(pieces[0])), let action = UUID(uuidString: String(pieces[1])) else { return nil }
        profileID = profile; actionID = action
    }
}

struct AgentSecondaryAction: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case keyboard, url, shortcut
        var title: String {
            switch self { case .keyboard: return "Press a shortcut in the agent"; case .url: return "Open a URL"; case .shortcut: return "Run a macOS Shortcut" }
        }
    }
    var id = UUID()
    var name: String
    var kind: Kind = .keyboard
    var target = ""
    var key: KeyboardShortcut?
    var openAgentFirst = true
    var delay: Double = 0.3
    var presetID: String?
    var sendGlobally: Bool?
    var hotkey: KeyboardShortcut?
    var runAfterHeadset: Bool? = true
    var isConfigured: Bool { validationError == nil }
    var validationError: String? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 60 else { return "Name the action (1–60 characters)." }
        guard delay.isFinite, (0...5).contains(delay) else { return "Use a delay between 0 and 5 seconds." }
        if let hotkey, !hotkey.isValid { return "Choose a valid global shortcut." }
        switch kind {
        case .keyboard:
            guard let key, key.isValid else { return "Record the shortcut used inside this agent." }
        case .url, .shortcut:
            let settings = ButtonSettings(action: kind == .url ? .openURL : .shortcut, target: target)
            if let error = settings.validationError { return error }
        }
        return nil
    }
}
