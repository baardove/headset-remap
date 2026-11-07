import Foundation

enum HeadsetAudioState: String { case active, idle, unknown }

enum ButtonActivationCondition: String, Codable, CaseIterable {
    case always, audioIdle, audioActive
    var title: String {
        switch self {
        case .always: return "Always"
        case .audioIdle: return "Only when headset audio is idle"
        case .audioActive: return "Only while headset audio is active"
        }
    }
    func permits(_ state: HeadsetAudioState) -> Bool {
        switch self { case .always: return true; case .audioIdle: return state == .idle; case .audioActive: return state == .active }
    }
}

/// Require a quiet interval, so a pause-button event cannot immediately look like standby.
struct AudioActivityGate {
    private var quietSince: TimeInterval?
    private(set) var state: HeadsetAudioState = .unknown
    mutating func update(_ sample: HeadsetAudioState, now: TimeInterval) {
        switch sample {
        case .active: quietSince = nil; state = .active
        case .unknown: quietSince = nil; state = .unknown
        case .idle:
            if quietSince == nil { quietSince = now }
            if now - quietSince! >= 2 { state = .idle }
        }
    }
}
