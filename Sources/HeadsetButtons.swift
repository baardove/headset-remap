import Foundation

struct HeadsetButton: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var settings: ButtonSettings

    static let defaults: [(String, String)] = [
        ("mute", "Microphone mute"), ("micArm", "Microphone arm"), ("play", "Play / pause"),
        ("volumeUp", "Volume up"), ("volumeDown", "Volume down"),
        ("call", "Call / answer"), ("assistant", "Voice assistant")
    ]
}

extension ButtonProfile {
    var resolvedButtons: [HeadsetButton] {
        let extra = additionalButtons ?? []
        let known = HeadsetButton.defaults.map { id, name in
            extra.first { $0.id == id } ?? {
                var settings = ButtonSettings()
                if id == "play" { settings.activationCondition = .audioIdle }
                return HeadsetButton(id: id, name: name, settings: settings)
            }()
        }
        return [HeadsetButton(id: "teams", name: "Teams", settings: settings)] + known +
            extra.filter { button in !HeadsetButton.defaults.contains { $0.0 == button.id } }
    }
}

/// Each mapped button tracks its own press/release state and debounce interval.
struct HeadsetButtonRouter {
    private var triggers: [String: ButtonTrigger] = [:]
    mutating func consume(_ signal: ButtonSignal, device: String, buttons: [HeadsetButton], now: TimeInterval) -> [HeadsetButton] {
        var matches: [HeadsetButton] = []
        for button in buttons {
            guard let binding = button.settings.learnedSignals.first(where: { signal.sameElement(as: $0) }) else { continue }
            let key = "\(button.id):\(signal.productID)"
            var trigger = triggers[key] ?? ButtonTrigger()
            if trigger.consume(signal, device: device, binding: binding, now: now) { matches.append(button) }
            triggers[key] = trigger
        }
        return matches
    }
    mutating func reset() { triggers.removeAll() }
}
