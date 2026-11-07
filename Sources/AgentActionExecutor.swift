import Cocoa
import ApplicationServices

/// Runs a user-configured secondary action. No text or key event is sent until explicitly invoked.
enum AgentActionExecutor {
    static func run(_ action: AgentSecondaryAction, profile: ButtonProfile, completion: @escaping (String?) -> Void) {
        if let error = action.validationError { completion(error); return }
        let perform = {
            DispatchQueue.main.asyncAfter(deadline: .now() + action.delay) {
                switch action.kind {
                case .url:
                    ButtonActionExecutor.run(ButtonSettings(action: .openURL, target: action.target), completion: completion)
                case .shortcut:
                    ButtonActionExecutor.run(ButtonSettings(action: .shortcut, target: action.target), completion: completion)
                case .keyboard:
                    guard profile.settings.action == .openApp,
                          let bundleID = Bundle(path: profile.settings.target)?.bundleIdentifier else {
                        completion("Keyboard actions need a desktop app as the agent’s Open action."); return
                    }
                    guard AXIsProcessTrusted() else {
                        completion("Allow Headset Remap in System Settings → Privacy & Security → Accessibility to send app shortcuts."); return
                    }
                    guard let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == bundleID, let key = action.key else {
                        completion("The agent is not in front. Keyboard action canceled."); return
                    }
                    let source = CGEventSource(stateID: .combinedSessionState)
                    guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key.keyCode), keyDown: true),
                          let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key.keyCode), keyDown: false) else {
                        completion("Could not create the keyboard event."); return
                    }
                    var flags: CGEventFlags = []
                    if key.modifiers & KeyboardShortcut.command != 0 { flags.insert(.maskCommand) }
                    if key.modifiers & KeyboardShortcut.option != 0 { flags.insert(.maskAlternate) }
                    if key.modifiers & KeyboardShortcut.control != 0 { flags.insert(.maskControl) }
                    if key.modifiers & KeyboardShortcut.shift != 0 { flags.insert(.maskShift) }
                    down.flags = flags; up.flags = flags
                    if action.sendGlobally == true {
                        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
                    } else { down.postToPid(front.processIdentifier); up.postToPid(front.processIdentifier) }
                    completion(nil)
                }
            }
        }
        if action.openAgentFirst {
            ButtonActionExecutor.run(profile.settings) { error in
                if let error { completion(error) } else { perform() }
            }
        } else { perform() }
    }
}
