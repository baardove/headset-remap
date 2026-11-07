import Foundation

var count = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    count += 1
    if !condition() { fatalError(message) }
}
func signal(_ value: Int, product: Int = 1234, page: UInt32 = 0xFF00, cookie: UInt32 = 12) -> ButtonSignal {
    ButtonSignal(productID: product, usagePage: page, usage: 1, reportID: 3, cookie: cookie, value: value)
}
let press = signal(1)
let release = signal(0)
var trigger = ButtonTrigger()
check(!trigger.consume(release, device: "A", binding: press, now: 0), "Release must not launch")
check(trigger.consume(press, device: "A", binding: press, now: 1), "Press must launch")
check(!trigger.consume(press, device: "A", binding: press, now: 2), "Held/repeated value must not relaunch")
check(!trigger.consume(press, device: "B", binding: press, now: 1.1), "Duplicate interface must be debounced")
check(!trigger.consume(release, device: "A", binding: press, now: 2.1), "Release must only rearm")
check(trigger.consume(press, device: "A", binding: press, now: 2.5), "Second distinct press must launch")
check(!trigger.consume(signal(1, product: 999), device: "A", binding: press, now: 3), "Other model must not launch")
check(!trigger.consume(signal(1, page: 12), device: "A", binding: press, now: 3), "Other usage page must not launch")
check(!trigger.consume(signal(1, cookie: 13), device: "A", binding: press, now: 3), "Other element must not launch")
trigger.reset()
check(trigger.consume(press, device: "A", binding: press, now: 4), "Reset must clear held state")
trigger.reset()
check(!trigger.consume(press, device: "A", binding: release, now: 5), "Active-low source high value must not launch")
check(trigger.consume(release, device: "A", binding: release, now: 6), "Active-low button must work")
check(!trigger.consume(release, device: "A", binding: release, now: 7), "Active-low hold must not repeat")
check(!trigger.consume(press, device: "A", binding: nil, now: 8), "Unlearned input must do nothing")

let defaults = UserDefaults(suiteName: "JabraTeamsRemap.Tests.\(UUID().uuidString)")!
defer { defaults.removeObject(forKey: ButtonSettings.defaultsKey) }
check(!ButtonSettings.load(from: defaults).legacyControls, "Fresh settings must not force a call")
var settings = ButtonSettings(signal: press, action: .shortcut, target: "Agent's \"voice\" $(literal)")
try settings.save(to: defaults)
let loaded = ButtonSettings.load(from: defaults)
check(loaded.signal == press && loaded.target == settings.target, "Settings must round-trip including literal arguments")
check(loaded.validationError == nil, "Literal shortcut names must be valid without shell interpretation")
settings.action = .openURL
for url in ["https://grok.com/", "myagent://start"] {
    settings.target = url
    check(settings.validationError == nil, "Valid URL rejected: \(url)")
}
for url in ["", "grok.com", "https://", "javascript:alert(1)", "file:///tmp/run", "data:text/plain,test"] {
    settings.target = url
    check(settings.validationError != nil, "Invalid URL accepted: \(url)")
}
settings.action = .openApp
settings.target = "/Applications/Example Agent.app"
check(settings.validationError == nil, "App path with spaces must work")
settings.target = "Example Agent"
check(settings.validationError != nil, "App action requires an absolute bundle path")
settings.action = .none
settings.target = ""
check(settings.validationError == nil, "Disabled action needs no target")
defaults.set(Data("not json".utf8), forKey: ButtonSettings.defaultsKey)
check(ButtonSettings.load(from: defaults).signal == nil, "Corrupt preferences must fall back safely")
// Regression: displaying input must never implicitly disable actions.
var mode = InputMonitorMode(tracingEnabled: true)
check(mode.dispatchesActions(isLearning: false), "Enabling trace must not pause actions")
mode.tracingEnabled = false
check(mode.dispatchesActions(isLearning: false), "Pausing trace must not pause actions")
mode.actionsEnabled = false
mode.tracingEnabled = true
check(!mode.dispatchesActions(isLearning: false), "Explicit action pause must work while tracing")
mode.tracingEnabled = false
check(!mode.dispatchesActions(isLearning: false), "Trace toggle must preserve explicit action pause")
mode.actionsEnabled = true
check(!mode.dispatchesActions(isLearning: true), "Learning must never launch an agent")

// Replay the actual short 0x9B pulse: track its release even while paused.
let teamsPress = ButtonSignal(productID: 0x2e57, usagePage: 0xff99, usage: 4, reportID: 155, cookie: 76, value: 1)
let teamsRelease = ButtonSignal(productID: 0x2e57, usagePage: 0xff99, usage: 4, reportID: 155, cookie: 76, value: 0)
var replay = ButtonTrigger()
mode.actionsEnabled = false
let pausedPress = replay.consume(teamsPress, device: "390", binding: teamsPress, now: 1)
check(pausedPress && !mode.dispatchesActions(isLearning: false), "Pause must suppress dispatch without dropping edge tracking")
mode.actionsEnabled = true
check(!replay.consume(teamsPress, device: "390", binding: teamsPress, now: 2), "Resume must not fire a held button")
_ = replay.consume(teamsRelease, device: "390", binding: teamsPress, now: 2.001)
check(replay.consume(teamsPress, device: "390", binding: teamsPress, now: 3), "Next physical press must launch after resume")
_ = replay.consume(teamsRelease, device: "390", binding: teamsPress, now: 3.001)
mode.tracingEnabled = true
check(replay.consume(teamsPress, device: "390", binding: teamsPress, now: 4) && mode.dispatchesActions(isLearning: false), "Real Teams pulse must route while debug logging is active")
// Existing saved mappings retain their signal and gain a Teams-specific delay.
let oldJSON = Data("{\"signal\":{\"productID\":11863,\"usagePage\":65433,\"usage\":4,\"reportID\":155,\"cookie\":76,\"value\":1},\"action\":\"openApp\",\"target\":\"/Applications/ChatGPT.app\",\"legacyControls\":false}".utf8)
var migrated = try JSONDecoder().decode(ButtonSettings.self, from: oldJSON)
check(migrated.signal == teamsPress, "Migration must preserve the learned Teams button")
check(migrated.effectiveFocusTiming == .afterTeams, "Old Teams mappings need the default foreground delay")
check(migrated.effectiveFocusTiming.delay == 0.5, "Default Teams delay must be half a second")
migrated.focusTiming = .oneSecond
let roundTrip = try JSONDecoder().decode(ButtonSettings.self, from: JSONEncoder().encode(migrated))
check(roundTrip.effectiveFocusTiming.delay == 1, "Custom focus timing must persist")
migrated.focusTiming = .immediate
check(migrated.effectiveFocusTiming.delay == 0, "Explicit immediate setting must override Teams default")
migrated.focusTiming = nil
migrated.signal = press
check(migrated.effectiveFocusTiming == .immediate, "Non-Teams buttons should remain immediate")
// Protocol framing and replies captured from the actual Link 390.
let idleReport = TeamsProtocol.report(.idle, payload: [0])!
check(idleReport.count == 64, "Feature reports must match the 64-byte descriptor")
check(Array(idleReport.prefix(5)) == [0x9a, 0x30, 0, 1, 0], "Idle handshake framing must match the accepted device packet")
check(TeamsProtocol.report(.idle, payload: Array(repeating: 0, count: 61)) == nil, "Oversized feature payload must be rejected")
check(TeamsProtocol.accepts([0x9a, 0, 0, 1, 1], for: .version), "Captured version reply must pass")
check(TeamsProtocol.accepts([0x9a, 0x10, 0, 1, 0x27], for: .capabilities), "Captured capabilities reply must pass")
check(TeamsProtocol.accepts([0x9a, 0x20, 0, 1, 1], for: .locale), "Captured locale acknowledgement must pass")
check(TeamsProtocol.accepts([0x9a, 0x30, 0, 1, 1], for: .idle), "Captured idle acknowledgement must pass")
check(!TeamsProtocol.accepts([0x9a, 0x30, 0, 1, 0], for: .idle), "Rejected handshake must not be called active")
check(!TeamsProtocol.accepts([0x9a, 0x20, 0, 1, 1], for: .idle), "Stale reply from another request must be ignored")
check(!TeamsProtocol.accepts([0x9a, 0x30, 0, 2, 1], for: .idle), "Truncated payload must be rejected")
check(!TeamsProtocol.accepts([], for: .idle), "Empty USB reply must be rejected")
check(TeamsProtocol.localePayload(at: Date()).count == 26, "Locale/time payload must fit the tested framing")
var standalone = ButtonSettings()
standalone.standaloneTeamsButton = true
let standaloneRoundTrip = try JSONDecoder().decode(ButtonSettings.self, from: JSONEncoder().encode(standalone))
check(standaloneRoundTrip.standaloneTeamsButton == true, "Standalone setting must persist")
let oldStandalone = try JSONDecoder().decode(ButtonSettings.self, from: oldJSON)
check(oldStandalone.standaloneTeamsButton == nil, "Existing preferences must remain readable")
// Full-profile migration, isolation, persistence and keyboard assignment.
var current = ButtonSettings(signal: teamsPress, action: .openApp, target: "/Applications/ChatGPT.app")
current.focusTiming = .immediate; current.standaloneTeamsButton = true
var library = ButtonProfileLibrary.seeded(current: current, currentName: "Codex", alternatives: [
    ("Codex", .openApp, "/ignored.app"), ("Grok", .openURL, "https://grok.com/"), ("Siri", .openApp, "/System/Applications/Siri.app")])
let codexID = library.activeID
let grokID = library.profiles[1].id
check(library.profiles.count == 3, "Migration must avoid duplicate current preset")
check(library.active.settings == current, "Migration must preserve every current setting")
check(library.profiles[1].settings.signal == teamsPress && library.profiles[1].settings.effectiveFocusTiming == .immediate,
      "Other presets must inherit the tested hardware binding and timing")
library.assignInitialShortcuts()
check(library.hotkeys.count == 6, "Each seeded agent needs independent run and switch shortcuts")
check(library.active.runShortcut?.label == "⌃⌥⌘1", "Codex direct shortcut label")
check(library.active.activateShortcut?.label == "⌃⌥1", "Codex switch shortcut label")
try library.select(grokID)
check(library.active.settings.target == "https://grok.com/", "Switch must restore target")
var grok = library.active.settings; grok.focusTiming = .oneSecond; library.updateActive(grok)
let oldGrokShortcuts = library.active.runShortcut
check(library.migrateGrokWebProfile(to: "/Applications/Grok Bot.app"), "Grok web preset must migrate to the requested desktop app")
check(library.active.settings.action == .openApp && library.active.settings.target == "/Applications/Grok Bot.app", "Grok must open its desktop app")
check(library.active.settings.signal == teamsPress && library.active.settings.focusTiming == .oneSecond && library.active.runShortcut == oldGrokShortcuts, "Grok migration must preserve hardware, timing and shortcuts")
check(!library.migrateGrokWebProfile(to: "/Applications/Grok Bot.app"), "Grok app migration must be idempotent")
try library.select(codexID)
check(library.active.settings == current, "Editing Grok must not modify Codex")
try library.save(to: defaults)
let savedLibrary = try ButtonProfileLibrary.load(from: defaults)
check(savedLibrary == library, "All profiles and active selection must round-trip")
check(ButtonSettings.load(from: defaults) == current, "Legacy setting key must reflect active profile")
let copyID = try library.add(name: "  Work  ", settings: current)
check(copyID != codexID && library.active.name == "Work", "Save as needs unique ID and trimmed name")
check(library.active.runShortcut == nil && library.active.activateShortcut == nil, "Copies must not duplicate globally reserved keys")
try library.renameActive(to: "Deep work")
check(library.active.name == "Deep work", "Rename should preserve settings and identity")
try library.updateActiveShortcuts(activate: nil, run: KeyboardShortcut(keyCode: 21, modifiers: 7))
check(library.active.runShortcut?.label == "⌃⌥⌘4", "Custom shortcut must persist in current profile")
let previous = library
func mustThrow(_ message: String, _ operation: () throws -> Void) {
    var threw = false
    do { try operation() } catch { threw = true }
    check(threw, message)
}
mustThrow("Duplicate shortcut across profiles must be refused") {
    try library.updateActiveShortcuts(activate: nil, run: KeyboardShortcut(keyCode: 18, modifiers: 7))
}
check(library == previous, "Failed shortcut edit must be atomic")
mustThrow("Same shortcut cannot switch and run") {
    let key = KeyboardShortcut(keyCode: 21, modifiers: 7)
    try library.updateActiveShortcuts(activate: key, run: key)
}
mustThrow("Unmodified typing key must be refused") {
    try library.updateActiveShortcuts(activate: nil, run: KeyboardShortcut(keyCode: 0, modifiers: 0))
}
mustThrow("Invalid modifier bits must be refused") {
    try library.updateActiveShortcuts(activate: nil, run: KeyboardShortcut(keyCode: 0, modifiers: 128))
}
mustThrow("Modifier physical key cannot be assigned") {
    try library.updateActiveShortcuts(activate: nil, run: KeyboardShortcut(keyCode: 55, modifiers: 1))
}
mustThrow("Duplicate names must be case insensitive") { try library.renameActive(to: "CODEX") }
mustThrow("Blank names must be refused") { try library.renameActive(to: "  ") }
mustThrow("Missing profile must be refused") { try library.select(UUID()) }
try library.deleteActive()
check(library.profiles.count == 3 && !library.profiles.contains { $0.id == copyID }, "Delete must remove profile and its keys")
check(library.profiles.contains { $0.id == library.activeID }, "Delete must leave a valid active selection")
let legacyProfileJSON = "{\"profiles\":[{\"id\":\"\(codexID.uuidString)\",\"name\":\"Codex\",\"settings\":{\"action\":\"none\",\"target\":\"\",\"legacyControls\":false}}],\"activeID\":\"\(codexID.uuidString)\"}"
defaults.set(Data(legacyProfileJSON.utf8), forKey: ButtonProfileLibrary.defaultsKey)
let withoutKeys = try ButtonProfileLibrary.load(from: defaults)!
check(withoutKeys.hotkeys.isEmpty, "Existing profiles without shortcut fields must decode safely")
var single = withoutKeys
mustThrow("Last profile cannot be deleted") { try single.deleteActive() }
defaults.set(Data("broken library".utf8), forKey: ButtonProfileLibrary.defaultsKey)
mustThrow("Corrupt profile data must not silently decode") { _ = try ButtonProfileLibrary.load(from: defaults) }
try library.save(to: defaults)
check(defaults.data(forKey: ButtonProfileLibrary.recoveryKey) == Data("broken library".utf8), "Corrupt data must be backed up before recovery")
defaults.removeObject(forKey: ButtonProfileLibrary.defaultsKey)
defaults.removeObject(forKey: ButtonProfileLibrary.recoveryKey)
// Multiple headset buttons remain independent, and old profiles gain unassigned slots.
var multi = ButtonProfileLibrary.seeded(current: current, currentName: "Codex")
check(multi.active.resolvedButtons.count == 8, "Known button slots must be visible on old profiles")
check(multi.active.resolvedButtons.first { $0.id == "play" }?.settings.activationCondition == .audioIdle, "Play/pause extras default to idle-only")
let muteSignal = ButtonSignal(productID: 0x2e57, usagePage: 11, usage: 47, reportID: 2, cookie: 100, value: 1)
var muteSettings = ButtonSettings(signal: muteSignal, action: .openApp, target: "/Applications/Grok Bot.app")
muteSettings.activationCondition = .always
let mute = HeadsetButton(id: "mute", name: "Microphone mute", settings: muteSettings)
try multi.updateButton(mute, in: multi.activeID)
check(multi.active.settings == current, "Adding mute action must preserve primary action and hardware setup")
let beforeConflict = multi
mustThrow("Two buttons must not claim the same exact input") {
    try multi.updateButton(HeadsetButton(id: "play", name: "Play", settings: muteSettings), in: multi.activeID)
}
check(multi == beforeConflict, "Conflicting binding update must be atomic")
try multi.save(to: defaults)
let reloadedMulti = try ButtonProfileLibrary.load(from: defaults)!
check(reloadedMulti == multi, "All button mappings and conditions must persist")
let originalID = multi.activeID
_ = try multi.add(name: "Copy", settings: current)
check(multi.active.additionalButtons == multi.profiles.first { $0.id == originalID }?.additionalButtons, "Save-as must copy every extra button mapping")
var router = HeadsetButtonRouter()
let bindings = multi.active.resolvedButtons
check(router.consume(teamsPress, device: "390", buttons: bindings, now: 1).map(\.id) == ["teams"], "Teams must dispatch only its own action")
check(router.consume(muteSignal, device: "390", buttons: bindings, now: 1.01).map(\.id) == ["mute"], "Different buttons must not debounce each other")
check(router.consume(muteSignal, device: "390", buttons: bindings, now: 2).isEmpty, "Held mute input must not repeat")
var muteRelease = ButtonSignal(productID: 0x2e57, usagePage: 11, usage: 47, reportID: 2, cookie: 100, value: 0)
_ = router.consume(muteRelease, device: "390", buttons: bindings, now: 2.1)
check(router.consume(muteSignal, device: "390", buttons: bindings, now: 2.5).map(\.id) == ["mute"], "Releasing mute must re-arm it")
router.reset()
check(router.consume(muteSignal, device: "390", buttons: bindings, now: 3).count == 1, "Profile/reconnect reset must re-arm all buttons")
let custom = HeadsetButton(id: "custom-test", name: "Custom", settings: ButtonSettings())
try multi.updateButton(custom, in: multi.activeID)
check(multi.active.resolvedButtons.count == 9, "Custom buttons must appear beside known slots")
try multi.removeCustomButton(custom.id, in: multi.activeID)
check(multi.active.resolvedButtons.count == 8, "Removing custom button must keep known slots")
// Audio state is conservative around pause and unknown/error transitions.
var gate = AudioActivityGate()
check(!ButtonActivationCondition.audioIdle.permits(.unknown), "Unknown audio must not pass an idle-only rule")
check(ButtonActivationCondition.always.permits(.unknown), "Always must work when audio detection is unavailable")
gate.update(.idle, now: 0)
check(gate.state == .unknown, "Startup requires a quiet observation window")
gate.update(.idle, now: 2)
check(gate.state == .idle, "Two quiet seconds must establish idle")
gate.update(.active, now: 3)
check(gate.state == .active && !ButtonActivationCondition.audioIdle.permits(gate.state), "Playback must immediately suppress idle-only actions")
gate.update(.idle, now: 3.1)
gate.update(.idle, now: 4.9)
check(gate.state == .active, "Pausing a movie must not immediately trigger an idle-only action")
gate.update(.idle, now: 5.2)
check(gate.state == .idle && ButtonActivationCondition.audioIdle.permits(gate.state), "Idle-only actions must resume after the settling interval")
gate.update(.unknown, now: 6)
check(gate.state == .unknown, "Unknown route must clear the previous idle result")
check(ButtonActivationCondition.audioActive.permits(.active) && !ButtonActivationCondition.audioActive.permits(.idle), "Active-only rule must distinguish playback")
defaults.removeObject(forKey: ButtonProfileLibrary.defaultsKey)
// Siri is pinned, while enabled agents receive contiguous numbers and global shortcuts.
var agents = ButtonProfileLibrary.seeded(current: current, currentName: "Codex", alternatives: [("Grok", .openApp, "/Applications/Grok Bot.app"), ("Siri", .openApp, ButtonProfileLibrary.siriPath)])
let originalCodex = agents.activeID
try agents.configureAgentCatalog([("Codex", "/Applications/ChatGPT.app"), ("Grok Bot", "/Applications/Grok Bot.app"), ("Claude", "/Applications/Claude.app"), ("Hermes", "/Applications/Hermes.app"), ("OpenClaw", nil)])
let siri = agents.profiles[0]
let grokAgent = agents.profiles.first { $0.name == "Grok Bot" }!
let openClaw = agents.profiles.first { $0.name == "OpenClaw" }!
check(siri.builtInSiri == true && agents.number(for: siri.id) == 1, "Siri must be pinned as agent 1")
check(siri.runShortcut?.label == "⌃⌥⌘1", "Agent 1 shortcut must run Siri")
check(agents.activeID == originalCodex && agents.active.settings == current, "Catalog migration must retain the selected profile and all hardware settings")
check(agents.number(for: originalCodex) == 2 && agents.active.runShortcut?.label == "⌃⌥⌘2", "Codex must be numbered after Siri")
check(!openClaw.isEnabled && agents.number(for: openClaw.id) == nil && openClaw.runShortcut == nil, "Unconfigured agents must have no number or shortcut")
check(agents.enabledProfiles.count == 5 && agents.hotkeys.count == 12, "Only enabled agents register keyboard shortcuts")
try agents.moveAgent(originalCodex, offset: 1)
check(agents.number(for: grokAgent.id) == 2 && agents.number(for: originalCodex) == 3, "Reordering must update numbering")
check(agents.active.runShortcut?.label == "⌃⌥⌘3" && agents.active.settings == current, "Reordering must update keys without touching actions or headset mappings")
try agents.setAgentEnabled(grokAgent.id, enabled: false)
check(agents.number(for: grokAgent.id) == nil && agents.number(for: originalCodex) == 2, "Disabling removes number and closes gaps")
check(!agents.hotkeys.contains { $0.profileID == grokAgent.id }, "Disabled agents must not register shortcuts")
mustThrow("Cannot select a disabled agent") { try agents.select(grokAgent.id) }
try agents.setAgentEnabled(originalCodex, enabled: false)
check(agents.activeID == siri.id, "Disabling current profile must fall back to Siri")
mustThrow("Siri cannot be disabled") { try agents.setAgentEnabled(siri.id, enabled: false) }
mustThrow("Siri cannot be moved") { try agents.moveAgent(siri.id, offset: 1) }
mustThrow("Siri cannot be removed") { try agents.removeAgent(siri.id) }
mustThrow("Siri cannot be renamed") { try agents.renameActive(to: "Other Siri") }
mustThrow("Siri shortcuts are fixed") { try agents.updateActiveShortcuts(activate: nil, run: nil) }
var overwriteSiri = agents.active.settings; overwriteSiri.action = .openURL; overwriteSiri.target = "https://example.com"
agents.updateActive(overwriteSiri)
check(agents.active.settings.action == .openApp && agents.active.settings.target == ButtonProfileLibrary.siriPath, "Siri's primary action remains hardcoded")
mustThrow("Missing OpenClaw target must block enabling") { try agents.setAgentEnabled(openClaw.id, enabled: true) }
let customAgent = try agents.addAgent(name: "Local helper")
check(agents.number(for: customAgent) == nil, "New agents start disabled until configured")
var customSettings = current; customSettings.action = .openURL; customSettings.target = "helper://open"
try agents.updateAgent(customAgent, name: "Local helper", settings: customSettings)
try agents.setAgentEnabled(customAgent, enabled: true)
check(agents.number(for: customAgent) != nil, "Configured custom agents can be enabled")
try agents.removeAgent(openClaw.id)
let afterRemove = agents
try agents.configureAgentCatalog([("OpenClaw", nil)])
check(agents == afterRemove, "One-time catalog migration must not restore removed agents")
try agents.save(to: defaults)
let restoredAgents = try ButtonProfileLibrary.load(from: defaults)!
check(restoredAgents == agents, "Agent ordering, enable switches and hardcoded Siri identity must persist")
defaults.removeObject(forKey: ButtonProfileLibrary.defaultsKey)
// Previous/next follow the enabled order, wrap, and reserve their own configurable keys.
let enabledOrder = agents.enabledProfiles
try agents.select(enabledOrder[0].id)
check(agents.cycleTarget(offset: -1)?.id == enabledOrder.last?.id, "Previous from Siri wraps to the last enabled agent")
check(agents.cycleTarget(offset: 1)?.id == enabledOrder[1].id, "Next follows the enabled order")
try agents.select(enabledOrder.last!.id)
check(agents.cycleTarget(offset: 1)?.id == enabledOrder[0].id, "Next from the last enabled agent wraps to Siri")
check(agents.effectiveCycleShortcuts.previous?.label == "⌃⌥←" && agents.effectiveCycleShortcuts.next?.label == "⌃⌥→", "Cycle defaults must be visible and predictable")
check(agents.hotkeys.contains { $0.purpose == .previous } && agents.hotkeys.contains { $0.purpose == .next }, "Cycle keys must register globally")
let cycleBefore = agents
mustThrow("Cycle keys must not conflict with direct agent shortcuts") {
    try agents.updateCycleShortcuts(previous: agents.profiles[0].runShortcut, next: nil)
}
check(agents == cycleBefore, "Rejected cycle shortcut change must be atomic")
try agents.updateCycleShortcuts(previous: nil, next: KeyboardShortcut(keyCode: 124, modifiers: 7))
check(!agents.hotkeys.contains { $0.purpose == .previous }, "Clearing previous shortcut must disable it")
try agents.save(to: defaults)
let cycleReload = try ButtonProfileLibrary.load(from: defaults)!
check(cycleReload.effectiveCycleShortcuts.previous == nil && cycleReload.effectiveCycleShortcuts.next?.modifiers == 7, "Cycle key settings must persist including disabled keys")
defaults.removeObject(forKey: ButtonProfileLibrary.defaultsKey)
// Named secondary actions remain separate from Open and can be bound to headset inputs.
var secondary = ButtonProfileLibrary.seeded(current: current, currentName: "Codex")
let parentID = secondary.activeID
var voice = AgentSecondaryAction(name: "Voice")
check(!voice.isConfigured, "Unconfigured voice template must never claim it works")
voice.kind = .url; voice.target = "javascript:bad"
check(!voice.isConfigured, "Unsafe secondary URL must be rejected")
voice.target = "agent://voice"
check(voice.isConfigured, "App deep links must be supported")
voice.hotkey = KeyboardShortcut(keyCode: 24, modifiers: 7)
try secondary.updateSecondaryAction(voice, in: parentID)
check(secondary.active.settings == current, "Secondary action must not replace Open")
check(secondary.hotkeys.contains { $0.purpose == .secondary && $0.secondaryActionID == voice.id }, "Configured secondary action can have its own hotkey")
let ref = AgentActionReference(profileID: parentID, actionID: voice.id)
check(AgentActionReference(ref.encoded) == ref, "Action references must round-trip")
check(AgentActionReference("not/an/id") == nil, "Malformed action reference must be rejected")
var bound = ButtonSettings(signal: muteSignal, action: .agentAction, target: ref.encoded)
check(bound.validationError == nil, "A headset input can run a named action")
try secondary.updateButton(HeadsetButton(id: "mute", name: "Mute", settings: bound), in: parentID)
let childID = try secondary.add(name: "Other agent", settings: current)
check(secondary.active.secondaryActions?.first?.hotkey == nil, "Copies must not duplicate secondary global shortcuts")
let copiedRef = AgentActionReference(secondary.active.resolvedButtons.first { $0.id == "mute" }!.settings.target)
check(copiedRef?.profileID == childID && copiedRef?.actionID == voice.id, "Copied self-references must point at copied agent actions")
try secondary.removeSecondaryAction(voice.id, in: parentID)
check(secondary.profiles.first { $0.id == parentID }?.resolvedButtons.first { $0.id == "mute" }?.settings.action == ButtonAction.none, "Removing an action must clear stale input references")
try secondary.save(to: defaults)
let savedSecondary = try ButtonProfileLibrary.load(from: defaults)!
check(savedSecondary == secondary, "Secondary actions and references must persist")
var badDelay = voice; badDelay.delay = .nan
check(!badDelay.isConfigured, "Nonfinite action delays must be rejected")
var keyAction = AgentSecondaryAction(name: "New chat")
keyAction.key = KeyboardShortcut(keyCode: 45, modifiers: 1)
check(keyAction.isConfigured, "A configured target-app shortcut must be valid")
var recursive = current; recursive.action = .agentAction; recursive.target = ref.encoded
mustThrow("Primary Open actions must not recurse into agent actions") { try secondary.updateAgent(childID, name: "Other agent", settings: recursive) }
defaults.removeObject(forKey: ButtonProfileLibrary.defaultsKey)
// Headset activation chains enabled actions in order, without reopening the agent.
var firstAuto = AgentSecondaryAction(name: "New chat"); firstAuto.key = KeyboardShortcut(keyCode: 45, modifiers: 1)
var secondAuto = AgentSecondaryAction(name: "Voice"); secondAuto.key = KeyboardShortcut(keyCode: 9, modifiers: 12)
var manual = secondAuto; manual.id = UUID(); manual.runAfterHeadset = false
var chainProfile = ButtonProfile(name: "Agent", settings: current); chainProfile.secondaryActions = [firstAuto, manual, secondAuto]
check(chainProfile.automaticActions.map(\.name) == ["New chat", "Voice"], "Only enabled automatic actions enter the chain")
var calls: [String] = []; var finished = false
AutomaticAgentActions.run(chainProfile.automaticActions, perform: { action, next in
    check(!action.openAgentFirst, "Automatic steps must not reopen the agent")
    calls.append(action.name); next(nil)
}, completion: { error in finished = error == nil })
check(calls == ["New chat", "Voice"] && finished, "Automatic steps must run sequentially after primary success")
calls = []; var failure: String?
AutomaticAgentActions.run(chainProfile.automaticActions, perform: { action, next in calls.append(action.name); next("failed") }, completion: { failure = $0 })
check(calls == ["New chat"] && failure == "failed", "A failed step must stop the remaining actions")
chainProfile.automaticActionSelection = secondAuto.id.uuidString
check(chainProfile.automaticActions.map(\.name) == ["Voice"], "Explicit selection runs only that secondary action")
chainProfile.automaticActionSelection = "none"
check(chainProfile.automaticActions.isEmpty, "None disables automatic secondary actions")
chainProfile.automaticActionSelection = nil
check(chainProfile.automaticActions.count == 2, "All retains the enabled ordered chain")
var presetLibrary = ButtonProfileLibrary.seeded(current: current, currentName: "Codex")
let presetParent = presetLibrary.activeID
check(presetLibrary.installCodexActionPresets(for: presetParent), "Screenshot action presets must install")
check(presetLibrary.active.secondaryActions?.count == 9, "All nine requested actions must be present")
check(presetLibrary.active.automaticActions.isEmpty, "New presets must not all run automatically")
let requested = presetLibrary.active.secondaryActions!
check(requested.first { $0.presetID == "dot.open" }?.key == KeyboardShortcut(keyCode: 47, modifiers: 1), "Dot shortcut must match screenshot")
check(requested.first { $0.presetID == "voice.start" }?.key == KeyboardShortcut(keyCode: 9, modifiers: 5), "Voice start must use the supplied custom shortcut")
check(requested.first { $0.presetID == "voice.end" }?.key == KeyboardShortcut(keyCode: 9, modifiers: 9), "End voice must match screenshot")
var dotStep = requested.first { $0.presetID == "dot.open" }!; dotStep.runAfterHeadset = true
var voiceStep = requested.first { $0.presetID == "voice.start" }!; voiceStep.runAfterHeadset = true
try presetLibrary.updateSecondaryAction(dotStep, in: presetParent)
try presetLibrary.updateSecondaryAction(voiceStep, in: presetParent)
check(presetLibrary.active.automaticActions.map(\.presetID) == ["dot.open", "voice.start"], "Checked actions form an ordered subset stack")
check(!presetLibrary.installCodexActionPresets(for: presetParent), "Preset installation must preserve later customization")
// Observed from Evolve2 65 / Link 380 on 2026-11-07, including long-button tests.
let link380TeamsPress = ButtonSignal(productID: 0x24c8, usagePage: 0xff99, usage: 4, reportID: 155, cookie: 76, value: 1, deviceName: "Jabra Link 380")
let link380TeamsRelease = ButtonSignal(productID: 0x24c8, usagePage: 0xff99, usage: 4, reportID: 155, cookie: 76, value: 0)
var observedSettings = ButtonSettings(signal: teamsPress, action: .openApp, target: "/Applications/ChatGPT.app")
observedSettings.learnInput(link380TeamsPress)
var observedRouter = HeadsetButtonRouter()
let observedButtons = [HeadsetButton(id: "teams", name: "Teams", settings: observedSettings)]
check(observedRouter.consume(link380TeamsPress, device: "Link380", buttons: observedButtons, now: 1).count == 1, "Captured Link 380 Teams press must route")
check(observedRouter.consume(link380TeamsRelease, device: "Link380", buttons: observedButtons, now: 1.005).isEmpty, "Captured Link 380 release pulse must not route")
check(observedRouter.consume(link380TeamsPress, device: "Link380", buttons: observedButtons, now: 2).count == 1, "Repeated captured Link 380 Teams press must route")
check(observedRouter.consume(teamsPress, device: "Link390", buttons: observedButtons, now: 2.01).count == 1, "Link 390 must still route beside the captured Link 380 input")

// Multiple USB products share an action while preserving their own inputs.
// The second product ID is synthetic; hardware signals must be learned locally.
let otherHeadsetPress = ButtonSignal(productID: 0x7001, usagePage: 11, usage: 47, reportID: 7, cookie: 19, value: 1, deviceName: "Test second headset")
let otherHeadsetRelease = ButtonSignal(productID: 0x7001, usagePage: 11, usage: 47, reportID: 7, cookie: 19, value: 0)
var twoHeadsets = try JSONDecoder().decode(ButtonSettings.self, from: oldJSON)
let originalHeadsetInput = twoHeadsets.signal!
check(twoHeadsets.learnedSignals == [originalHeadsetInput], "Old single-input preferences must load unchanged")
twoHeadsets.learnInput(otherHeadsetPress)
check(twoHeadsets.signal == originalHeadsetInput && twoHeadsets.learnedSignals.count == 2, "Learning a second headset must preserve the original input")
let restoredHeadsets = try JSONDecoder().decode(ButtonSettings.self, from: JSONEncoder().encode(twoHeadsets))
check(restoredHeadsets == twoHeadsets && restoredHeadsets.learnedSignals.last?.deviceName == "Test second headset", "All headset inputs and names must persist")
var multipleRouter = HeadsetButtonRouter()
let sharedButton = HeadsetButton(id: "teams", name: "Teams", settings: twoHeadsets)
check(multipleRouter.consume(originalHeadsetInput, device: "first", buttons: [sharedButton], now: 1).count == 1, "The original headset must still trigger")
check(multipleRouter.consume(otherHeadsetPress, device: "second", buttons: [sharedButton], now: 1.01).count == 1, "A second headset must trigger independently of the first debounce")
check(multipleRouter.consume(otherHeadsetPress, device: "second", buttons: [sharedButton], now: 2).isEmpty, "The second headset must retain held-key protection")
check(multipleRouter.consume(otherHeadsetRelease, device: "second", buttons: [sharedButton], now: 2.1).isEmpty, "The second headset release must only rearm")
check(multipleRouter.consume(otherHeadsetPress, device: "second", buttons: [sharedButton], now: 2.5).count == 1, "A second headset must trigger after release")
check(multipleRouter.consume(signal(1, product: 0x7002), device: "unlearned", buttons: [sharedButton], now: 3).isEmpty, "An unlearned headset must not trigger")
let replacedHeadsetPress = ButtonSignal(productID: 0x7001, usagePage: 12, usage: 1, reportID: 8, cookie: 20, value: 1)
twoHeadsets.learnInput(replacedHeadsetPress)
check(twoHeadsets.learnedSignals.count == 2 && twoHeadsets.signal == originalHeadsetInput && twoHeadsets.learnedSignals.last == replacedHeadsetPress, "Relearning a headset replaces only that product's input")
twoHeadsets.removeInput(replacedHeadsetPress)
check(twoHeadsets.learnedSignals == [originalHeadsetInput] && twoHeadsets.additionalSignals == nil, "Removing the added headset preserves the original binding")
twoHeadsets.learnInput(otherHeadsetPress)
twoHeadsets.removeInput(originalHeadsetInput)
check(twoHeadsets.signal == otherHeadsetPress && twoHeadsets.additionalSignals == nil, "Removing the original binding promotes the remaining headset")
twoHeadsets.removeInput(otherHeadsetPress)
check(twoHeadsets.signal == nil && twoHeadsets.learnedSignals.isEmpty, "Removing the last input clears the mapping")
var multiDeviceLibrary = ButtonProfileLibrary.seeded(current: restoredHeadsets, currentName: "Codex")
let beforeMultiDeviceConflict = multiDeviceLibrary
var secondDeviceConflict = ButtonSettings(signal: otherHeadsetPress, action: .openApp, target: "/Applications/Grok Bot.app")
secondDeviceConflict.signal?.deviceName = "Different display name"
mustThrow("A second headset input must not be assigned to two physical button slots") {
    try multiDeviceLibrary.updateButton(HeadsetButton(id: "mute", name: "Mute", settings: secondDeviceConflict), in: multiDeviceLibrary.activeID)
}
check(multiDeviceLibrary == beforeMultiDeviceConflict, "A conflicting secondary-device input must leave the library unchanged")
var multiDeviceDefaults = UserDefaults(suiteName: "JabraTeamsRemap.MultiDeviceTests.\(UUID().uuidString)")!
try multiDeviceLibrary.save(to: multiDeviceDefaults)
check(try! ButtonProfileLibrary.load(from: multiDeviceDefaults) == multiDeviceLibrary, "The full profile library must preserve both headset inputs")
multiDeviceDefaults.removeObject(forKey: ButtonProfileLibrary.defaultsKey)

check(multi.active.resolvedButtons.first { $0.id == "micArm" }?.settings.signal == nil, "Existing profiles gain an unassigned microphone arm without changing mute bindings")

// Device selection limits triggers without conflating two physical adapters.
let link380Device = ConnectedHeadset(productID: 0x24c8, locationID: 100, name: "Jabra Link 380")
let link390Device = ConnectedHeadset(productID: 0x2e57, locationID: 200, name: "Jabra Link 390")
let second380Device = ConnectedHeadset(productID: 0x24c8, locationID: 300, name: "Jabra Link 380")
check(link380Device.id != second380Device.id, "Two adapters with the same USB product must remain selectable individually")
var inputSelection = HeadsetInputSelection(deviceID: link380Device.id)
check(inputSelection.accepts(link380Device) && !inputSelection.accepts(link390Device) && !inputSelection.accepts(second380Device), "Only the selected physical adapter may trigger actions")
inputSelection.save(to: multiDeviceDefaults)
check(HeadsetInputSelection.load(from: multiDeviceDefaults) == inputSelection, "Selected headset must persist across relaunch")
check(!inputSelection.accepts(link390Device), "A disconnected selected headset must not silently switch to another")
inputSelection.deviceID = nil
inputSelection.save(to: multiDeviceDefaults)
check(HeadsetInputSelection.load(from: multiDeviceDefaults).accepts(link380Device) && inputSelection.accepts(link390Device), "All connected headsets mode must accept either adapter")
check(multiDeviceDefaults.string(forKey: HeadsetInputSelection.defaultsKey) == nil, "All mode must clear the saved device preference")


// Distinct physical adapters must not suppress each other's button presses.
var physicalRouter = HeadsetButtonRouter()
let physicalSignal = signal(1)
let physicalButton = HeadsetButton(id: "teams", name: "Teams", settings: ButtonSettings(signal: physicalSignal))
check(physicalRouter.consume(physicalSignal, device: "port-A", buttons: [physicalButton], now: 10).count == 1, "First adapter fires")
check(physicalRouter.consume(physicalSignal, device: "port-B", buttons: [physicalButton], now: 10.1).count == 1, "Second same-model adapter fires independently")
check(physicalRouter.consume(physicalSignal, device: "port-A", buttons: [physicalButton], now: 10.2).isEmpty, "Duplicate interface report on same adapter stays suppressed")
let selectedAudio = ConnectedHeadset(productID: 9416, locationID: 1, name: "Jabra Link 380", serialNumber: "TEST-A")
check(HeadsetAudioRoute.matches(modelUID: "Jabra Link 380:0B0E:24C8", deviceUID: "AppleUSBAudioEngine:Jabra:Link:TEST-A:1", selected: selectedAudio) == true, "Selected adapter audio matches serial and model")
check(HeadsetAudioRoute.matches(modelUID: "Jabra Link 380:0B0E:24C8", deviceUID: "AppleUSBAudioEngine:Jabra:Link:TEST-B:1", selected: selectedAudio) == false, "Other same-model audio excluded")
check(HeadsetAudioRoute.matches(modelUID: "Jabra Link 390:0B0E:2E57", deviceUID: "AppleUSBAudioEngine:Jabra:Link:TEST-A:1", selected: selectedAudio) == false, "Other adapter model audio excluded")
check(HeadsetAudioRoute.matches(modelUID: "Jabra Link 380:0B0E:24C8", deviceUID: "unknown", selected: ConnectedHeadset(productID: 9416, locationID: 1, name: "Jabra")) == nil, "Missing serial remains unknown")
var deletionLibrary = ButtonProfileLibrary.seeded(current: ButtonSettings(action: .openApp, target: "/Applications/Example.app"), currentName: "Example")
let deletedAction = AgentSecondaryAction(name: "Example", kind: .url, target: "https://example.com")
try deletionLibrary.updateSecondaryAction(deletedAction, in: deletionLibrary.activeID)
try deletionLibrary.setAutomaticActionSelection(deletedAction.id.uuidString, for: deletionLibrary.activeID)
try deletionLibrary.removeSecondaryAction(deletedAction.id, in: deletionLibrary.activeID)
check(deletionLibrary.active.automaticActionSelection == "none", "Deleting selected action explicitly selects None")
let generationCheck = ActionGeneration()
let beforeCancel = generationCheck.checkpoint()
check(beforeCancel(), "New generation valid")
generationCheck.cancel()
check(!beforeCancel() && generationCheck.checkpoint()(), "Cancel invalidates only old work")

print("Passed \(count) mapping, profile, button and audio-rule checks")
