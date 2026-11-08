import Cocoa

// Fake only the external launch boundary. The real delayed executor runs below.
enum ButtonActionExecutor {
    static var calls = 0
    static var openDelay: Double = 0
    static func run(_ settings: ButtonSettings, completion: @escaping (String?) -> Void) {
        calls += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + openDelay) { completion(nil) }
    }
}
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
let profile = ButtonProfile(name: "Test", settings: ButtonSettings(action: .openApp, target: "/Applications/Test.app"))
var action = AgentSecondaryAction(name: "Test URL", kind: .url, target: "https://example.com")
action.openAgentFirst = false
action.delay = 0.03
var completed = false
var result: String?
let generation = ActionGeneration()
AgentActionExecutor.run(action, profile: profile, isCurrent: generation.checkpoint()) { result = $0; completed = true }
generation.cancel()
RunLoop.main.run(until: Date().addingTimeInterval(0.12))
check(completed && result != nil && ButtonActionExecutor.calls == 0, "Canceled delayed action must not cross launch boundary")
completed = false
AgentActionExecutor.run(action, profile: profile, isCurrent: generation.checkpoint()) { result = $0; completed = true }
RunLoop.main.run(until: Date().addingTimeInterval(0.12))
check(completed && result == nil && ButtonActionExecutor.calls == 1, "Valid action should launch exactly once")
ButtonActionExecutor.calls = 0
ButtonActionExecutor.openDelay = 0.04
action.openAgentFirst = true
completed = false
AgentActionExecutor.run(action, profile: profile, isCurrent: generation.checkpoint()) { result = $0; completed = true }
generation.cancel()
RunLoop.main.run(until: Date().addingTimeInterval(0.15))
check(completed && result != nil && ButtonActionExecutor.calls == 1, "Cancel during app open prevents follow-up")
completed = false
AgentActionExecutor.run(action, profile: profile, isCurrent: { false }) { result = $0; completed = true }
check(completed && result != nil && ButtonActionExecutor.calls == 1, "Already canceled work must not open app")
for kind in [AgentSecondaryAction.Kind.keyboard, .shortcut, .uiButton] {
    action.kind = kind
    action.openAgentFirst = false
    action.key = KeyboardShortcut(keyCode: 45, modifiers: KeyboardShortcut.command)
    let fresh = ActionGeneration()
    completed = false
    AgentActionExecutor.run(action, profile: profile, isCurrent: fresh.checkpoint()) { result = $0; completed = true }
    fresh.cancel()
    RunLoop.main.run(until: Date().addingTimeInterval(0.12))
    check(completed && result?.contains("canceled") == true && ButtonActionExecutor.calls == 1, "Canceled keyboard/Shortcut actions must not dispatch")
}
let grok = AgentActionPresets.grokVoice()
check(grok.kind == .uiButton && grok.target == "Start voice chat" && grok.isConfigured && grok.key == nil, "Grok preset must target the exact voice-chat button without a keypress")
let roundTripped = try JSONDecoder().decode(AgentSecondaryAction.self, from: JSONEncoder().encode(grok))
check(roundTripped == grok, "Button actions must survive persistence")
var blank = grok; blank.target = "  "
check(!blank.isConfigured, "Empty button labels must be rejected")
check(AgentUIButtonMatch.matches(label: "Start voice chat", role: "AXButton", enabled: true, labels: [" Start voice chat "]), "Exact label should match")
check(!AgentUIButtonMatch.matches(label: "Start voice chat", role: "AXButton", enabled: true, labels: ["Start voice input"]), "Dictation must not substitute for voice chat")
check(!AgentUIButtonMatch.matches(label: "Start voice chat", role: "AXStaticText", enabled: true, labels: ["Start voice chat"]), "Transcript text must not match")
check(!AgentUIButtonMatch.matches(label: "Start voice chat", role: "AXButton", enabled: false, labels: ["Start voice chat"]), "Disabled buttons must not match")
check(!AgentUIButtonMatch.matches(label: "Start voice chat", role: "AXButton", enabled: true, labels: ["Start voice chat replay"]), "Partial button labels must not match")
check(AgentUIButtonMatch.error(count: 1, complete: true, label: "Voice") == nil, "One exact button should be accepted")
check(AgentUIButtonMatch.error(count: 2, complete: true, label: "Voice") != nil, "Ambiguous targets must not be pressed")
check(AgentUIButtonMatch.error(count: 1, complete: false, label: "Voice") != nil, "Incomplete inspection must not press even a found button")
check(AgentUIButtonMatch.error(count: 0, complete: true, label: "Voice") != nil, "Missing target must be an error")
check(AgentUIButtonMatch.needsGrokVoiceClick(label: " Start voice chat ", bundleID: "com.anysphere.sand"), "Grok voice requires a pointer click")
check(!AgentUIButtonMatch.needsGrokVoiceClick(label: "Start voice input", bundleID: "com.anysphere.sand"), "Other Grok controls must not use the special voice integration")
check(!AgentUIButtonMatch.needsGrokVoiceClick(label: "Start voice chat", bundleID: "com.openai.codex"), "Other apps must preserve AXPress behavior")
check(AgentUIButtonMatch.clickPoint(position: CGPoint(x: -100, y: 200), size: CGSize(width: 40, height: 30)) == CGPoint(x: -80, y: 215), "Button coordinates must come from current bounds, including a secondary display")
check(AgentUIButtonMatch.clickPoint(position: .zero, size: .zero) == nil, "Zero-size controls must not be clicked")
check(AgentUIButtonMatch.clickPoint(position: CGPoint(x: CGFloat.infinity, y: 0), size: CGSize(width: 40, height: 40)) == nil, "Invalid coordinates must not be clicked")
print("Passed 7 delayed-action cancellation checks and 18 UI-button/persistence checks; no real apps, buttons or shortcuts invoked")

let sequenceActions = [AgentSecondaryAction(name: "one", kind: .url, target: "https://example.com/1"),
                       AgentSecondaryAction(name: "two", kind: .url, target: "https://example.com/2")]
var sequenceTrace: [String] = []
var sequenceError: String?
AutomaticAgentActions.run(afterPrimary: { next in sequenceTrace.append("primary"); next(nil) }, actions: sequenceActions,
    isCurrent: { true }, perform: { action, next in
        check(!action.openAgentFirst, "The primary must not be reopened for every follow-up")
        sequenceTrace.append(action.name); next(nil)
    }, completion: { sequenceError = $0; sequenceTrace.append("done") })
check(sequenceError == nil && sequenceTrace == ["primary", "one", "two", "done"], "Play must run primary then secondary actions in order")
sequenceTrace = []
AutomaticAgentActions.run(afterPrimary: { next in sequenceTrace.append("primary"); next("open failed") }, actions: sequenceActions,
    isCurrent: { true }, perform: { action, next in sequenceTrace.append(action.name); next(nil) }, completion: { sequenceError = $0 })
check(sequenceTrace == ["primary"] && sequenceError == "open failed", "Primary failure must prevent all follow-ups")
sequenceTrace = []
AutomaticAgentActions.run(afterPrimary: { $0(nil) }, actions: sequenceActions,
    isCurrent: { true }, perform: { action, next in sequenceTrace.append(action.name); next("secondary failed") }, completion: { sequenceError = $0 })
check(sequenceTrace == ["one"] && sequenceError == "secondary failed", "Secondary failure must stop remaining actions")
sequenceTrace = []
AutomaticAgentActions.run(afterPrimary: { next in sequenceTrace.append("primary"); next(nil) }, actions: sequenceActions,
    isCurrent: { false }, perform: { action, next in sequenceTrace.append(action.name); next(nil) }, completion: { sequenceError = $0 })
check(sequenceTrace.isEmpty && sequenceError != nil, "An already canceled Play must do nothing")
var openFinished: ((String?) -> Void)?
var sequenceCurrent = true
AutomaticAgentActions.run(afterPrimary: { openFinished = $0 }, actions: sequenceActions,
    isCurrent: { sequenceCurrent }, perform: { action, next in sequenceTrace.append(action.name); next(nil) }, completion: { sequenceError = $0 })
sequenceCurrent = false
openFinished?(nil)
check(sequenceTrace.isEmpty && sequenceError != nil, "Changing configuration during open must cancel follow-ups")
sequenceCurrent = true
sequenceTrace = []
AutomaticAgentActions.run(afterPrimary: { $0(nil) }, actions: sequenceActions,
    isCurrent: { sequenceCurrent }, perform: { action, next in
        sequenceTrace.append(action.name); sequenceCurrent = false; next(nil)
    }, completion: { sequenceError = $0 })
check(sequenceTrace == ["one"] && sequenceError != nil, "Changing configuration between follow-ups must stop the sequence")
print("Passed 6 Run-sequence ordering, failure and cancellation checks")

check(GrokVoiceSession.classify(foundHangup: true, foundComposer: false, complete: false) == .active, "An observed call control proves active voice")
check(GrokVoiceSession.classify(foundHangup: false, foundComposer: true, complete: true) == .inactive, "A complete composer without a call control is inactive")
check(GrokVoiceSession.classify(foundHangup: false, foundComposer: true, complete: false) == .unknown, "An incomplete tree must not imply inactive voice")
check(GrokVoiceSession.classify(foundHangup: false, foundComposer: false, complete: true) == .unknown, "Settings/unknown windows must not imply a voice state")
check(GrokVoiceSession.classify(foundHangup: true, foundComposer: true, complete: true) == .active, "Call control takes precedence over composer")
check(GrokVoiceSession.supportsToggle(bundleIdentifier: GrokVoiceSession.bundleID, actions: [grok]), "Configured Grok voice must support toggle")
check(!GrokVoiceSession.supportsToggle(bundleIdentifier: "com.openai.codex", actions: [grok]), "Grok toggle must not affect another app")
check(!GrokVoiceSession.supportsToggle(bundleIdentifier: GrokVoiceSession.bundleID, actions: []), "Grok with no selected voice action must not hang up")
var dictation = grok; dictation.target = "Start voice input"
check(!GrokVoiceSession.supportsToggle(bundleIdentifier: GrokVoiceSession.bundleID, actions: [dictation]), "Dictation is not a voice-chat toggle")
check(VoiceSessionState.active.status(for: "Grok Bot") == "Grok Bot voice active", "Tray status must identify Grok")
print("Passed 10 Grok voice-state and toggle-scope checks")
