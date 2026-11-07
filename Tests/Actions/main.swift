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
for kind in [AgentSecondaryAction.Kind.keyboard, .shortcut] {
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
print("Passed 6 delayed-action cancellation checks; no real apps or shortcuts invoked")
