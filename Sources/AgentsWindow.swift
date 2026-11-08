import Cocoa
import UniformTypeIdentifiers

final class AgentsWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    var onBack: (() -> Void)?
    var onActions: ((UUID) -> Void)?
    var onCycle: ((Int) -> Void)?
    var onShortcutRecording: ((Bool) -> Void)?
    var onChange: ((ButtonProfileLibrary) -> Void)?
    private var library: ButtonProfileLibrary
    private var selectedID: UUID
    private var loading = false
    private let table = NSTableView()
    private let name = NSTextField()
    private let appSummary = NSTextField(labelWithString: "")
    private let action = NSPopUpButton()
    private let automatic = NSPopUpButton()
    private let target = NSTextField()
    private let save = NSButton(title: "Save agent", target: nil, action: nil)
    private let choose = NSButton(title: "Choose app…", target: nil, action: nil)
    private let remove = NSButton(title: "Remove", target: nil, action: nil)
    private let previousRecorder = ShortcutRecorder()
    private let nextRecorder = ShortcutRecorder()
    private let shortcuts = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private var selected: ButtonProfile { library.profiles.first { $0.id == selectedID } ?? library.active }

    init(library: ButtonProfileLibrary) {
        self.library = library; selectedID = library.activeID
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 690), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Headset Remap · Configuration · Agents"; window.isReleasedWhenClosed = false
        super.init(window: window); window.center(); build(); loadSelection(); loadCycleShortcuts()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present() { showWindow(nil); NSApp.activate(ignoringOtherApps: true) }
    func update(_ next: ButtonProfileLibrary) {
        let preserve = dirty
        library = next
        if !library.profiles.contains(where: { $0.id == selectedID }) { selectedID = library.activeID }
        loadCycleShortcuts()
        if !preserve { loadSelection() } else { loading = true; table.reloadData(); loading = false }
    }
    private func row(_ views: [NSView]) -> NSStackView { let result = NSStackView(views: views); result.orientation = .horizontal; result.spacing = 10; result.alignment = .centerY; return result }
    private func build() {
        let heading = NSTextField(labelWithString: "Agents & actions"); heading.font = .systemFont(ofSize: 25, weight: .semibold)
        let help = NSTextField(wrappingLabelWithString: "Select an agent to configure its app and follow-up actions. Check agents to show them in the launcher. Siri stays first."); help.textColor = .secondaryLabelColor; help.preferredMaxLayoutWidth = 700
        let enabled = NSTableColumn(identifier: .init("enabled")); enabled.title = "On"; enabled.width = 28; enabled.minWidth = 28; enabled.maxWidth = 28
        let names = NSTableColumn(identifier: .init("name")); names.title = "Agent"; names.width = 170; names.minWidth = 160; names.maxWidth = 170
        let order = NSTableColumn(identifier: .init("order")); order.title = ""; order.width = 52; order.minWidth = 52; order.maxWidth = 52
        table.addTableColumn(enabled); table.addTableColumn(names); table.addTableColumn(order); table.columnAutoresizingStyle = .noColumnAutoresizing; table.rowHeight = 32; table.delegate = self; table.dataSource = self
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.widthAnchor.constraint(equalToConstant: 280).isActive = true; scroll.heightAnchor.constraint(equalToConstant: 270).isActive = true
        let add = NSButton(title: "Add agent…", target: self, action: #selector(addAgent))
        remove.target = self; remove.action = #selector(removeAgent)
        let left = ConfigurationSection("Available agents", views: [scroll, row([add, remove])])
        name.delegate = self; name.font = .systemFont(ofSize: 18, weight: .semibold)
        action.addItems(withTitles: ButtonAction.primaryCases.map(\.title)); action.target = self; action.action = #selector(formChanged)
        target.delegate = self; target.placeholderString = "App path, URL or macOS Shortcut name"
        choose.target = self; choose.action = #selector(chooseApp)
        automatic.target = self; automatic.action = #selector(formChanged)
        automatic.setAccessibilityLabel("Secondary action after primary action")
        automatic.toolTip = "Choose what runs after the primary action when you press the headset button."
        automatic.widthAnchor.constraint(equalToConstant: 548).isActive = true
        save.target = self; save.action = #selector(saveAgent); save.bezelColor = .controlAccentColor
        let test = NSButton(title: "Test primary action", target: self, action: #selector(testAgent))
        let actions = NSButton(title: "Edit secondary actions…", target: self, action: #selector(showActions))
        shortcuts.font = .systemFont(ofSize: 12); shortcuts.textColor = .secondaryLabelColor; shortcuts.preferredMaxLayoutWidth = 548
        let custom = ConfigurationDisclosure("Advanced: custom target", views: [action, target])
        appSummary.textColor = .secondaryLabelColor
        appSummary.lineBreakMode = .byTruncatingMiddle
        appSummary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        choose.setContentCompressionResistancePriority(.required, for: .horizontal)
        let primaryRow = row([appSummary, choose])
        primaryRow.widthAnchor.constraint(lessThanOrEqualToConstant: 548).isActive = true
        let primary = ConfigurationSection("Primary action", views: [primaryRow, custom])
        let secondaryHint = NSTextField(wrappingLabelWithString: "Runs after the primary action when you press the headset button.")
        secondaryHint.textColor = .secondaryLabelColor
        secondaryHint.font = .systemFont(ofSize: 12)
        secondaryHint.preferredMaxLayoutWidth = 548
        let secondary = ConfigurationSection("Secondary action", views: [automatic, secondaryHint, actions])
        let right = NSStackView(views: [name, primary, secondary, row([save, test]), status])
        right.orientation = .vertical; right.alignment = .leading; right.spacing = 20
        primary.widthAnchor.constraint(equalToConstant: 548).isActive = true
        secondary.widthAnchor.constraint(equalToConstant: 548).isActive = true
        right.widthAnchor.constraint(equalToConstant: 548).isActive = true
        for field in [name, target, shortcuts, status] { field.widthAnchor.constraint(equalToConstant: 548).isActive = true }
        status.preferredMaxLayoutWidth = 548; status.font = .systemFont(ofSize: 12)
        let body = row([left, right]); body.alignment = .top; body.spacing = 24
        for recorder in [previousRecorder, nextRecorder] {
            recorder.onRecording = { [weak self] recording in self?.onShortcutRecording?(recording) }
            recorder.onChange = { [weak self] in self?.saveCycleShortcuts() }
        }
        previousRecorder.setAccessibilityLabel("Previous agent shortcut")
        nextRecorder.setAccessibilityLabel("Next agent shortcut")
        let cycleTitle = NSTextField(labelWithString: "Cycle agents"); cycleTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        let tryPrevious = NSButton(title: "Try", target: self, action: #selector(tryPreviousAgent))
        tryPrevious.toolTip = "Switch to the previous enabled agent"
        let tryNext = NSButton(title: "Try", target: self, action: #selector(tryNextAgent))
        tryNext.toolTip = "Switch to the next enabled agent"
        let cycleRow = row([NSTextField(labelWithString: "Previous"), previousRecorder, tryPrevious, NSTextField(labelWithString: "Next"), nextRecorder, tryNext])
        let cycleHint = NSTextField(labelWithString: "Switches the headset agent and shows its name beside the menu bar icon.")
        cycleHint.font = .systemFont(ofSize: 12); cycleHint.textColor = .secondaryLabelColor
        let navigation = ConfigurationNavigation(section: "Agents & actions", onBack: { [weak self] in self?.onBack?() })
        let keyboard = ConfigurationDisclosure("Advanced: agent switching shortcuts", views: [cycleTitle, cycleRow, cycleHint, shortcuts])
        let root = NSStackView(views: [navigation, heading, help, body, keyboard]); root.orientation = .vertical; root.alignment = .leading; root.spacing = 16; root.translatesAutoresizingMaskIntoConstraints = false
        window!.contentView!.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: window!.contentView!.leadingAnchor, constant: 24), root.topAnchor.constraint(equalTo: window!.contentView!.topAnchor, constant: 24)])
    }
    private func loadCycleShortcuts() {
        previousRecorder.shortcut = library.effectiveCycleShortcuts.previous
        nextRecorder.shortcut = library.effectiveCycleShortcuts.next
    }
    private func saveCycleShortcuts() {
        do {
            var next = library
            try next.updateCycleShortcuts(previous: previousRecorder.shortcut, next: nextRecorder.shortcut)
            let preserveDraft = dirty
            try next.save(); library = next; onChange?(next); loadCycleShortcuts()
            if !preserveDraft { loadSelection() }
            status.stringValue = "Cycle shortcuts saved."
        } catch { status.stringValue = error.localizedDescription; loadCycleShortcuts() }
    }
    @objc private func tryPreviousAgent() { onCycle?(-1) }
    @objc private func tryNextAgent() { onCycle?(1) }
    func numberOfRows(in tableView: NSTableView) -> Int { library.profiles.count }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let profile = library.profiles[row]
        if column?.identifier.rawValue == "enabled" {
            let toggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))
            toggle.tag = row; toggle.state = profile.isEnabled ? .on : .off; toggle.isEnabled = profile.builtInSiri != true
            toggle.setAccessibilityLabel("Enable \(profile.name)"); return toggle
        }
        if column?.identifier.rawValue == "order" {
            let up = NSButton(image: NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil)!, target: self, action: #selector(moveRowUp(_:)))
            let down = NSButton(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)!, target: self, action: #selector(moveRowDown(_:)))
            for button in [up, down] {
                button.tag = row; button.isBordered = false
                button.widthAnchor.constraint(equalToConstant: 21).isActive = true
                button.heightAnchor.constraint(equalToConstant: 24).isActive = true
            }
            up.setAccessibilityLabel("Move \(profile.name) up"); down.setAccessibilityLabel("Move \(profile.name) down")
            up.isEnabled = profile.builtInSiri != true && row > 1
            down.isEnabled = profile.builtInSiri != true && row < library.profiles.count - 1
            let buttons = NSStackView(views: [up, down]); buttons.orientation = .horizontal; buttons.alignment = .centerY; buttons.spacing = 4
            return buttons
        }
        let text = NSTextField(labelWithString: library.displayName(profile))
        text.lineBreakMode = .byTruncatingTail
        text.textColor = profile.isEnabled ? .labelColor : .secondaryLabelColor
        return text
    }
    private func readSettings() -> ButtonSettings {
        var result = selected.settings; result.action = ButtonAction.primaryCases[action.indexOfSelectedItem]; result.target = target.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); return result
    }
    private var automaticSelection: String? { automatic.selectedItem?.representedObject as? String }
    private var dirty: Bool { !loading && action.indexOfSelectedItem >= 0 && (name.stringValue != selected.name || readSettings() != selected.settings || automaticSelection != selected.automaticActionSelection) }
    private func loadSelection() {
        loading = true
        name.stringValue = selected.name; action.selectItem(at: ButtonAction.primaryCases.firstIndex(of: selected.settings.action)!); target.stringValue = selected.settings.target
        appSummary.stringValue = selected.settings.action == .openApp
            ? "Opens " + (Bundle(path: selected.settings.target)?.bundleIdentifier == "com.openai.codex" ? "Codex" : URL(fileURLWithPath: selected.settings.target).deletingPathExtension().lastPathComponent)
            : selected.settings.action.title
        automatic.removeAllItems()
        automatic.addItem(withTitle: "None")
        automatic.item(at: 0)?.representedObject = "none"
        for secondary in selected.secondaryActions ?? [] {
            automatic.addItem(withTitle: secondary.name + (secondary.isConfigured ? "" : " (needs setup)"))
            automatic.lastItem?.representedObject = secondary.id.uuidString
            automatic.lastItem?.isEnabled = secondary.isConfigured
        }
        automatic.menu?.addItem(.separator())
        automatic.addItem(withTitle: "All checked secondary actions, in order")
        automatic.menu?.autoenablesItems = false
        automatic.selectItem(at: automatic.numberOfItems - 1)
        if let selection = selected.automaticActionSelection {
            automatic.selectItem(at: automatic.itemArray.firstIndex { ($0.representedObject as? String) == selection } ?? 0)
        }
        let fixed = selected.builtInSiri == true
        name.isEnabled = !fixed; action.isEnabled = !fixed; target.isEnabled = !fixed; choose.isEnabled = !fixed
        let index = library.profiles.firstIndex { $0.id == selectedID }!
        remove.isEnabled = !fixed
        table.reloadData(); table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        if let number = library.number(for: selectedID) {
            shortcuts.stringValue = "Agent \(number)\nRun: \(selected.runShortcut?.label ?? "Not assigned")\nSwitch: \(selected.activateShortcut?.label ?? "Not assigned")"
        } else { shortcuts.stringValue = "Disabled: no number or active keyboard shortcuts. Configure its action, then enable it in the list." }
        loading = false; save.isEnabled = false
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !loading, library.profiles.indices.contains(table.selectedRow) else { return }
        let id = library.profiles[table.selectedRow].id
        guard id != selectedID else { return }
        guard prepareForExternalEdit() else { loading = true; table.selectRowIndexes(IndexSet(integer: library.profiles.firstIndex { $0.id == selectedID }!), byExtendingSelection: false); loading = false; return }
        selectedID = id; loadSelection(); status.stringValue = ""
    }
    @objc private func formChanged() {
        let settings = readSettings()
        appSummary.stringValue = settings.action == .openApp
            ? "Opens " + (Bundle(path: settings.target)?.bundleIdentifier == "com.openai.codex" ? "Codex" : URL(fileURLWithPath: settings.target).deletingPathExtension().lastPathComponent)
            : settings.action.title
        save.isEnabled = dirty
    }
    func controlTextDidChange(_ obj: Notification) { formChanged() }
    func prepareForExternalEdit() -> Bool {
        guard dirty else { return true }
        let alert = NSAlert(); alert.messageText = "Save changes to \(selected.name)?"
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Discard"); alert.addButton(withTitle: "Cancel")
        switch alert.runModal() { case .alertFirstButtonReturn: return commit(); case .alertSecondButtonReturn: loadSelection(); return true; default: return false }
    }
    private func apply(_ next: ButtonProfileLibrary) throws {
        try next.save(); library = next; onChange?(next); loadSelection()
    }
    @discardableResult private func commit() -> Bool {
        let settings = readSettings()
        if let error = settings.validationError { status.stringValue = error; return false }
        do { var next = library; if selected.builtInSiri != true { try next.updateAgent(selectedID, name: name.stringValue, settings: settings) }; try next.setAutomaticActionSelection(automaticSelection, for: selectedID); try apply(next); status.stringValue = "Saved."; return true }
        catch { status.stringValue = error.localizedDescription; return false }
    }
    @objc private func saveAgent() { _ = commit() }
    @objc private func toggleEnabled(_ sender: NSButton) {
        let id = library.profiles[sender.tag].id
        guard prepareForExternalEdit() else { loadSelection(); return }
        do { var next = library; try next.setAgentEnabled(id, enabled: sender.state == .on); try apply(next); status.stringValue = "Agent order and shortcuts updated." }
        catch { status.stringValue = error.localizedDescription; loadSelection() }
    }
    private func move(_ offset: Int, row: Int) {
        guard library.profiles.indices.contains(row), prepareForExternalEdit() else { return }
        selectedID = library.profiles[row].id
        do { var next = library; try next.moveAgent(selectedID, offset: offset); try apply(next); status.stringValue = "Order and shortcuts updated." }
        catch { status.stringValue = error.localizedDescription }
    }
    @objc private func moveRowUp(_ sender: NSButton) { move(-1, row: sender.tag) }
    @objc private func moveRowDown(_ sender: NSButton) { move(1, row: sender.tag) }
    @objc private func addAgent() {
        guard prepareForExternalEdit() else { return }
        do {
            var next = library; let id = try next.addAgent(name: "New agent \(library.profiles.count)")
            selectedID = id; try apply(next); window?.makeFirstResponder(name)
        } catch { status.stringValue = error.localizedDescription }
    }
    @objc private func removeAgent() {
        guard selected.builtInSiri != true, prepareForExternalEdit() else { return }
        let alert = NSAlert(); alert.messageText = "Remove \(selected.name)?"; alert.informativeText = "Its saved profile and button actions will be removed."
        alert.addButton(withTitle: "Remove"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { var next = library; try next.removeAgent(selectedID); selectedID = next.activeID; try apply(next) }
        catch { status.stringValue = error.localizedDescription }
    }
    @objc private func chooseApp() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        action.selectItem(at: 0); target.stringValue = url.path; formChanged()
    }
    @objc private func showActions() { if prepareForExternalEdit() { onActions?(selectedID) } }
    @objc private func testAgent() {
        guard readSettings().action != .none else { status.stringValue = "Choose an action first."; return }
        ButtonActionExecutor.run(readSettings()) { [weak self] error in self?.status.stringValue = error ?? "Action opened." } }
}
