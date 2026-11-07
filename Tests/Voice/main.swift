import Foundation
enum AppLog { static func log(_ value: String) {} }
precondition(CodexVoiceToggle.isEndVoiceLabel("End voice chat"))
precondition(CodexVoiceToggle.isEndVoiceLabel("Stop voice chat"))
precondition(CodexVoiceToggle.isEndVoiceLabel("Avslutt tale"))
precondition(!CodexVoiceToggle.isEndVoiceLabel("Start voice chat"))
precondition(!CodexVoiceToggle.isEndVoiceLabel("End call"))
print("Passed 5 voice-control label checks")
precondition(CodexVoiceToggle.classify(foundEnd: true, foundStart: false, complete: false) == .active)
precondition(CodexVoiceToggle.classify(foundEnd: false, foundStart: true, complete: true) == .inactive)
precondition(CodexVoiceToggle.classify(foundEnd: false, foundStart: true, complete: false) == .unknown)
precondition(CodexVoiceToggle.classify(foundEnd: false, foundStart: false, complete: true) == .unknown)
precondition(CodexVoiceToggle.isStartVoiceLabel("Start voice chat"))
precondition(!CodexVoiceToggle.isStartVoiceLabel("End voice chat"))
let icon = CodexVoiceStatusIcon.activeImage()
precondition(!icon.isTemplate && icon.size.width == 22 && icon.tiffRepresentation != nil)
var observed: [CodexVoiceState] = []
var current: CodexVoiceState = .active
let stateLock = NSLock()
let monitor = CodexVoiceMonitor(interval: 0.02, processID: { 42 }, readState: { _ in
    stateLock.lock(); defer { stateLock.unlock() }; return current
})
monitor.onChange = { observed.append($0) }
monitor.start()
RunLoop.main.run(until: Date().addingTimeInterval(0.12))
stateLock.lock(); current = .inactive; stateLock.unlock()
RunLoop.main.run(until: Date().addingTimeInterval(0.12))
precondition(observed == [.active, .inactive], "External state changes must update the monitor without button input")
monitor.stop()
let stoppedCount = observed.count
stateLock.lock(); current = .active; stateLock.unlock()
RunLoop.main.run(until: Date().addingTimeInterval(0.08))
precondition(observed.count == stoppedCount, "Stopped monitor must not publish changes")
let unavailable = CodexVoiceMonitor(processID: { nil }, readState: { _ in fatalError("No process must not be queried") })
unavailable.start()
precondition(unavailable.state == .inactive)
unavailable.stop()
print("Passed 10 voice-state, icon and polling checks in addition to the 5 label checks; no live call queried or started")
