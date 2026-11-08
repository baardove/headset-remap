import Foundation

struct HeadsetPhysicalControl {
    let name: String
    let ids: [String]
    let terms: [String]
    let side: String
}

extension HeadsetDiagramModel {
    /// Left controls top-to-bottom, then right controls top-to-bottom.
    /// Shared functions deliberately retain one physical-control number.
    var controls: [HeadsetPhysicalControl] {
        func c(_ name: String, _ ids: [String], _ terms: [String], _ side: String = "Right") -> HeadsetPhysicalControl {
            HeadsetPhysicalControl(name: name, ids: ids, terms: terms, side: side)
        }
        let power = c("Power / Bluetooth", ["power"], ["Power on", "Power On", "Power off"], "Left")
        let anc = c("ANC / HearThrough", ["anc"], ["Cycle between", "ANC/HearThrough", "HearThrough/ANC", "ANC on/o"], "Left")
        let up = c("Volume up", ["volumeUp"], ["Volume up"])
        let down = c("Volume down", ["volumeDown"], ["Volume down"])
        let play = c("Play / pause", ["play"], ["Play/Pause", "Play/pause", "Play or Pause"])
        let call = c("Teams / call", ["teams", "call"], ["Answer/end call", "Answer/End call", "Answer or end call"])
        let mute = c("Mute / voice assistant", ["mute", "assistant"], ["Mute/unmute", "Mute/Unmute", "Voice Assistant", "Voice assistant", "Mute microphone"])
        switch self {
        case .evolve230, .evolve230SE, .evolve240, .evolve240SE:
            return [play, up, c("Microphone mute", ["mute"], ["Mute/Unmute", "Mute microphone"]), down, call]
        case .evolve250, .evolve255:
            return [c(self == .evolve255 ? "ANC / voice assistant" : "ANC", self == .evolve255 ? ["anc", "assistant"] : ["anc"], ["ANC on/o"]), up,
                    c("Play / pause / mute", ["play", "mute"], ["Play/pause music"]), call, down,
                    c("Power / Bluetooth", ["power"], ["Power on/off", "Bluetooth pairing"])]
        case .evolve2:
            return [up, mute, play, down, call, c("Power / Bluetooth", ["power"], ["Power On/Off", "Power On", "Power on"], "Right")]
        case .evolve265Flex: return [anc, power, mute, up, play, down, call]
        case .evolve275, .evolve285: return [anc, power, up, play, call, down, mute]
        case .evolve2Buds:
            return [c("Left earbud", ["leftBud"], ["Left button"], "Left"), c("Right earbud", ["rightBud"], ["Right button"])]
        case .evolve345, .evolve365:
            return [c("Call / play / pause", ["call", "play"], ["Call and music controls"]), up, down, mute,
                    c("ANC / HearThrough", ["anc"], ["Cycle between"]), c("Teams", ["teams"], ["Microsoft Teams"]),
                    c("Power / Bluetooth", ["power"], ["Power on/off"])]
        case .evolve365Flex:
            return [anc, power, mute, up, c("Call / play / pause", ["call", "play"], ["Call and music"]), down,
                    c("Teams", ["teams"], ["Microsoft Teams"])]
        case .evolve3:
            return [anc, power, mute, up, c("Call / play / pause", ["call", "play"], ["Call and music"]),
                    c("Teams", ["teams"], ["Microsoft Teams"]), down]
        case .evolve385:
            return [anc, power, mute, c("Teams", ["teams"], ["Microsoft Teams"]), up,
                    c("Call / play / pause", ["call", "play"], ["Call and music"]), down]
        }
    }
    func number(for id: String) -> Int? { controls.firstIndex { $0.ids.contains(id) }.map { $0 + 1 } }
    func ordered(_ buttons: [HeadsetButton]) -> [HeadsetButton] {
        buttons.enumerated().filter { number(for: $0.element.id) != nil || ($0.element.id == "micArm" && hasBoom) || $0.element.id.hasPrefix("custom-") }
            .sorted {
                let l = number(for: $0.element.id) ?? 99, r = number(for: $1.element.id) ?? 99
                return l == r ? $0.offset < $1.offset : l < r
            }.map(\.element)
    }
}
