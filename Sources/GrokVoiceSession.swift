import Cocoa
import ApplicationServices

enum GrokVoiceSession {
    static let bundleID = "com.anysphere.sand"
    // Accessed only by the main-thread action dispatcher, never by the polling probe.
    private static var stopping: Set<pid_t> = []

    static func classify(foundHangup: Bool, foundComposer: Bool, complete: Bool) -> VoiceSessionState {
        if foundHangup { return .active }
        return complete && foundComposer ? .inactive : .unknown
    }

    static func supportsToggle(_ profile: ButtonProfile) -> Bool {
        profile.settings.action == .openApp && supportsToggle(bundleIdentifier: Bundle(path: profile.settings.target)?.bundleIdentifier, actions: profile.automaticActions)
    }

    static func supportsToggle(bundleIdentifier: String?, actions: [AgentSecondaryAction]) -> Bool {
        bundleIdentifier == bundleID && actions.contains {
            $0.kind == .uiButton && AgentUIButtonMatch.needsGrokVoiceClick(label: $0.target, bundleID: bundleID)
        }
    }

    /// Inspect all app windows, including when Grok is behind another application.
    /// Absence of Hang up is only conclusive if a complete composer was inspected.
    static func probe(processID: pid_t) -> VoiceSessionState {
        guard AXIsProcessTrusted() else { return .unknown }
        let root = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(root, 0.03)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windows) == .success,
              let list = windows as? [AXUIElement], !list.isEmpty else { return .unknown }
        var pending = list
        var cursor = 0
        var complete = true
        var foundComposer = false
        let deadline = ProcessInfo.processInfo.systemUptime + 0.5
        while cursor < pending.count, cursor < 6000, ProcessInfo.processInfo.systemUptime < deadline {
            let element = pending[cursor]; cursor += 1
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) != .success { complete = false }
            if role as? String == kAXButtonRole {
                for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] {
                    var value: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                       let label = value as? String {
                        let label = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        if label == "hang up" { return .active }
                        if ["start voice chat", "start voice input", "send message"].contains(label) { foundComposer = true }
                    }
                }
            }
            var children: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
            if result == .success, let children = children as? [AXUIElement] {
                let capacity = max(0, 6000 - pending.count)
                pending.append(contentsOf: children.prefix(capacity))
                if children.count > capacity { complete = false }
            } else if result != .success && result != .noValue && result != .attributeUnsupported {
                complete = false
            }
        }
        return classify(foundHangup: false, foundComposer: foundComposer, complete: complete && cursor == pending.count)
    }

    /// True consumes a Run/headset press to stop an active session, skipping the
    /// primary action and every later action. An unknown state never means active.
    static func stopIfActive(profile: ButtonProfile, isCurrent: @escaping () -> Bool,
                             completion: @escaping (String?) -> Void) -> Bool {
        guard supportsToggle(profile),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return false }
        guard !stopping.contains(app.processIdentifier) else { return true }
        guard probe(processID: app.processIdentifier) == .active else { return false }
        guard isCurrent() else { completion("Voice stop canceled because the configuration changed."); return true }
        let pid = app.processIdentifier
        stopping.insert(pid)
        _ = app.activate(options: [])
        let root = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        if AXUIElementCopyAttributeValue(root, kAXFocusedWindowAttribute as CFString, &window) == .success,
           let window, CFGetTypeID(window) == AXUIElementGetTypeID() {
            _ = AXUIElementPerformAction(unsafeBitCast(window, to: AXUIElement.self), kAXRaiseAction as CFString)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            AgentUIButton.stopGrokVoice(isCurrent: isCurrent) { error in
                stopping.remove(pid)
                completion(error)
            }
        }
        return true
    }
}
