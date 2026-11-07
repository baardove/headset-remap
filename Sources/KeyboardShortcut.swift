import Foundation

/// Stored independently of AppKit/Carbon so profiles can be validated and tested without a GUI.
struct KeyboardShortcut: Codable, Hashable {
    static let command: UInt32 = 1
    static let option: UInt32 = 2
    static let control: UInt32 = 4
    static let shift: UInt32 = 8
    let keyCode: UInt32
    let modifiers: UInt32

    var isValid: Bool {
        modifiers & ~15 == 0 && modifiers & 7 != 0 && Self.keyNames[keyCode] != nil
    }
    var label: String {
        (modifiers & Self.control != 0 ? "⌃" : "") +
        (modifiers & Self.option != 0 ? "⌥" : "") +
        (modifiers & Self.shift != 0 ? "⇧" : "") +
        (modifiers & Self.command != 0 ? "⌘" : "") + (Self.keyNames[keyCode] ?? "?")
    }
    static let keyNames: [UInt32: String] = [
        0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",
        12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",
        24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",
        36:"↩",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",
        48:"⇥",49:"Space",50:"`",51:"⌫",65:"Keypad .",67:"Keypad *",69:"Keypad +",71:"Clear",
        75:"Keypad /",76:"Keypad ↩",78:"Keypad −",81:"Keypad =",82:"Keypad 0",83:"Keypad 1",
        84:"Keypad 2",85:"Keypad 3",86:"Keypad 4",87:"Keypad 5",88:"Keypad 6",89:"Keypad 7",91:"Keypad 8",92:"Keypad 9",
        96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",105:"F13",106:"F16",107:"F14",
        109:"F10",111:"F12",113:"F15",114:"Help",115:"Home",116:"Page Up",117:"⌦",118:"F4",119:"End",
        120:"F2",121:"Page Down",122:"F1",123:"←",124:"→",125:"↓",126:"↑"
    ]
}

struct ProfileHotkey: Equatable {
    enum Purpose: String { case activate, run, previous, next, secondary }
    let profileID: UUID
    let purpose: Purpose
    let shortcut: KeyboardShortcut
    var secondaryActionID: UUID?
}

struct AgentCycleShortcuts: Codable, Equatable {
    var previous: KeyboardShortcut?
    var next: KeyboardShortcut?
    static let defaults = Self(previous: KeyboardShortcut(keyCode: 123, modifiers: 6), next: KeyboardShortcut(keyCode: 124, modifiers: 6))
    static let identity = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}
