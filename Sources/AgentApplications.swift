import Cocoa

/// Resolve installed desktop agents, including the Grok Bot app (not the Grok website).
enum AgentApplications {
    static func url(for name: String) -> URL? {
        let identifiers = ["Codex": "com.openai.codex", "Grok": "com.anysphere.sand", "Grok Bot": "com.anysphere.sand", "Claude": "com.anthropic.claudefordesktop", "Hermes": "com.nousresearch.hermes", "Siri": "com.apple.siri.launcher", "ChatGPT": "com.openai.chat"]
        if let id = identifiers[name], let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url }
        if name == "Grok" {
            for path in ["/Applications/Grok Bot.app", NSHomeDirectory() + "/Applications/Grok Bot.app"] {
                if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
            }
        }
        if ["Claude", "Hermes", "OpenClaw"].contains(name) {
            for directory in ["/Applications", NSHomeDirectory() + "/Applications"] {
                let path = directory + "/" + name + ".app"
                if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
            }
        }
        return nil
    }
}
