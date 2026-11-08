import Cocoa
import ApplicationServices

/// Exact matching prevents a voice-input button or transcript text from substituting for voice chat.
enum AgentUIButtonMatch {
    static func needsGrokVoiceClick(label: String, bundleID: String) -> Bool {
        bundleID == "com.anysphere.sand" && label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "start voice chat"
    }

    static func clickPoint(position: CGPoint, size: CGSize) -> CGPoint? {
        guard position.x.isFinite, position.y.isFinite, size.width.isFinite, size.height.isFinite,
              size.width >= 2, size.height >= 2 else { return nil }
        let point = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        return point.x.isFinite && point.y.isFinite ? point : nil
    }

    static func matches(label: String, role: String, enabled: Bool, labels: [String]) -> Bool {
        let wanted = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !wanted.isEmpty && role == kAXButtonRole && enabled && labels.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == wanted
        }
    }

    static func error(count: Int, complete: Bool, label: String) -> String? {
        guard complete else { return "Could not fully inspect the agent window. No button was pressed." }
        guard count > 0 else { return "No enabled button named ‘\(label)’ is visible in the agent’s focused window." }
        guard count == 1 else { return "More than one button is named ‘\(label)’. No button was pressed." }
        return nil
    }
}

enum AgentUIButton {
    private static let coveredButtonError = "The voice button is covered or no longer at its detected position. No click was sent."
    private static var grokStopInFlight = false
    struct SearchResult {
        var control: AXUIElement?
        var error: String?
    }

    /// Read-only lookup, also used for diagnostics. No coordinates, keypresses or app activation.
    static func find(label: String, processID: pid_t) -> SearchResult {
        guard AXIsProcessTrusted() else {
            return SearchResult(error: "Allow Headset Remap in System Settings → Privacy & Security → Accessibility to press app buttons.")
        }
        let root = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(root, 0.04)
        var window: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(root, kAXFocusedWindowAttribute as CFString, &window)
        if result != .success {
            result = AXUIElementCopyAttributeValue(root, kAXMainWindowAttribute as CFString, &window)
        }
        guard result == .success, let window, CFGetTypeID(window) == AXUIElementGetTypeID() else {
            return SearchResult(error: "The agent has no accessible focused window.")
        }
        var pending = [unsafeBitCast(window, to: AXUIElement.self)]
        var visited: [AXUIElement] = []
        var matches: [AXUIElement] = []
        var cursor = 0
        var complete = true
        let deadline = ProcessInfo.processInfo.systemUptime + 0.8
        while cursor < pending.count, cursor < 6000, ProcessInfo.processInfo.systemUptime < deadline {
            let element = pending[cursor]; cursor += 1
            // Accessibility hierarchies may contain references back to an existing node.
            if visited.contains(where: { CFEqual($0, element) }) { continue }
            visited.append(element)
            var role: CFTypeRef?
            let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            if roleResult != .success { complete = false }
            if role as? String == kAXButtonRole {
                var enabled: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabled)
                var labels: [String] = []
                for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] {
                    var value: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                       let text = value as? String { labels.append(text) }
                }
                if AgentUIButtonMatch.matches(label: label, role: kAXButtonRole, enabled: (enabled as? Bool) == true, labels: labels) {
                    matches.append(element)
                }
            }
            var children: CFTypeRef?
            let childResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
            if childResult == .success, let children = children as? [AXUIElement] {
                let remaining = max(0, 6000 - pending.count)
                pending.append(contentsOf: children.prefix(remaining))
                if children.count > remaining { complete = false }
            } else if childResult != .success && childResult != .noValue && childResult != .attributeUnsupported {
                complete = false
            }
        }
        complete = complete && cursor == pending.count
        if let error = AgentUIButtonMatch.error(count: matches.count, complete: complete, label: label) {
            return SearchResult(error: error)
        }
        return SearchResult(control: matches[0])
    }

    /// Grok's Electron voice control accepts AXPress without opening a call. Use an actual
    /// pointer click for that exact integration, and do not report success until voice opens.
    static func run(label: String, bundleID: String, isCurrent: @escaping () -> Bool, completion: @escaping (String?) -> Void) {
        let grokVoice = AgentUIButtonMatch.needsGrokVoiceClick(label: label, bundleID: bundleID)
        if grokVoice, isCurrent(), let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == bundleID,
           find(label: "Hang up", processID: app.processIdentifier).control != nil {
            stopGrokVoice(isCurrent: isCurrent, completion: completion)
            return
        }
        if let error = press(label: label, bundleID: bundleID, pointerClick: grokVoice, isCurrent: isCurrent) {
            completion(error); return
        }
        guard grokVoice else { completion(nil); return }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        func confirm() {
            guard isCurrent() else { completion("Configuration changed after the voice click; confirmation canceled."); return }
            guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == bundleID else {
                completion("Grok lost focus after the voice click; voice startup could not be confirmed."); return
            }
            if find(label: "Hang up", processID: app.processIdentifier).control != nil {
                completion(nil)
            } else if ProcessInfo.processInfo.systemUptime >= deadline {
                completion("Grok accepted the click but did not expose an active voice chat. Check Grok for a microphone prompt or error.")
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: confirm)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: confirm)
    }

    static func stopGrokVoice(isCurrent: @escaping () -> Bool, completion: @escaping (String?) -> Void) {
        guard !grokStopInFlight else { completion("Grok voice stop is already in progress."); return }
        guard isCurrent(), let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == GrokVoiceSession.bundleID else {
            completion("Grok is not in front, or the voice stop was canceled."); return
        }
        let state = GrokVoiceSession.probe(processID: app.processIdentifier)
        if state == .inactive { completion(nil); return }
        guard state == .active else { completion("Grok voice state is unavailable; no stop button was pressed."); return }
        grokStopInFlight = true
        func finish(_ error: String?) {
            grokStopInFlight = false
            completion(error)
        }
        func confirm(until deadline: TimeInterval) {
            guard isCurrent(), NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                finish("Grok lost focus or the configuration changed; voice stop could not be confirmed."); return
            }
            if GrokVoiceSession.probe(processID: app.processIdentifier) == .inactive {
                finish(nil)
            } else if ProcessInfo.processInfo.systemUptime >= deadline {
                finish("Grok voice stop could not be confirmed. Check the call panel.")
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { confirm(until: deadline) }
            }
        }
        let readyDeadline = ProcessInfo.processInfo.systemUptime + 2
        func clickWhenReady() {
            guard isCurrent(), NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                finish("Grok lost focus or the voice stop was canceled before clicking."); return
            }
            if let error = press(label: "Hang up", bundleID: GrokVoiceSession.bundleID, pointerClick: true, isCurrent: isCurrent) {
                // Retry only a pre-click visibility failure. Once a click is posted,
                // never click again: the same location could become Start voice.
                if error == coveredButtonError, ProcessInfo.processInfo.systemUptime < readyDeadline {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: clickWhenReady)
                } else { finish(error) }
                return
            }
            let confirmationDeadline = ProcessInfo.processInfo.systemUptime + 3
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { confirm(until: confirmationDeadline) }
        }
        clickWhenReady()
    }

    static func press(label: String, bundleID: String, pointerClick: Bool = false, isCurrent: () -> Bool) -> String? {
        guard isCurrent() else { return "Action canceled because the configuration changed." }
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == bundleID else {
            return "The agent is not in front. Button action canceled."
        }
        let found = find(label: label, processID: app.processIdentifier)
        guard let button = found.control else { return found.error }
        guard isCurrent(), NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            return "The agent lost focus or the configuration changed. No button was pressed."
        }
        var enabled: CFTypeRef?
        guard AXUIElementCopyAttributeValue(button, kAXEnabledAttribute as CFString, &enabled) == .success,
              (enabled as? Bool) == true else { return "The button is no longer enabled. No button was pressed." }
        var currentLabels: [String] = []
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(button, attribute as CFString, &value) == .success,
               let value = value as? String { currentLabels.append(value) }
        }
        guard AgentUIButtonMatch.matches(label: label, role: kAXButtonRole, enabled: true, labels: currentLabels) else {
            return "The button changed while being inspected. No button was pressed."
        }
        if pointerClick {
            return clickLocatedButton(button, processID: app.processIdentifier, isCurrent: isCurrent)
        }
        var actions: CFArray?
        guard AXUIElementCopyActionNames(button, &actions) == .success,
              (actions as? [String])?.contains(kAXPressAction) == true else {
            return "The button does not expose an Accessibility press action."
        }
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        return result == .success ? nil : "The agent’s button press failed (Accessibility error \(result.rawValue))."
    }

    private static func clickLocatedButton(_ button: AXUIElement, processID: pid_t, isCurrent: () -> Bool) -> String? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(button, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(button, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return "The voice button has no accessible screen position. No click was sent."
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size),
              let point = AgentUIButtonMatch.clickPoint(position: position, size: size) else {
            return "The voice button has invalid bounds. No click was sent."
        }
        // A window, sheet or tooltip may cover the control. Check the actual hit target
        // (or one of its ancestors) before sending a pointer event to the screen.
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success else {
            return "Could not verify the voice button at its screen position. No click was sent."
        }
        var matches = false
        for _ in 0..<12 {
            guard let element = hit else { break }
            if CFEqual(element, button) { matches = true; break }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            hit = unsafeBitCast(parent, to: AXUIElement.self)
        }
        guard matches else { return coveredButtonError }
        guard isCurrent(), NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else {
            return "Grok lost focus or the configuration changed. No click was sent."
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            return "Could not create the voice-button mouse events."
        }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return nil
    }
}
