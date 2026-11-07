import Cocoa
import UniformTypeIdentifiers

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class ButtonSettingsWindow: NSWindowController, NSTextFieldDelegate {
    var onBack: (() -> Void)?
    var onChange: ((ButtonProfileLibrary) -> Void)?
    var onLearningChanged: ((Bool) -> Void)?
    var onAgentsRequested: (() -> Void)?
    var onButtonsRequested: (() -> Void)?
    var onDebugRequested: (() -> Void)?
    var statusProvider: (() -> String)?
    var shortcutStatusProvider: (() -> String)?
    var onShortcutRecording: ((Bool) -> Void)?

    private var library: ButtonProfileLibrary
    private var settings: ButtonSettings
    private let profilePicker = NSPopUpButton()
    private let profileSegments = NSSegmentedControl()
    private let managePicker = NSPopUpButton()
    private let summary = NSTextField(wrappingLabelWithString: "")
    private let readiness = NSTextField(wrappingLabelWithString: "")
    private let actionPresets = NSPopUpButton()
    private let saveButton = NSButton(title: "Save changes", target: nil, action: nil)
    private let disclosure = NSButton(title: "Advanced settings", target: nil, action: nil)
    private let advanced = NSStackView()
    private let root = NSStackView()
    private let contentDocument = SettingsDocumentView()
    private let scroll = NSScrollView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let nameRow = NSStackView()
    private let nameField = NSTextField()
    private var nameOperation: String?
    private var statusTimer: Timer?

    private let activateRecorder = ShortcutRecorder()
    private let runRecorder = ShortcutRecorder()
    private let shortcutHint = NSTextField(wrappingLabelWithString: "")
    private let shortcutSummary = NSTextField(wrappingLabelWithString: "")
    private let runLabel = NSTextField(labelWithString: "")
    private let switchLabel = NSTextField(labelWithString: "")
    private let runKey = NSTextField(labelWithString: "")
    private let switchKey = NSTextField(labelWithString: "")
    private let mappingLabel = NSTextField(wrappingLabelWithString: "")
    private let candidates = NSPopUpButton()
    private let learnButton = NSButton(title: "Start learning", target: nil, action: nil)
    private let actionPicker = NSPopUpButton()
    private let focusTimingPicker = NSPopUpButton()
    private var chooseAppButton: NSButton!
    private let targetField = NSTextField()
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let legacy = NSButton(checkboxWithTitle: "Enable original mute and Music controls", target: nil, action: nil)
    private let standalone = NSButton(checkboxWithTitle: "Use Teams button without Microsoft Teams", target: nil, action: nil)
    private var signals: [ButtonSignal] = []
    private var learning = false
    private var learnTimer: Timer?

    init(library: ButtonProfileLibrary) {
        self.library = library
        self.settings = library.active.settings
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 410),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Headset Remap · Configuration · Advanced settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
        buildInterface()
        populateForm()
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosing),
                                               name: NSWindow.willCloseNotification, object: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { learnTimer?.invalidate(); statusTimer?.invalidate(); NotificationCenter.default.removeObserver(self) }

    private func buildInterface() {
        let heading = NSTextField(labelWithString: "Advanced settings")
        heading.font = .systemFont(ofSize: 25, weight: .semibold)
        profilePicker.target = self; profilePicker.action = #selector(profileSelected)
        profilePicker.setAccessibilityLabel("Active profile")
        profilePicker.widthAnchor.constraint(equalToConstant: 752).isActive = true
        managePicker.addItems(withTitles: ["•••", "Save as new profile…", "Rename profile…", "Delete profile…"])
        managePicker.target = self; managePicker.action = #selector(manageProfile)
        managePicker.setAccessibilityLabel("Manage profiles")
        managePicker.toolTip = "Manage profiles"
        managePicker.widthAnchor.constraint(equalToConstant: 44).isActive = true
        profileSegments.segmentStyle = .rounded; profileSegments.trackingMode = .selectOne
        profileSegments.target = self; profileSegments.action = #selector(segmentSelected)
        profileSegments.widthAnchor.constraint(equalToConstant: 752).isActive = true
        let profileRow = row([profileSegments, profilePicker])
        summary.font = .systemFont(ofSize: 24, weight: .semibold)
        readiness.textColor = .secondaryLabelColor
        actionPresets.addItems(withTitles: ["Change action…", "Choose application…", "Open URL…", "Run Shortcut…"])
        actionPresets.target = self; actionPresets.action = #selector(selectPreset)
        saveButton.target = self; saveButton.action = #selector(saveSettings)
        saveButton.keyEquivalent = "\r"
        readiness.textColor = .secondaryLabelColor
        disclosure.target = self; disclosure.action = #selector(toggleAdvanced)
        disclosure.bezelStyle = .inline
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor

        nameField.placeholderString = "Profile name"
        nameField.widthAnchor.constraint(equalToConstant: 260).isActive = true
        let confirmName = NSButton(title: "Save profile", target: self, action: #selector(commitName))
        let cancelName = NSButton(title: "Cancel", target: self, action: #selector(cancelName))
        configure(nameRow, views: [nameField, confirmName, cancelName], vertical: false, spacing: 8)
        nameRow.isHidden = true

        mappingLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        learnButton.target = self; learnButton.action = #selector(toggleLearning)
        candidates.target = self; candidates.action = #selector(selectSignal)
        candidates.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        actionPicker.addItems(withTitles: ButtonAction.primaryCases.map(\.title))
        actionPicker.target = self; actionPicker.action = #selector(formChanged)
        focusTimingPicker.addItems(withTitles: AgentFocusTiming.allCases.map(\.title))
        focusTimingPicker.target = self; focusTimingPicker.action = #selector(formChanged)
        targetField.delegate = self
        targetField.placeholderString = "App path, URL or Shortcut name"
        let choose = NSButton(title: "Choose app…", target: self, action: #selector(chooseApp))
        chooseAppButton = choose
        for checkbox in [legacy, standalone] { checkbox.target = self; checkbox.action = #selector(formChanged) }
        standalone.toolTip = "Experimental local handshake. Pauses when Microsoft Teams is running."
        legacy.toolTip = "Keeps the headset in call mode."
        hint.font = .systemFont(ofSize: 12); hint.textColor = .secondaryLabelColor
        for recorder in [activateRecorder, runRecorder] {
            recorder.onChange = { [weak self] in self?.status.stringValue = ""; self?.refreshForm() }
            recorder.onRecording = { [weak self] recording in self?.onShortcutRecording?(recording) }
            recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        }
        activateRecorder.setAccessibilityLabel("Switch to this profile shortcut")
        runRecorder.setAccessibilityLabel("Run this profile action shortcut")
        shortcutHint.font = .systemFont(ofSize: 12); shortcutHint.textColor = .secondaryLabelColor
        shortcutSummary.font = .systemFont(ofSize: 12); shortcutSummary.textColor = .secondaryLabelColor
        configure(advanced, views: [
                  row([NSTextField(labelWithString: "Open this agent now"), runRecorder]),
                  row([NSTextField(labelWithString: "Select this agent for the headset"), activateRecorder]), shortcutHint], vertical: true, spacing: 16)
        advanced.isHidden = false
        let keyboard = ConfigurationSection("Keyboard shortcuts", views: [advanced])
        let options = ConfigurationDisclosure("Advanced: timing & compatibility", views: [
                  sectionLabel("Headset activation"),
                  row([NSTextField(labelWithString: "Wait after pressing the Teams button"), focusTimingPicker]),
                  sectionLabel("Compatibility"), standalone, legacy])
        options.onToggle = { [weak self] in self?.resizeToContent() }
        let navigation = ConfigurationNavigation(section: "Advanced settings", onBack: { [weak self] in self?.onBack?() })
        let intro = NSTextField(wrappingLabelWithString: "Choose the active headset agent, then adjust its shortcuts. Timing and compatibility options are under Advanced below.")
        intro.textColor = .secondaryLabelColor; intro.preferredMaxLayoutWidth = 752
        configure(root, views: [navigation, heading, intro, NSTextField(labelWithString: "Active headset agent"), profileRow, readiness, keyboard, options, saveButton, status], vertical: true, spacing: 24)
        root.detachesHiddenViews = true
        advanced.detachesHiddenViews = true

        scroll.frame = window!.contentView!.bounds
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay; scroll.drawsBackground = false
        contentDocument.frame = NSRect(x: 0, y: 0, width: 800, height: 410)
        contentDocument.autoresizingMask = [.width]
        scroll.documentView = contentDocument
        window!.contentView!.addSubview(scroll)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentDocument.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentDocument.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: contentDocument.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: contentDocument.topAnchor, constant: 24),
            keyboard.widthAnchor.constraint(equalTo: root.widthAnchor),
            options.widthAnchor.constraint(equalTo: root.widthAnchor),
            advanced.widthAnchor.constraint(equalTo: root.widthAnchor),
            targetField.widthAnchor.constraint(greaterThanOrEqualToConstant: 330),
            summary.widthAnchor.constraint(lessThanOrEqualToConstant: 370)
        ])
        for label in [readiness, intro, shortcutHint, status] {
            label.preferredMaxLayoutWidth = 752
            label.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(); configure(stack, views: views, vertical: false, spacing: 10); return stack
    }
    private func configure(_ stack: NSStackView, views: [NSView], vertical: Bool, spacing: CGFloat) {
        stack.orientation = vertical ? .vertical : .horizontal
        stack.alignment = vertical ? .leading : .centerY
        stack.spacing = spacing
        stack.detachesHiddenViews = true
        for view in views { stack.addArrangedSubview(view) }
    }
    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 13, weight: .semibold); return label
    }
    private func resizeToContent() {
        contentDocument.layoutSubtreeIfNeeded()
        let height = root.fittingSize.height + 48
        let maximum = (window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let windowHeight = min(max(height, 330), maximum - 100)
        window?.setContentSize(NSSize(width: 800, height: windowHeight))
        contentDocument.setFrameSize(NSSize(width: 800, height: max(height, windowHeight)))
    }
    func present() {
        refreshReadiness(); resizeToContent(); showWindow(nil); NSApp.activate(ignoringOtherApps: true)
        if statusTimer == nil {
            statusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshReadiness() }
        }
    }
    func presentShortcuts() {
        if advanced.isHidden { toggleAdvanced() }
        present()
    }
    func refreshShortcutStatus() { refreshForm() }
    func cancelLearning() { if learning { stopLearning() } }
    func prepareForExternalEdit() -> Bool {
        cancelLearning()
        guard hasChanges else { return true }
        let alert = NSAlert(); alert.messageText = "Save changes to \(library.active.name)?"
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Discard"); alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveCurrent()
        case .alertSecondButtonReturn: populateForm(); return true
        default: return false
        }
    }
    func synchronize(_ next: ButtonProfileLibrary) {
        let preserve = hasChanges && library.activeID == next.activeID
        library = next
        if !preserve { populateForm() }
    }
    @objc private func openAgents() { onAgentsRequested?() }
    @objc private func openAllButtons() { onButtonsRequested?() }
    private func refreshReadiness() {
        readiness.stringValue = "Editing settings for \(library.active.name)."
    }
    private func populateForm() {
        settings = library.active.settings
        let fixed = library.active.builtInSiri == true
        for control in [actionPicker as NSControl, actionPresets, targetField, chooseAppButton!, activateRecorder, runRecorder] { control.isEnabled = !fixed }
        activateRecorder.stopRecording(); runRecorder.stopRecording()
        activateRecorder.shortcut = library.active.activateShortcut
        runRecorder.shortcut = library.active.runShortcut
        profilePicker.removeAllItems(); profilePicker.addItems(withTitles: library.enabledProfiles.map { library.displayName($0) })
        profilePicker.selectItem(at: library.enabledProfiles.firstIndex { $0.id == library.activeID }!)
        profileSegments.segmentCount = library.enabledProfiles.count
        for (index, profile) in library.enabledProfiles.enumerated() { profileSegments.setLabel(library.displayName(profile), forSegment: index) }
        profileSegments.selectedSegment = library.enabledProfiles.firstIndex { $0.id == library.activeID }!
        profileSegments.isHidden = library.enabledProfiles.count > 4
        profilePicker.isHidden = library.enabledProfiles.count <= 4
        actionPicker.selectItem(at: ButtonAction.primaryCases.firstIndex(of: settings.action)!)
        focusTimingPicker.selectItem(at: AgentFocusTiming.allCases.firstIndex(of: settings.effectiveFocusTiming)!)
        targetField.stringValue = settings.target
        standalone.state = settings.standaloneTeamsButton == true ? .on : .off
        legacy.state = settings.legacyControls ? .on : .off
        signals.removeAll(); candidates.removeAllItems(); candidates.addItem(withTitle: "No captured signals")
        refreshForm(); refreshReadiness()
    }
    private func readForm() -> ButtonSettings {
        var result = settings
        result.action = ButtonAction.primaryCases[actionPicker.indexOfSelectedItem]
        result.target = targetField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        result.focusTiming = AgentFocusTiming.allCases[focusTimingPicker.indexOfSelectedItem]
        // Preserve nil/default encodings when no effective value changed.
        if result.focusTiming == settings.effectiveFocusTiming { result.focusTiming = settings.focusTiming }
        result.standaloneTeamsButton = standalone.state == .on
        if result.standaloneTeamsButton == (settings.standaloneTeamsButton == true) { result.standaloneTeamsButton = settings.standaloneTeamsButton }
        result.legacyControls = legacy.state == .on
        return result
    }
    private func refreshForm() {
        let draft = readForm()
        switch draft.action {
        case .openApp:
            let bundle = Bundle(path: draft.target)?.bundleIdentifier
            let name = bundle == "com.openai.codex" ? "Codex" : URL(fileURLWithPath: draft.target).deletingPathExtension().lastPathComponent
            summary.stringValue = "Open \(name.isEmpty ? "an app" : name)"
        case .openURL: summary.stringValue = "Open \(URL(string: draft.target)?.host ?? "a URL")"
        case .shortcut: summary.stringValue = "Run \(draft.target.isEmpty ? "a Shortcut" : draft.target)"
        case .none: summary.stringValue = "No action assigned"
        case .agentAction: summary.stringValue = "Run agent action"
        }
        mappingLabel.stringValue = settings.signal?.label ?? "No button learned"
        hint.stringValue = draft.action.hint
        let run = runRecorder.shortcut.map { "Run action: \($0.label)" } ?? "Run action: no keyboard shortcut"
        let activate = activateRecorder.shortcut.map { "Switch profile: \($0.label)" } ?? "Switch profile: no keyboard shortcut"
        shortcutSummary.stringValue = "\(run)  ·  \(activate)"
        shortcutHint.stringValue = shortcutStatusProvider?().isEmpty == false ? shortcutStatusProvider!() : "Open starts the app immediately. Select changes which agent the headset uses. Click a shortcut to record it; Delete clears it."
        runLabel.stringValue = "Run \(library.active.name)"
        switchLabel.stringValue = "Switch to \(library.active.name)"
        runKey.stringValue = runRecorder.shortcut?.label ?? "Not set"
        switchKey.stringValue = activateRecorder.shortcut?.label ?? "Not set"
        saveButton.isEnabled = hasChanges
        saveButton.isHidden = !hasChanges
        resizeToContent()
    }
    private var hasChanges: Bool {
        readForm() != library.active.settings || activateRecorder.shortcut != library.active.activateShortcut || runRecorder.shortcut != library.active.runShortcut
    }
    private func updatedDraft() throws -> ButtonProfileLibrary {
        var next = library; next.updateActive(readForm())
        try next.updateActiveShortcuts(activate: activateRecorder.shortcut, run: runRecorder.shortcut)
        return next
    }
    @objc private func formChanged() { refreshForm() }
    func controlTextDidChange(_ obj: Notification) { refreshForm() }

    private func commit(_ next: ButtonProfileLibrary) throws {
        try next.save(); library = next; onChange?(next); populateForm()
    }
    @discardableResult private func saveCurrent() -> Bool {
        let draft = readForm()
        if let error = draft.validationError { status.stringValue = error; resizeToContent(); return false }
        do { try commit(updatedDraft()); status.stringValue = "Saved \(library.active.name)."; resizeToContent(); return true }
        catch { status.stringValue = error.localizedDescription; resizeToContent(); return false }
    }
    @objc private func saveSettings() { if learning { stopLearning() }; _ = saveCurrent() }

    func selectProfile(_ id: UUID) {
        guard id != library.activeID else { return }
        if learning { stopLearning() }
        if hasChanges {
            let alert = NSAlert()
            alert.messageText = "Save changes to \(library.active.name)?"
            alert.informativeText = "Switching profiles will replace the unsaved settings in this window."
            alert.addButton(withTitle: "Save and switch"); alert.addButton(withTitle: "Discard and switch"); alert.addButton(withTitle: "Cancel")
            let result = alert.runModal()
            if result == .alertFirstButtonReturn && !saveCurrent() { restoreProfileSelection(); return }
            if result == .alertThirdButtonReturn { restoreProfileSelection(); return }
        }
        var next = library
        do { try next.select(id); try commit(next); status.stringValue = "Using \(library.active.name)."; resizeToContent() }
        catch { status.stringValue = error.localizedDescription; restoreProfileSelection() }
    }
    private func restoreProfileSelection() {
        let index = library.enabledProfiles.firstIndex { $0.id == library.activeID }!
        profilePicker.selectItem(at: index); profileSegments.selectedSegment = index
    }
    @objc private func segmentSelected() {
        let index = profileSegments.selectedSegment
        guard library.enabledProfiles.indices.contains(index) else { return }
        selectProfile(library.enabledProfiles[index].id)
    }
    @objc private func profileSelected() {
        let index = profilePicker.indexOfSelectedItem
        guard library.enabledProfiles.indices.contains(index) else { return }
        selectProfile(library.enabledProfiles[index].id)
    }
    @objc private func manageProfile() {
        let index = managePicker.indexOfSelectedItem; managePicker.selectItem(at: 0)
        if index > 0 && library.active.builtInSiri == true { status.stringValue = "Siri is fixed as agent 1. Use Agents to configure the others."; return }
        if index == 1 || index == 2 {
            nameOperation = index == 1 ? "create" : "rename"
            nameField.stringValue = index == 1 ? "\(library.active.name) copy" : library.active.name
            nameRow.isHidden = false; resizeToContent(); window?.makeFirstResponder(nameField)
        } else if index == 3 {
            guard library.enabledProfiles.count > 1 else { status.stringValue = "Keep at least one profile."; resizeToContent(); return }
            let alert = NSAlert(); alert.messageText = "Delete \(library.active.name)?"
            alert.informativeText = "The saved configuration for this profile will be removed."
            alert.addButton(withTitle: "Delete profile"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            var next = library
            do { try next.deleteActive(); try commit(next); status.stringValue = "Profile deleted."; resizeToContent() }
            catch { status.stringValue = error.localizedDescription }
        }
    }
    @objc private func commitName() {
        let draft = readForm()
        if let error = draft.validationError { status.stringValue = error; resizeToContent(); return }
        var next = library
        do {
            if nameOperation == "create" { try next.add(name: nameField.stringValue, settings: draft) }
            else { next = try updatedDraft(); try next.renameActive(to: nameField.stringValue) }
            try commit(next); cancelName(); status.stringValue = "Saved \(library.active.name)."; resizeToContent()
        } catch { status.stringValue = error.localizedDescription; resizeToContent() }
    }
    @objc private func cancelName() { nameRow.isHidden = true; nameOperation = nil; resizeToContent() }

    @objc private func toggleAdvanced() {
        advanced.isHidden.toggle()
        disclosure.title = advanced.isHidden ? "Advanced settings" : "Hide advanced settings"
        resizeToContent()
    }
    func receive(_ signal: ButtonSignal) {
        guard learning, !signals.contains(signal), signals.count < 100 else { return }
        if signals.isEmpty { candidates.removeAllItems() }
        signals.append(signal); candidates.addItem(withTitle: signal.label)
        status.stringValue = "Captured \(signals.count) signals. Stop learning and choose the press event."
    }
    private func stopLearning() {
        learning = false; learnTimer?.invalidate(); learnTimer = nil; onLearningChanged?(false)
        learnButton.title = "Start learning"
        if signals.isEmpty { status.stringValue = "No input captured. Open Debug to check the connection." }
        else { selectSignal() }
        resizeToContent()
    }
    @objc private func toggleLearning() {
        if learning { stopLearning(); return }
        signals.removeAll(); candidates.removeAllItems(); candidates.addItem(withTitle: "Waiting for the button…")
        learning = true; onLearningChanged?(true); learnButton.title = "Stop learning"
        status.stringValue = "Press and release only your chosen button. Learning stops after 15 seconds."
        learnTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in self?.stopLearning() }
        resizeToContent()
    }
    @objc private func selectSignal() {
        let index = candidates.indexOfSelectedItem
        guard !learning, signals.indices.contains(index) else { return }
        settings.learnInput(signals[index]); refreshForm(); refreshReadiness()
    }
    @objc private func clearSignal() { if learning { stopLearning() }; if let signal = settings.signal { settings.removeInput(signal) }; refreshForm(); refreshReadiness() }
    @objc private func openDebug() { onDebugRequested?() }
    @objc private func selectPreset() {
        let index = actionPresets.indexOfSelectedItem; actionPresets.selectItem(at: 0)
        if index == 1 { chooseApp(); return }
        if index == 2 { actionPicker.selectItem(at: 1) }
        if index == 3 { actionPicker.selectItem(at: 2) }
        if index > 1 { if advanced.isHidden { toggleAdvanced() }; refreshForm(); window?.makeFirstResponder(targetField) }
    }
    @objc private func chooseApp() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        actionPicker.selectItem(at: 0); targetField.stringValue = url.path; refreshForm()
    }
    @objc private func testAction() {
        guard !learning else { status.stringValue = "Stop learning before testing."; return }
        let draft = readForm()
        if let error = draft.validationError { status.stringValue = error; resizeToContent(); return }
        ButtonActionExecutor.run(draft) { [weak self] error in
            self?.status.stringValue = error ?? "Action opened. Check the target app."
            self?.resizeToContent()
        }
    }
    @objc private func windowClosing() {
        activateRecorder.stopRecording(); runRecorder.stopRecording()
        if learning { stopLearning() }; statusTimer?.invalidate(); statusTimer = nil
        nameRow.isHidden = true; populateForm(); status.stringValue = ""
    }
}

enum ButtonActionExecutor {
    private static var shortcutRunning = false
    static var agentActionHandler: ((AgentActionReference, @escaping (String?) -> Void) -> Void)?
    static func run(_ settings: ButtonSettings, completion: @escaping (String?) -> Void) {
        if let error = settings.validationError { completion(error); return }
        switch settings.action {
        case .none: completion(nil)
        case .agentAction:
            guard let reference = AgentActionReference(settings.target), let handler = agentActionHandler else { completion("Agent action is unavailable."); return }
            handler(reference, completion)
        case .openApp:
            let config = NSWorkspace.OpenConfiguration(); config.activates = true
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: settings.target), configuration: config) { app, error in
                DispatchQueue.main.async {
                    if error == nil { _ = app?.activate(options: []) }
                    completion(error?.localizedDescription)
                    guard error == nil, let app else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        let foreground = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
                        AppLog.log("ACTION focus: target=\(app.bundleIdentifier ?? "unknown"), foreground=\(foreground)")
                    }
                }
            }
        case .openURL:
            guard let url = URL(string: settings.target) else { completion("Invalid URL"); return }
            completion(NSWorkspace.shared.open(url) ? nil : "No application could open this URL.")
        case .shortcut:
            guard !shortcutRunning else { completion("The previous shortcut is still running."); return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", settings.target]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            process.terminationHandler = { task in
                DispatchQueue.main.async {
                    shortcutRunning = false
                    completion(task.terminationStatus == 0 ? nil : "Shortcut failed (exit \(task.terminationStatus)). Check its name and permissions in Shortcuts.")
                }
            }
            do { try process.run(); shortcutRunning = true }
            catch { completion(error.localizedDescription) }
        }
    }
}
