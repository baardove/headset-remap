import Cocoa
import ApplicationServices

enum CodexVoiceToggle {
    static func isEndVoiceLabel(_ text: String) -> Bool {
        ["end voice chat", "stop voice chat", "end voice", "avslutt tale", "avslutt talesamtale"].contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
    static func isStartVoiceLabel(_ text: String) -> Bool {
        ["start voice chat", "start voice", "start tale", "start talesamtale"].contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
    static func classify(foundEnd: Bool, foundStart: Bool, complete: Bool) -> CodexVoiceState {
        if foundEnd { return .active }
        return complete && foundStart ? .inactive : .unknown
    }
    /// Read only. Incomplete or unrecognized accessibility trees never imply an active call.
    static func probe(processID: pid_t) -> (state: CodexVoiceState, control: AXUIElement?) {
        guard AXIsProcessTrusted() else { return (.unknown, nil) }
        let root = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(root, 0.03)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windows) == .success,
              let list = windows as? [AXUIElement], !list.isEmpty else { return (.unknown, nil) }
        var pending = list
        var cursor = 0
        var complete = true
        var foundStart = false
        let deadline = ProcessInfo.processInfo.systemUptime + 0.35
        while cursor < pending.count && cursor < 4000 && ProcessInfo.processInfo.systemUptime < deadline {
            let element = pending[cursor]; cursor += 1
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) != .success { complete = false }
            if role as? String == kAXButtonRole {
                for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] {
                    var label: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, attribute as CFString, &label) == .success, let text = label as? String {
                        if isEndVoiceLabel(text) { return (.active, element) }
                        if isStartVoiceLabel(text) { foundStart = true }
                    }
                }
            }
            var children: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
            if result == .success, let values = children as? [AXUIElement] {
                let capacity = max(0, 4000 - pending.count)
                pending.append(contentsOf: values.prefix(capacity))
                if values.count > capacity { complete = false }
            } else if result != .success && result != .noValue && result != .attributeUnsupported { complete = false }
        }
        complete = complete && cursor == pending.count
        return (classify(foundEnd: false, foundStart: foundStart, complete: complete), nil)
    }
    /// True means a detected active voice session was handled; skip the launch chain.
    static func isConfigured(in profile: ButtonProfile) -> Bool {
        profile.settings.action == .openApp &&
            Bundle(path: profile.settings.target)?.bundleIdentifier == "com.openai.codex" &&
            profile.automaticActions.contains { $0.kind == .keyboard && ($0.presetID == "voice.start" || $0.key == KeyboardShortcut(keyCode: 9, modifiers: 12) || $0.key == KeyboardShortcut(keyCode: 9, modifiers: 5)) }
    }

    static func stopIfActive(profile: ButtonProfile) -> Bool {
        guard isConfigured(in: profile),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first,
              let control = probe(processID: app.processIdentifier).control else { return false }
        _ = app.activate(options: [])
        let result = AXUIElementPerformAction(control, kAXPressAction as CFString)
        AppLog.log(result == .success ? "VOICE stopped: active Codex voice session" : "VOICE stop failed: \(result.rawValue); action chain canceled")
        return true
    }
}

/// Polls actual app controls off the main thread, including externally started calls.
final class CodexVoiceMonitor {
    private let queue = DispatchQueue(label: "HeadsetRemap.voice-state", qos: .utility)
    private var timer: Timer?
    private var generation = 0
    private var inFlight = false
    private let processID: () -> pid_t?
    private let readState: (pid_t) -> CodexVoiceState
    private let interval: TimeInterval
    private(set) var state: CodexVoiceState = .unknown
    var onChange: ((CodexVoiceState) -> Void)?

    init(interval: TimeInterval = 1, processID: @escaping () -> pid_t? = {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first?.processIdentifier
    }, readState: @escaping (pid_t) -> CodexVoiceState = { CodexVoiceToggle.probe(processID: $0).state }) {
        self.interval = interval; self.processID = processID; self.readState = readState
    }
    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.sample() }
        sample()
    }
    func stop() { timer?.invalidate(); timer = nil; generation += 1; inFlight = false }
    func refresh() { sample() }
    private func publish(_ value: CodexVoiceState) {
        guard value != state else { return }
        state = value; onChange?(value)
    }
    private func sample() {
        guard !inFlight else { return }
        guard let pid = processID() else { publish(.inactive); return }
        inFlight = true
        let token = generation
        let read = readState
        queue.async { [weak self] in
            let value = read(pid)
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.inFlight = false
                self.publish(value)
            }
        }
    }
}

enum CodexVoiceStatusIcon {
    static func activeImage(agent: String = "Codex") -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { rect in
            NSColor(calibratedRed: 1, green: 0.76, blue: 0.42, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(calibratedWhite: 0.12, alpha: 1)]))
            if let symbol = NSImage(systemSymbolName: "headphones", accessibilityDescription: "\(agent) voice active")?.withSymbolConfiguration(config) {
                symbol.draw(at: NSPoint(x: (rect.width - symbol.size.width) / 2, y: (rect.height - symbol.size.height) / 2), from: .zero, operation: .sourceOver, fraction: 1)
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
