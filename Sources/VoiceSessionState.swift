import Foundation

enum VoiceSessionState: String {
    case active, inactive, unknown

    func status(for agent: String) -> String {
        switch self {
        case .active: return "\(agent) voice active"
        case .inactive: return "\(agent) voice inactive"
        case .unknown: return "\(agent) voice state unavailable"
        }
    }

    var status: String { status(for: "Codex") }
}

// Preserve the existing Codex API while sharing the same states with other agents.
typealias CodexVoiceState = VoiceSessionState
