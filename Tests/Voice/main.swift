import Foundation
enum AppLog { static func log(_ value: String) {} }
precondition(CodexVoiceToggle.isEndVoiceLabel("End voice chat"))
precondition(CodexVoiceToggle.isEndVoiceLabel("Stop voice chat"))
precondition(CodexVoiceToggle.isEndVoiceLabel("Avslutt tale"))
precondition(!CodexVoiceToggle.isEndVoiceLabel("Start voice chat"))
precondition(!CodexVoiceToggle.isEndVoiceLabel("End call"))
print("Passed 5 voice-control label checks")
