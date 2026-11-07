import Cocoa
import Carbon

/// Registers only the configured key combinations. Does not monitor typing or need Accessibility.
final class GlobalHotkeys {
    private var handler: EventHandlerRef?
    private var registrations: [EventHotKeyRef] = []
    private var bindings: [UInt32: ProfileHotkey] = [:]
    private var configured: [ProfileHotkey]?
    private var lastFailures: [String] = []
    private var pressed: Set<UInt32> = []
    var onTrigger: ((ProfileHotkey) -> Void)?
    private static let signature: OSType = 0x4A42524D // JBRM

    init() {
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalHotkeys>.fromOpaque(context).takeUnretainedValue()
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == GlobalHotkeys.signature,
                  let binding = owner.bindings[identifier.id] else { return OSStatus(eventNotHandledErr) }
            if GetEventKind(event) == UInt32(kEventHotKeyReleased) { owner.pressed.remove(identifier.id) }
            else if owner.pressed.insert(identifier.id).inserted { owner.onTrigger?(binding) }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    deinit { clear(); if let handler { RemoveEventHandler(handler) } }
    func clear() {
        registrations.forEach { UnregisterEventHotKey($0) }
        registrations.removeAll(); bindings.removeAll(); pressed.removeAll(); configured = nil
    }
    @discardableResult func configure(_ library: ButtonProfileLibrary) -> [String] {
        if configured == library.hotkeys { return lastFailures }
        clear()
        configured = library.hotkeys
        guard handler != nil else { return ["Global keyboard shortcuts could not start."] }
        var failures: [String] = []
        for (index, binding) in library.hotkeys.enumerated() {
            let shortcut = binding.shortcut
            var flags: UInt32 = 0
            if shortcut.modifiers & KeyboardShortcut.command != 0 { flags |= UInt32(cmdKey) }
            if shortcut.modifiers & KeyboardShortcut.option != 0 { flags |= UInt32(optionKey) }
            if shortcut.modifiers & KeyboardShortcut.control != 0 { flags |= UInt32(controlKey) }
            if shortcut.modifiers & KeyboardShortcut.shift != 0 { flags |= UInt32(shiftKey) }
            let identifier = UInt32(index + 1)
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(shortcut.keyCode, flags, EventHotKeyID(signature: Self.signature, id: identifier),
                                             GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
            if result == noErr, let reference {
                registrations.append(reference); bindings[identifier] = binding
            } else {
                let name = library.profiles.first { $0.id == binding.profileID }?.name ?? (binding.purpose == .previous ? "Previous agent" : "Next agent")
                failures.append("\(name) \(shortcut.label) is unavailable (macOS error \(result)). Choose another combination.")
            }
        }
        lastFailures = failures
        return failures
    }
}

final class ShortcutRecorder: NSButton {
    var shortcut: KeyboardShortcut? { didSet { if !recording { updateTitle() } } }
    var onChange: (() -> Void)?
    var onRecording: ((Bool) -> Void)?
    private var recording = false
    override var acceptsFirstResponder: Bool { true }
    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded; target = self; action = #selector(beginRecording)
        toolTip = "Click, then press a combination with Control, Option or Command. Escape cancels; Delete clears."
        updateTitle()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func beginRecording() {
        guard !recording else { return }
        recording = true; onRecording?(true); title = "Press shortcut…"
        window?.makeFirstResponder(self)
    }
    private func updateTitle() { title = shortcut?.label ?? "Record shortcut…" }
    func stopRecording() {
        guard recording else { return }
        recording = false; updateTitle(); onRecording?(false)
    }
    override func resignFirstResponder() -> Bool { stopRecording(); return super.resignFirstResponder() }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { stopRecording(); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if [UInt16(51), UInt16(117)].contains(event.keyCode), flags.intersection([.command, .option, .control, .shift]).isEmpty {
            shortcut = nil; stopRecording(); onChange?(); return
        }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= KeyboardShortcut.command }
        if flags.contains(.option) { modifiers |= KeyboardShortcut.option }
        if flags.contains(.control) { modifiers |= KeyboardShortcut.control }
        if flags.contains(.shift) { modifiers |= KeyboardShortcut.shift }
        let candidate = KeyboardShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        guard candidate.isValid else { title = "Include ⌃, ⌥ or ⌘"; return }
        shortcut = candidate; stopRecording(); onChange?()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording { keyDown(with: event); return true }
        return super.performKeyEquivalent(with: event)
    }
}
