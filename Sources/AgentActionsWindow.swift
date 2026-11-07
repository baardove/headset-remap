import Cocoa
import ApplicationServices

final class AgentActionsWindow: NSWindowController, NSTableViewDelegate, NSTableViewDataSource, NSTextFieldDelegate {
    var onBack: (() -> Void)?
    let profileID: UUID
    var onChange: ((ButtonProfileLibrary) -> Void)?
    var onRecording: ((Bool) -> Void)?
    var onTest: ((UUID, AgentSecondaryAction, @escaping (String?) -> Void) -> Void)?
    private var library: ButtonProfileLibrary
    private var selectedID: UUID?
    private var loading = false
    private let table = NSTableView()
    private let editor = NSStackView()
    private let name = NSTextField()
    private let kind = NSPopUpButton()
    private let target = NSTextField()
    private let appKey = ShortcutRecorder()
    private let accessibility = NSButton(title: "Allow keyboard actions…", target: nil, action: nil)
    private let globalKey = ShortcutRecorder()
    private let automatic = NSButton(checkboxWithTitle: "Include when running checked actions", target: nil, action: nil)
    private let first = NSButton(checkboxWithTitle: "Open the agent first", target: nil, action: nil)
    private let delay = NSTextField(string: "0.3")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let save = NSButton(title: "Save action", target: nil, action: nil)
    private var profile: ButtonProfile? { library.profiles.first { $0.id == profileID } }
    private var actions: [AgentSecondaryAction] { profile?.secondaryActions ?? [] }
    private var current: AgentSecondaryAction? { actions.first { $0.id == selectedID } }

    init(library: ButtonProfileLibrary, profileID: UUID) {
        self.library = library; self.profileID = profileID; selectedID = library.profiles.first { $0.id == profileID }?.secondaryActions?.first?.id
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 660), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Headset Remap · Configuration · \(library.profiles.first { $0.id == profileID }?.name ?? "Agent") actions"; window.isReleasedWhenClosed = false
        super.init(window: window); window.center(); build(); loadSelection()
        NotificationCenter.default.addObserver(self, selector: #selector(closing), name: NSWindow.willCloseNotification, object: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }
    func present() { showWindow(nil); NSApp.activate(ignoringOtherApps: true) }
    func update(_ next: ButtonProfileLibrary) {
        let preserve = dirty; library = next
        guard profile != nil else { close(); return }
        if !preserve { loadSelection() }
    }
    private func row(_ views: [NSView]) -> NSStackView { let stack = NSStackView(views: views); stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = 10; return stack }
    private func build() {
        let heading = NSTextField(labelWithString: "Configure \(profile?.name ?? "agent") actions"); heading.font = .systemFont(ofSize: 23, weight: .semibold)
        let help = NSTextField(wrappingLabelWithString: "Select an action to edit it. Check actions and use the arrows to order them. In Agents, choose whether the headset runs one action or all checked actions.")
        help.textColor = .secondaryLabelColor; help.preferredMaxLayoutWidth = 872; help.widthAnchor.constraint(equalToConstant: 872).isActive = true
        let enabled = NSTableColumn(identifier: .init("stack")); enabled.width = 28; enabled.minWidth = 28; enabled.maxWidth = 28
        let column = NSTableColumn(identifier: .init("action")); column.width = 270; table.addTableColumn(enabled); table.addTableColumn(column); table.headerView = nil; table.rowHeight = 38; table.delegate = self; table.dataSource = self
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.widthAnchor.constraint(equalToConstant: 310).isActive = true; scroll.heightAnchor.constraint(equalToConstant: 330).isActive = true
        let add = NSPopUpButton(); add.addItems(withTitles: ["Add action…"] + (profile.flatMap { Bundle(path: $0.settings.target)?.bundleIdentifier } == "com.openai.codex" ? AgentActionPresets.codex.map(\.name) : ["Voice", "New chat"]) + ["Custom action"]); add.target = self; add.action = #selector(addAction(_:))
        add.widthAnchor.constraint(equalToConstant: 134).isActive = true
        let remove = NSButton(title: "Remove", target: self, action: #selector(removeAction))
        remove.widthAnchor.constraint(equalToConstant: 76).isActive = true
        let up = NSButton(title: "↑", target: self, action: #selector(moveUpAction))
        let down = NSButton(title: "↓", target: self, action: #selector(moveDownAction))
        let left = ConfigurationSection("Available actions", views: [scroll, row([up, down]), row([add, remove])])
        name.placeholderString = "Action name"; name.delegate = self
        kind.addItems(withTitles: AgentSecondaryAction.Kind.allCases.map(\.title)); kind.target = self; kind.action = #selector(changed)
        target.placeholderString = "URL or exact macOS Shortcut name"; target.delegate = self
        for recorder in [appKey, globalKey] { recorder.onChange = { [weak self] in self?.refresh() }; recorder.onRecording = { [weak self] value in self?.onRecording?(value) } }
        accessibility.target = self; accessibility.action = #selector(openAccessibility)
        appKey.setAccessibilityLabel("Shortcut inside the agent")
        globalKey.setAccessibilityLabel("Global shortcut for this action")
        automatic.target = self; automatic.action = #selector(changed)
        first.target = self; first.action = #selector(changed)
        delay.delegate = self; delay.widthAnchor.constraint(equalToConstant: 70).isActive = true
        save.target = self; save.action = #selector(saveAction); save.bezelColor = .controlAccentColor
        let test = NSButton(title: "Test action", target: self, action: #selector(testAction))
        let advanced = ConfigurationDisclosure("Advanced action settings", views: [first,
                     row([NSTextField(labelWithString: "Wait after opening (seconds)"), delay]),
                     row([NSTextField(labelWithString: "Global shortcut (optional)"), globalKey])])
        for item in [name as NSView, kind, target, appKey, accessibility, automatic, advanced, row([save, test])] { editor.addArrangedSubview(item) }
        editor.orientation = .vertical; editor.alignment = .leading; editor.spacing = 14; editor.detachesHiddenViews = true
        for view in [name as NSView, kind, target] { view.widthAnchor.constraint(equalToConstant: 538).isActive = true }
        let right = ConfigurationSection("Action settings", views: [editor])
        let body = row([left, right]); body.alignment = .top; body.spacing = 24
        status.preferredMaxLayoutWidth = 872; status.widthAnchor.constraint(equalToConstant: 872).isActive = true; status.font = .systemFont(ofSize: 12)
        let navigation = ConfigurationNavigation(section: "\(profile?.name ?? "Agent") actions", backTitle: "Agents & actions", onBack: { [weak self] in self?.onBack?() })
        let root = NSStackView(views: [navigation, heading, help, body, status]); root.orientation = .vertical; root.alignment = .leading; root.spacing = 16; root.translatesAutoresizingMaskIntoConstraints = false
        window!.contentView!.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: window!.contentView!.leadingAnchor, constant: 24), root.topAnchor.constraint(equalTo: window!.contentView!.topAnchor, constant: 24)])
    }
    func numberOfRows(in tableView: NSTableView) -> Int { actions.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let action = actions[row]
        if tableColumn?.identifier.rawValue == "stack" {
            let toggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleStack(_:)))
            toggle.tag = row; toggle.state = action.runAfterHeadset != false ? .on : .off; toggle.isEnabled = action.isConfigured
            toggle.setAccessibilityLabel("Include \(action.name) in checked actions")
            return toggle
        }
        let label = NSTextField(labelWithString: action.name + (action.isConfigured ? "" : " · needs setup"))
        label.font = .systemFont(ofSize: 12); label.lineBreakMode = .byTruncatingTail; label.toolTip = action.name
        let cell = NSTableCellView()
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }
    @objc private func toggleStack(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        let id = actions[sender.tag].id; let enabled = sender.state == .on
        guard prepareForExternalEdit(), var action = actions.first(where: { $0.id == id }) else { loadSelection(); return }
        action.runAfterHeadset = enabled
        do {
            var next = library; try next.updateSecondaryAction(action, in: profileID)
            try next.setAutomaticActionSelection(nil, for: profileID); try next.save()
            library = next; onChange?(next); loadSelection()
        } catch { status.stringValue = error.localizedDescription; loadSelection() }
    }
    private func read() -> AgentSecondaryAction? {
        guard var action = current else { return nil }
        action.name = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        action.kind = AgentSecondaryAction.Kind.allCases[kind.indexOfSelectedItem]
        action.target = target.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        action.key = appKey.shortcut; action.hotkey = globalKey.shortcut; action.openAgentFirst = first.state == .on; action.runAfterHeadset = automatic.state == .on
        action.delay = Double(delay.stringValue) ?? .nan
        return action
    }
    private var dirty: Bool { !loading && read() != current }
    private func loadSelection() {
        loading = true
        if !actions.contains(where: { $0.id == selectedID }) { selectedID = actions.first?.id }
        table.reloadData(); editor.isHidden = current == nil
        if let action = current {
            name.stringValue = action.name; kind.selectItem(at: AgentSecondaryAction.Kind.allCases.firstIndex(of: action.kind)!)
            target.stringValue = action.target; appKey.shortcut = action.key; globalKey.shortcut = action.hotkey
            automatic.state = action.runAfterHeadset != false ? .on : .off
            first.state = action.openAgentFirst ? .on : .off; delay.stringValue = String(action.delay)
            table.selectRowIndexes(IndexSet(integer: actions.firstIndex { $0.id == action.id }!), byExtendingSelection: false)
        }
        loading = false; refresh()
    }
    private func refresh() {
        guard let draft = read() else { status.stringValue = "Add an action to configure it."; return }
        appKey.isHidden = draft.kind != .keyboard; target.isHidden = draft.kind == .keyboard
        accessibility.isHidden = draft.kind != .keyboard || AXIsProcessTrusted()
        save.isEnabled = dirty
        status.stringValue = draft.validationError ?? ""
    }
    @objc private func changed() { if !loading { refresh() } }
    func controlTextDidChange(_ obj: Notification) { refresh() }
    func prepareForExternalEdit() -> Bool {
        appKey.stopRecording(); globalKey.stopRecording()
        guard dirty else { return true }
        let alert = NSAlert(); alert.messageText = "Save changes to this action?"; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Discard"); alert.addButton(withTitle: "Cancel")
        switch alert.runModal() { case .alertFirstButtonReturn: return commit(); case .alertSecondButtonReturn: loadSelection(); return true; default: return false }
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !loading, actions.indices.contains(table.selectedRow) else { return }
        let id = actions[table.selectedRow].id
        guard id != selectedID else { return }
        guard prepareForExternalEdit() else { loadSelection(); return }
        selectedID = id; loadSelection()
    }
    @discardableResult private func commit() -> Bool {
        guard let action = read() else { return false }
        if let error = action.validationError { status.stringValue = error; return false }
        do { var next = library; try next.updateSecondaryAction(action, in: profileID); try next.save(); library = next; onChange?(next); loadSelection(); status.stringValue = "Saved."; return true }
        catch { status.stringValue = error.localizedDescription; return false }
    }
    private func moveAction(_ offset: Int) {
        guard let selectedID, prepareForExternalEdit() else { return }
        do { var next = library; try next.moveSecondaryAction(selectedID, offset: offset, in: profileID); try next.save(); library = next; onChange?(next); loadSelection() }
        catch { status.stringValue = error.localizedDescription }
    }
    @objc private func moveUpAction() { moveAction(-1) }
    @objc private func moveDownAction() { moveAction(1) }
    @objc private func saveAction() { _ = commit() }
    @objc private func addAction(_ sender: NSPopUpButton) {
        let choice = sender.titleOfSelectedItem ?? ""; sender.selectItem(at: 0)
        guard choice != "Add action…", prepareForExternalEdit() else { return }
        var label = choice; var suffix = 2
        while actions.contains(where: { $0.name.caseInsensitiveCompare(label) == .orderedSame }) { label = "\(choice) \(suffix)"; suffix += 1 }
        var action = AgentSecondaryAction(name: label)
        action.runAfterHeadset = false
        if let preset = AgentActionPresets.codex.first(where: { $0.name == choice }), profile.flatMap({ Bundle(path: $0.settings.target)?.bundleIdentifier }) == "com.openai.codex" {
            action.presetID = preset.id; action.key = KeyboardShortcut(keyCode: preset.key, modifiers: preset.modifiers)
            action.sendGlobally = preset.id == "voice.start"
        }
        do { var next = library; try next.updateSecondaryAction(action, in: profileID); try next.save(); selectedID = action.id; library = next; onChange?(next); loadSelection() }
        catch { status.stringValue = error.localizedDescription }
    }
    @objc private func removeAction() {
        guard let current, prepareForExternalEdit() else { return }
        let alert = NSAlert(); alert.messageText = "Remove \(current.name)?"; alert.addButton(withTitle: "Remove"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { var next = library; try next.removeSecondaryAction(current.id, in: profileID); try next.save(); selectedID = nil; library = next; onChange?(next); loadSelection() }
        catch { status.stringValue = error.localizedDescription }
    }
    @objc private func testAction() {
        guard let draft = read() else { return }
        if let error = draft.validationError { status.stringValue = error; return }
        onTest?(profileID, draft) { [weak self] error in self?.status.stringValue = error ?? "Action completed." }
    }
    @objc private func openAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    @objc private func closing() { appKey.stopRecording(); globalKey.stopRecording() }
}
