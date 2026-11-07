import Foundation

struct ButtonSignal: Codable, Hashable {
    let productID: Int
    let usagePage: UInt32
    let usage: UInt32
    let reportID: UInt32
    let cookie: UInt32
    let value: Int
    var deviceName: String? = nil

    var source: String { "\(productID):\(usagePage):\(usage):\(reportID):\(cookie)" }
    var bindingID: String { "\(source):\(value)" }
    var deviceLabel: String {
        let name = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? String(format: "Jabra USB %04X", productID) : name
    }
    var label: String {
        String(format: "USB %04X · page %04X · usage %04X · report %d · element %d · value %d",
               productID, usagePage, usage, reportID, cookie, value)
    }

    func sameElement(as other: ButtonSignal) -> Bool { source == other.source }
}

enum ButtonAction: String, Codable, CaseIterable {
    case openApp, openURL, shortcut, none, agentAction
    static let primaryCases: [Self] = [.openApp, .openURL, .shortcut, .none]
    var title: String {
        switch self {
        case .openApp: return "Open or activate an app"
        case .openURL: return "Open a URL"
        case .shortcut: return "Run a macOS Shortcut"
        case .none: return "Do nothing"
        case .agentAction: return "Run an agent action"
        }
    }
    var hint: String {
        switch self {
        case .openApp: return "Choose an application, for example ChatGPT or Codex."
        case .openURL: return "Enter a complete URL, including https:// or the app's URL scheme."
        case .shortcut: return "Enter the exact name of a shortcut from the Shortcuts app."
        case .none: return "The learned button will not run an action."
        case .agentAction: return "Choose a named action from the agent menu."
        }
    }
}

enum AgentFocusTiming: String, Codable, CaseIterable {
    case immediate, afterTeams, oneSecond

    var title: String {
        switch self {
        case .immediate: return "Activate immediately"
        case .afterTeams: return "Let Teams finish (0.5 seconds)"
        case .oneSecond: return "Wait 1 second"
        }
    }
    var delay: TimeInterval {
        switch self {
        case .immediate: return 0
        case .afterTeams: return 0.5
        case .oneSecond: return 1
        }
    }
}

struct ButtonSettings: Codable, Equatable {
    var signal: ButtonSignal?
    // Keep the original input so old preferences remain valid. Additional
    // products let wired headsets and USB adapters share the same button action.
    var additionalSignals: [ButtonSignal]?
    var action: ButtonAction = .none
    var target: String = ""
    var legacyControls = false
    // Optional for compatibility with configurations saved before focus timing.
    var focusTiming: AgentFocusTiming?
    var standaloneTeamsButton: Bool?
    var activationCondition: ButtonActivationCondition?

    var learnedSignals: [ButtonSignal] {
        var seen = Set<String>()
        return ([signal].compactMap { $0 } + (additionalSignals ?? []))
            .filter { seen.insert($0.bindingID).inserted }
    }

    mutating func learnInput(_ input: ButtonSignal) {
        var inputs = learnedSignals
        if let index = inputs.firstIndex(where: { $0.productID == input.productID }) {
            // Relearning one device must not replace another device's input.
            inputs[index] = input
            inputs = inputs.enumerated().filter { $0.offset == index || $0.element.productID != input.productID }.map(\.element)
        } else { inputs.append(input) }
        setInputs(inputs)
    }

    mutating func removeInput(_ input: ButtonSignal) {
        setInputs(learnedSignals.filter { $0.bindingID != input.bindingID })
    }

    private mutating func setInputs(_ inputs: [ButtonSignal]) {
        signal = inputs.first
        additionalSignals = inputs.count > 1 ? Array(inputs.dropFirst()) : nil
    }

    var effectiveFocusTiming: AgentFocusTiming {
        focusTiming ?? (signal?.usagePage == 0xFF99 ? .afterTeams : .immediate)
    }

    static let defaultsKey = "customButtonSettings.v1"
    static func load(from defaults: UserDefaults = .standard) -> ButtonSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return settings
    }
    func save(to defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }

    var validationError: String? {
        if action == .none { return nil }
        let text = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "Choose an app or enter a target for the selected action." }
        switch action {
        case .openApp:
            if !text.hasPrefix("/") || !text.hasSuffix(".app") {
                return "Choose an application with the Choose App button."
            }
        case .openURL:
            guard let url = URL(string: text), let scheme = url.scheme, !scheme.isEmpty else {
                return "Enter a complete URL with a scheme, such as https://example.com."
            }
            if ["file", "javascript", "data"].contains(scheme.lowercased()) {
                return "Use an app URL scheme or a web URL."
            }
            if ["https", "http"].contains(scheme.lowercased()), url.host?.isEmpty != false {
                return "This web URL needs a host name."
            }
        case .agentAction:
            if AgentActionReference(text) == nil { return "Choose a named action from the agent menu." }
        case .shortcut, .none: break
        }
        return nil
    }
}

/// Tracks individual HID elements per device. A held button fires once; the
/// opposite value re-arms it. Debounce also absorbs duplicate USB interfaces.
struct ButtonTrigger {
    private var previous: [String: Int] = [:]
    private var lastFire = -Double.infinity

    mutating func consume(_ event: ButtonSignal, device: String,
                          binding: ButtonSignal?, now: TimeInterval) -> Bool {
        let key = device + ":" + event.source
        let old = previous.updateValue(event.value, forKey: key)
        guard let binding, event.sameElement(as: binding), event.value == binding.value,
              old != event.value, now - lastFire >= 0.35 else { return false }
        lastFire = now
        return true
    }

    mutating func reset() { previous.removeAll(); lastFire = -Double.infinity }
}

/// Logging may be paused without disabling the configured action, and actions
/// may be paused while input logging continues. Learning never dispatches.
struct InputMonitorMode {
    var tracingEnabled = false
    var actionsEnabled = true

    func dispatchesActions(isLearning: Bool) -> Bool { actionsEnabled && !isLearning }
}
