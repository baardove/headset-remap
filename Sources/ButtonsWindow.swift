import Cocoa
import UniformTypeIdentifiers

private final class ButtonsDocument: NSView { override var isFlipped: Bool { true } }

final class ButtonsWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    var onBack: (() -> Void)?
    var onChange: ((ButtonProfileLibrary) -> Void)?
    var onLearningChanged: ((Bool) -> Void)?
    var audioStatusProvider: (() -> String)?
    var onDebug: (() -> Void)?
    private var library: ButtonProfileLibrary
    private var profileID: UUID
    private var selectedID = "teams"
    private var draft: HeadsetButton!
    private var loading = false
    private var learning = false
    private var timer: Timer?
    private var agentChoices: [(String, ButtonSettings)] = []
    private let selectedAgentAction = NSTextField(labelWithString: "")
    private var signals: [ButtonSignal] = []
    private let root = NSStackView()
    private let outerScroll = NSScrollView()
    private let contentDocument = ButtonsDocument()
    private let profiles = NSPopUpButton()
    private let table = NSTableView()
    private let name = NSTextField()
    private let action = NSPopUpButton()
    private let presets = NSPopUpButton()
    private let target = NSTextField()
    private let condition = NSPopUpButton()
    private let audioStatus = NSTextField(labelWithString: "")
    private var audioTimer: Timer?
    private let timing = NSPopUpButton()
    private let learn = NSButton(title: "Learn input", target: nil, action: nil)
    private let inputState = NSTextField(labelWithString: "")
    private let inputHelp = NSTextField(wrappingLabelWithString: "Raise and lower the arm to learn its input. If it shares the mute button’s signal, configure only one of them.")
    private let signalPicker = NSPopUpButton()
    private let savedInputs = NSPopUpButton()
    private let removeInput = NSButton(title: "Remove input", target: nil, action: nil)
    private let details = NSTextField(wrappingLabelWithString: "")
    private let save = NSButton(title: "Save button", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private var chooseAppButton: NSButton!
    private let remove = NSButton(title: "Remove custom", target: nil, action: nil)
    private var currentProfile: ButtonProfile { library.profiles.first { $0.id == profileID } ?? library.active }
    private var buttons: [HeadsetButton] { currentProfile.resolvedButtons }

    init(library: ButtonProfileLibrary) {
        self.library = library; profileID = library.activeID
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 655), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Headset Remap · Configuration · Headset buttons"; window.isReleasedWhenClosed = false
        super.init(window: window); window.center(); build(); loadSelection()
        NotificationCenter.default.addObserver(self, selector: #selector(closing), name: NSWindow.willCloseNotification, object: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { timer?.invalidate(); audioTimer?.invalidate(); NotificationCenter.default.removeObserver(self) }
    func present() {
        showWindow(nil); NSApp.activate(ignoringOtherApps: true)
        audioStatus.stringValue = audioStatusProvider?() ?? "Checking headset audio…"
        if audioTimer == nil { audioTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.audioStatus.stringValue = self?.audioStatusProvider?() ?? "" } }
    }
    func update(_ next: ButtonProfileLibrary) {
        let dirty = hasChanges
        library = next
        if !library.profiles.contains(where: { $0.id == profileID }) { profileID = library.activeID; selectedID = "teams" }
        updateProfiles()
        table.reloadData()
        if !dirty { loadSelection() }
    }
    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views); stack.orientation = .horizontal; stack.spacing = 10; stack.alignment = .centerY
        return stack
    }
    private func build() {
        let heading = NSTextField(labelWithString: "Headset buttons"); heading.font = .systemFont(ofSize: 24, weight: .semibold)
        let explanation = NSTextField(wrappingLabelWithString: "Keep the headset’s built-in behavior and add your own action to each detectable button. Learn the button once on each headset or adapter; existing inputs are kept.")
        explanation.textColor = .secondaryLabelColor
        profiles.widthAnchor.constraint(equalToConstant: 170).isActive = true
        profiles.target = self; profiles.action = #selector(profileSelected)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("button")); column.title = "Headset buttons"; column.width = 225
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 49; table.delegate = self; table.dataSource = self
        table.target = self; table.action = #selector(buttonSelected)
        let list = NSScrollView(); list.documentView = table; list.hasVerticalScroller = true; list.borderType = .bezelBorder
        list.widthAnchor.constraint(equalToConstant: 235).isActive = true; list.heightAnchor.constraint(equalToConstant: 376).isActive = true
        let add = NSButton(title: "Add custom…", target: self, action: #selector(addCustom))
        remove.target = self; remove.action = #selector(removeCustom)
        let left = ConfigurationSection("Physical buttons", views: [list, row([add, remove])])
        name.font = .systemFont(ofSize: 19, weight: .semibold); name.delegate = self
        learn.target = self; learn.action = #selector(toggleLearning)
        removeInput.target = self; removeInput.action = #selector(clearInput)
        savedInputs.setAccessibilityLabel("Learned headsets and adapters")
        savedInputs.widthAnchor.constraint(equalToConstant: 420).isActive = true
        inputState.textColor = .secondaryLabelColor
        inputHelp.textColor = .secondaryLabelColor; inputHelp.font = .systemFont(ofSize: 12); inputHelp.preferredMaxLayoutWidth = 575
        signalPicker.target = self; signalPicker.action = #selector(signalSelected); signalPicker.isHidden = true
        signalPicker.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        action.addItems(withTitles: ButtonAction.allCases.map { $0 == .none ? "No extra action" : $0.title })
        action.target = self; action.action = #selector(formChanged)
        presets.addItem(withTitle: "Choose agent…")
        presets.target = self; presets.action = #selector(presetSelected)
        target.placeholderString = "App path, URL or Shortcut name"; target.delegate = self
        let choose = NSButton(title: "Choose app…", target: self, action: #selector(chooseApp))
        chooseAppButton = choose
        timing.addItems(withTitles: AgentFocusTiming.allCases.map(\.title)); timing.target = self; timing.action = #selector(formChanged)
        condition.addItems(withTitles: ButtonActivationCondition.allCases.map(\.title)); condition.target = self; condition.action = #selector(formChanged)
        audioStatus.textColor = .secondaryLabelColor; audioStatus.font = .systemFont(ofSize: 12)
        details.font = .monospacedSystemFont(ofSize: 10, weight: .regular); details.textColor = .secondaryLabelColor
        save.target = self; save.action = #selector(saveAction); save.bezelColor = .controlAccentColor
        let test = NSButton(title: "Test action", target: self, action: #selector(testAction))
        let advanced = ConfigurationDisclosure("Advanced button options", views: [
            row([NSTextField(labelWithString: "Timing"), timing]), condition, audioStatus])
        advanced.onToggle = { [weak self] in self?.refresh() }
        let right = ConfigurationSection("Button configuration", views: [name, inputState, inputHelp, row([savedInputs, removeInput]), learn, signalPicker,
            NSTextField(labelWithString: "Additional action"), row([action, presets]), selectedAgentAction, target, choose,
            advanced, row([save, test])])
        right.detachesHiddenViews = true
        right.widthAnchor.constraint(equalToConstant: 575).isActive = true
        for field in [name, target, signalPicker, details] { field.widthAnchor.constraint(equalToConstant: 575).isActive = true }
        details.preferredMaxLayoutWidth = 575
        let body = row([left, right]); body.alignment = .top; body.spacing = 24
        let foot = NSTextField(wrappingLabelWithString: "Some controls work inside the headset and never reach the USB adapter. If learning shows nothing, inspect Debug Input. Original responses are not suppressed. Audio rules use playback activity, not the physical power state; idle requires two quiet seconds.")
        foot.textColor = .secondaryLabelColor; foot.font = .systemFont(ofSize: 12)
        status.font = .systemFont(ofSize: 12)
        status.preferredMaxLayoutWidth = 620
        status.widthAnchor.constraint(lessThanOrEqualToConstant: 620).isActive = true
        let debug = NSButton(title: "Debug Input…", target: self, action: #selector(openDebug))
        let diagnostics = ConfigurationDisclosure("Diagnostics", views: [foot, details, debug])
        diagnostics.onToggle = { [weak self] in self?.refresh() }
        let navigation = ConfigurationNavigation(section: "Headset buttons", onBack: { [weak self] in self?.onBack?() })
        for item in [navigation, row([heading, NSTextField(labelWithString: "For agent"), profiles]), explanation, body, diagnostics, status] { root.addArrangedSubview(item) }
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 16; root.translatesAutoresizingMaskIntoConstraints = false
        outerScroll.frame = window!.contentView!.bounds; outerScroll.autoresizingMask = [.width, .height]
        outerScroll.hasVerticalScroller = true; outerScroll.scrollerStyle = .overlay; outerScroll.drawsBackground = false
        contentDocument.frame = NSRect(x: 0, y: 0, width: 900, height: 655)
        outerScroll.documentView = contentDocument
        window!.contentView!.addSubview(outerScroll); contentDocument.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: contentDocument.leadingAnchor, constant: 24), root.trailingAnchor.constraint(equalTo: contentDocument.trailingAnchor, constant: -24), root.topAnchor.constraint(equalTo: contentDocument.topAnchor, constant: 24)])
        for label in [explanation, foot] { label.widthAnchor.constraint(equalToConstant: 852).isActive = true; label.preferredMaxLayoutWidth = 852 }
        diagnostics.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        updateProfiles()
    }
    private func updateProfiles() {
        profiles.removeAllItems(); profiles.addItems(withTitles: library.profiles.map { library.displayName($0) })
        agentChoices = []
        for profile in library.enabledProfiles {
            agentChoices.append(("\(profile.name) · Open", profile.settings))
            for action in profile.secondaryActions ?? [] where action.isConfigured {
                let reference = AgentActionReference(profileID: profile.id, actionID: action.id)
                agentChoices.append(("\(profile.name) · \(action.name)", ButtonSettings(action: .agentAction, target: reference.encoded)))
            }
        }
        presets.removeAllItems(); presets.addItem(withTitle: "Choose agent…"); presets.addItems(withTitles: agentChoices.map { $0.0 })
        profiles.selectItem(at: library.profiles.firstIndex { $0.id == profileID } ?? 0)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { buttons.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let button = buttons[row]
        let title = NSTextField(labelWithString: button.name); title.font = .systemFont(ofSize: 13, weight: .medium)
        let description: String
        if button.settings.signal == nil { description = "Input not learned" }
        else if button.settings.action == .none { description = "Learned · no extra action" }
        else { description = "Learned · \(button.settings.action == .openApp ? (Bundle(path: button.settings.target)?.bundleIdentifier == "com.openai.codex" ? "Codex" : URL(fileURLWithPath: button.settings.target).deletingPathExtension().lastPathComponent) : button.settings.action.title)" }
        let subtitle = NSTextField(labelWithString: description); subtitle.font = .systemFont(ofSize: 10); subtitle.textColor = .secondaryLabelColor
        let cell = NSStackView(views: [title, subtitle]); cell.orientation = .vertical; cell.alignment = .leading; cell.spacing = 3
        return cell
    }
    private func loadSelection() {
        loading = true
        draft = buttons.first { $0.id == selectedID } ?? buttons[0]; selectedID = draft.id
        let fixed = currentProfile.builtInSiri == true && selectedID == "teams"
        for control in [action as NSControl, presets, target, chooseAppButton!] { control.isEnabled = !fixed }
        name.stringValue = draft.name; name.isEditable = selectedID.hasPrefix("custom-")
        name.isBezeled = name.isEditable; name.drawsBackground = name.isEditable
        action.selectItem(at: ButtonAction.allCases.firstIndex(of: draft.settings.action)!)
        target.stringValue = draft.settings.target
        condition.selectItem(at: ButtonActivationCondition.allCases.firstIndex(of: draft.settings.activationCondition ?? .always)!)
        timing.selectItem(at: AgentFocusTiming.allCases.firstIndex(of: draft.settings.effectiveFocusTiming)!)
        signals = []; signalPicker.isHidden = true
        table.reloadData(); table.selectRowIndexes(IndexSet(integer: buttons.firstIndex { $0.id == selectedID }!), byExtendingSelection: false)
        remove.isEnabled = selectedID.hasPrefix("custom-")
        loading = false; refresh()
    }
    private func readDraft() -> HeadsetButton {
        var result = draft!
        result.name = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        result.settings.action = ButtonAction.allCases[action.indexOfSelectedItem]
        if result.settings.action != .agentAction { result.settings.target = target.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
        let chosenCondition = ButtonActivationCondition.allCases[condition.indexOfSelectedItem]
        if chosenCondition != (result.settings.activationCondition ?? .always) { result.settings.activationCondition = chosenCondition }
        let chosen = AgentFocusTiming.allCases[timing.indexOfSelectedItem]
        if chosen != result.settings.effectiveFocusTiming { result.settings.focusTiming = chosen }
        return result
    }
    private var hasChanges: Bool { draft != nil && readDraft() != buttons.first { $0.id == selectedID } }
    private func refresh() {
        inputHelp.isHidden = selectedID != "micArm"
        let learned = draft.settings.learnedSignals
        inputState.stringValue = learned.isEmpty ? "Input not learned" : "Learned for \(learned.count) headset / adapter\(learned.count == 1 ? "" : "s")"
        let selectedInput = savedInputs.selectedItem?.representedObject as? String
        savedInputs.removeAllItems()
        for input in learned {
            savedInputs.addItem(withTitle: input.deviceLabel)
            savedInputs.lastItem?.representedObject = input.bindingID
        }
        if let selectedInput, let index = learned.firstIndex(where: { $0.bindingID == selectedInput }) { savedInputs.selectItem(at: index) }
        if learned.isEmpty { savedInputs.addItem(withTitle: "No input learned") }
        savedInputs.isEnabled = !learned.isEmpty && !learning
        removeInput.isEnabled = !learned.isEmpty && !learning
        if !learning { learn.title = learned.isEmpty ? "Learn input" : "Learn another headset" }
        details.stringValue = learned.isEmpty ? "Press Learn input, then press and release this button only." : learned.map { "\($0.deviceLabel): \($0.label)" }.joined(separator: "\n")
        let reference = readDraft().settings.action == .agentAction
        target.isHidden = reference; selectedAgentAction.isHidden = !reference
        selectedAgentAction.stringValue = agentChoices.first(where: { $0.1.action == .agentAction && $0.1.target == draft.settings.target })?.0 ?? "Choose an agent action from the menu."
        save.isEnabled = hasChanges && !learning
        contentDocument.layoutSubtreeIfNeeded()
        let height = root.fittingSize.height + 48
        let maximum = (window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 1000
        let visibleHeight = min(height, maximum - 100)
        window?.setContentSize(NSSize(width: 900, height: visibleHeight))
        contentDocument.setFrameSize(NSSize(width: 900, height: height))
    }
    @objc private func formChanged() { if !loading { refresh() } }
    func controlTextDidChange(_ obj: Notification) { refresh() }
    func prepareForExternalEdit() -> Bool { canLeave() }
    private func canLeave() -> Bool {
        if learning { cancelLearning() }
        guard hasChanges else { return true }
        let alert = NSAlert(); alert.messageText = "Save the extra action for \(draft.name)?"
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Discard"); alert.addButton(withTitle: "Cancel")
        switch alert.runModal() { case .alertFirstButtonReturn: return commitDraft(); case .alertSecondButtonReturn: loadSelection(); return true; default: return false }
    }
    func tableViewSelectionDidChange(_ notification: Notification) { if !loading { buttonSelected() } }
    @objc private func buttonSelected() {
        guard !loading, buttons.indices.contains(table.selectedRow) else { return }
        let id = buttons[table.selectedRow].id
        guard id != selectedID else { return }
        guard canLeave() else { table.selectRowIndexes(IndexSet(integer: buttons.firstIndex { $0.id == selectedID }!), byExtendingSelection: false); return }
        selectedID = id; loadSelection(); status.stringValue = ""
    }
    @objc private func profileSelected() {
        let id = library.profiles[profiles.indexOfSelectedItem].id
        guard canLeave() else { updateProfiles(); return }
        profileID = id; selectedID = "teams"; loadSelection(); status.stringValue = ""
    }
    @discardableResult private func commitDraft() -> Bool {
        let button = readDraft()
        if let error = button.settings.validationError { status.stringValue = error; return false }
        do {
            var next = library; try next.updateButton(button, in: profileID); try next.save()
            library = next; draft = button; onChange?(next); loadSelection()
            status.stringValue = button.settings.signal == nil && button.settings.action != .none ? "Saved. Learn the input to trigger it from the headset." : "Saved \(button.name)."
            return true
        } catch { status.stringValue = error.localizedDescription; return false }
    }
    @objc private func saveAction() { _ = commitDraft() }
    @objc private func clearInput() {
        cancelLearning()
        guard draft.settings.learnedSignals.indices.contains(savedInputs.indexOfSelectedItem) else { return }
        draft.settings.removeInput(draft.settings.learnedSignals[savedInputs.indexOfSelectedItem])
        refresh()
    }
    @objc private func toggleLearning() {
        if learning { cancelLearning(); return }
        learning = true; signals = []; signalPicker.removeAllItems(); signalPicker.isHidden = false
        signalPicker.addItem(withTitle: "Waiting for input…"); learn.title = "Stop learning"; onLearningChanged?(true)
        status.stringValue = "Press and release only \(draft.name). Learning stops in 15 seconds."
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in self?.cancelLearning() }
        refresh()
    }
    func receive(_ signal: ButtonSignal) {
        guard learning, !signals.contains(signal), signals.count < 100 else { return }
        if signals.isEmpty { signalPicker.removeAllItems() }
        signals.append(signal); signalPicker.addItem(withTitle: signal.label)
    }
    func cancelLearning() {
        guard learning else { return }
        learning = false; timer?.invalidate(); timer = nil; learn.title = "Learn input"; onLearningChanged?(false)
        if let index = signals.firstIndex(where: { $0.value != 0 }) ?? signals.indices.first {
            signalPicker.selectItem(at: index); signalSelected()
            status.stringValue = "Captured. Choose the press event, then save."
        } else { status.stringValue = "No input detected. Open Debug Input to investigate."; signalPicker.isHidden = true }
        refresh()
    }
    @objc private func signalSelected() {
        guard !learning, signals.indices.contains(signalPicker.indexOfSelectedItem) else { return }
        draft.settings.learnInput(signals[signalPicker.indexOfSelectedItem]); refresh()
    }
    @objc private func presetSelected() {
        let index = presets.indexOfSelectedItem - 1; presets.selectItem(at: 0)
        guard agentChoices.indices.contains(index) else { return }
        let choice = agentChoices[index].1
        draft.settings.action = choice.action; draft.settings.target = choice.target
        action.selectItem(at: ButtonAction.allCases.firstIndex(of: choice.action)!); target.stringValue = choice.target; refresh()
    }
    @objc private func chooseApp() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        action.selectItem(at: 0); target.stringValue = url.path; refresh()
    }
    @objc private func testAction() {
        guard !learning else { return }
        guard readDraft().settings.action != .none else { status.stringValue = "No additional action assigned."; return }
        ButtonActionExecutor.run(readDraft().settings) { [weak self] error in self?.status.stringValue = error ?? "Action opened." }
    }
    @objc private func addCustom() {
        guard canLeave() else { return }
        let button = HeadsetButton(id: "custom-" + UUID().uuidString, name: "Custom button", settings: ButtonSettings())
        do { var next = library; try next.updateButton(button, in: profileID); try next.save(); library = next; selectedID = button.id; draft = nil; onChange?(next); loadSelection(); window?.makeFirstResponder(name) }
        catch { status.stringValue = error.localizedDescription }
    }
    @objc private func removeCustom() {
        guard selectedID.hasPrefix("custom-"), canLeave() else { return }
        do { var next = library; try next.removeCustomButton(selectedID, in: profileID); try next.save(); library = next; selectedID = "teams"; draft = nil; onChange?(next); loadSelection() }
        catch { status.stringValue = error.localizedDescription }
    }
    @objc private func openDebug() { onDebug?() }
    @objc private func closing() { cancelLearning(); audioTimer?.invalidate(); audioTimer = nil; loadSelection() }
}
