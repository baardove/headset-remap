import Cocoa
import ApplicationServices

enum CodexVoiceToggle {
    // Labels verified in the installed Codex app's accessible voice controls.
    static func isEndVoiceLabel(_ text: String) -> Bool {
        ["end voice chat", "stop voice chat", "end voice", "avslutt tale", "avslutt talesamtale"].contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
    /// True means an active voice session was detected; do not start another action chain.
    static func stopIfActive(profile: ButtonProfile) -> Bool {
        guard profile.settings.action == .openApp,
              Bundle(path: profile.settings.target)?.bundleIdentifier == "com.openai.codex",
              profile.automaticActions.contains(where: { $0.kind == .keyboard && ($0.presetID == "voice.start" || $0.key == KeyboardShortcut(keyCode: 9, modifiers: 12) || $0.key == KeyboardShortcut(keyCode: 9, modifiers: 5)) }),
              AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first else { return false }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.1)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windows) == .success,
              let list = windows as? [AXUIElement] else { return false }
        var pending = list; let deadline = Date().addingTimeInterval(0.4); var visited = 0
        while let element = pending.popLast(), visited < 4000, Date() < deadline {
            visited += 1
            var role: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            if role as? String == kAXButtonRole {
                for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] {
                    var label: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, attribute as CFString, &label) == .success,
                       let text = label as? String, isEndVoiceLabel(text) {
                        _ = app.activate(options: [])
                        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
                        AppLog.log(result == .success ? "VOICE stopped: active Codex voice session" : "VOICE stop failed: \(result.rawValue); action chain canceled")
                        return true
                    }
                }
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let values = children as? [AXUIElement] { pending.append(contentsOf: values) }
        }
        return false
    }
}
