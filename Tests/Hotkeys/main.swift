import Cocoa
import Carbon

// In-process Carbon dispatch integration. This does not synthesize keyboard input or run any agent.
_ = NSApplication.shared
let runKey = KeyboardShortcut(keyCode: 107, modifiers: 7)
let first = ButtonProfile(name: "Test", settings: ButtonSettings())
let second = ButtonProfile(name: "Other", settings: ButtonSettings())
var library = try ButtonProfileLibrary(profiles: [first, second], activeID: first.id)
try library.updateActiveShortcuts(activate: nil, run: runKey)
let registry = GlobalHotkeys()
var received: [ProfileHotkey] = []
registry.onTrigger = { received.append($0) }
let failures = registry.configure(library)
precondition(failures.isEmpty, "Test hotkey unavailable: \(failures)")
func event(_ kind: UInt32) {
    var event: EventRef?
    precondition(CreateEvent(nil, OSType(kEventClassKeyboard), kind, 0, 0, &event) == noErr)
    var id = EventHotKeyID(signature: 0x4A42524D, id: 1)
    precondition(SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id) == noErr)
    _ = SendEventToEventTarget(event, GetApplicationEventTarget())
    ReleaseEvent(event)
}
event(UInt32(kEventHotKeyPressed))
precondition(received.count == 1 && received[0].profileID == first.id && received[0].purpose == .run)
event(UInt32(kEventHotKeyPressed))
precondition(received.count == 1, "Holding key must not repeat")
try library.select(second.id)
_ = registry.configure(library)
event(UInt32(kEventHotKeyPressed))
precondition(received.count == 1, "Changing active profile must not reset held direct-action key")
event(UInt32(kEventHotKeyReleased)); event(UInt32(kEventHotKeyPressed))
precondition(received.count == 2 && received[1].profileID == first.id, "Direct action must keep targeting its saved profile")
registry.clear()
event(UInt32(kEventHotKeyReleased)); event(UInt32(kEventHotKeyPressed))
precondition(received.count == 2, "Cleared hotkeys must stop dispatching")
print("Passed 5 Carbon registration and dispatch checks")
