import Foundation

enum AgentActionPresets {
    static let codex: [(id: String, name: String, key: UInt32, modifiers: UInt32)] = [
        ("dot.open", "Open your dot", 47, 1),
        ("chat.new", "New chat", 45, 1),
        ("chat.temporary", "New temporary chat", 45, 9),
        ("chat.standalone", "New standalone chat", 31, 3),
        ("chat.side", "Open side chat", 1, 3),
        ("voice.start", "Voice Chat", 9, 5),
        ("voice.end", "End Voice Chat", 9, 9),
        ("voice.microphone", "Toggle Voice Chat microphone", 9, 6),
        ("voice.audio", "Toggle Voice Chat audio", 9, 10)
    ]
}
