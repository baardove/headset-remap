import Cocoa

/// Everyday controls; technical setup stays in the settings window.
final class ProfilePopover: NSViewController {
    var onSelect: ((UUID) -> Void)?
    var onSelectDevice: ((String?) -> Void)?
    var onSecondaryRun: ((UUID, UUID) -> Void)?
    var onActions: ((UUID) -> Void)?
    var onRun: ((UUID) -> Void)?
    var onSettings: (() -> Void)?
    var onConfiguration: (() -> Void)?
    private let stack = NSStackView()
    private var library: ButtonProfileLibrary
    private var connection: String
    private var devices: [ConnectedHeadset]
    private var selectedDeviceID: String?

    init(library: ButtonProfileLibrary, connection: String, devices: [ConnectedHeadset], selectedDeviceID: String?) {
        self.library = library; self.connection = connection; self.devices = devices; self.selectedDeviceID = selectedDeviceID
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 334, height: 360))
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])
        rebuild()
    }
    func update(library: ButtonProfileLibrary, connection: String, devices: [ConnectedHeadset], selectedDeviceID: String?) {
        self.library = library; self.connection = connection; self.devices = devices; self.selectedDeviceID = selectedDeviceID
        if isViewLoaded { rebuild() }
    }
    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.lineBreakMode = .byTruncatingTail
        return field
    }
    private func row(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views); row.orientation = .horizontal; row.spacing = 10; row.alignment = .centerY
        return row
    }
    private func fullWidth(_ item: NSView) {
        stack.addArrangedSubview(item)
        item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func separator() { let line = NSBox(); line.boxType = .separator; fullWidth(line) }
    private func rebuild() {
        for child in stack.arrangedSubviews { stack.removeArrangedSubview(child); child.removeFromSuperview() }
        let icon = NSImageView(image: NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)!)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 27, weight: .regular)
        let heading = NSStackView(views: [label("Headset Remap", size: 20, weight: .semibold), label(connection, secondary: true)])
        heading.orientation = .vertical; heading.alignment = .leading; heading.spacing = 3
        fullWidth(row([icon, heading]))
        fullWidth(HeadsetDevicePicker(devices: devices, selectedID: selectedDeviceID, onSelect: { [weak self] id in self?.onSelectDevice?(id) }))
        separator()
        stack.addArrangedSubview(label("HEADSET USES", size: 11, weight: .medium, secondary: true))
        for (index, profile) in library.enabledProfiles.enumerated() {
            let selected = profile.id == library.activeID
            let button = NSButton(title: (selected ? "✓  " : "    ") + library.displayName(profile), target: self, action: #selector(selectProfile(_:)))
            button.tag = index; button.bezelStyle = .rounded; button.isBordered = selected
            button.contentTintColor = selected ? .controlAccentColor : .labelColor
            button.alignment = .left; button.font = .systemFont(ofSize: 15, weight: selected ? .semibold : .regular)
            button.setAccessibilityLabel("Use \(profile.name) for headset")
            button.setAccessibilityValue(selected ? "Selected" : "")
            if selected { button.bezelColor = NSColor.controlAccentColor.withAlphaComponent(0.12) }
            button.widthAnchor.constraint(equalToConstant: 236).isActive = true
            let shortcut = label(profile.activateShortcut?.label ?? "", secondary: true)
            shortcut.widthAnchor.constraint(equalToConstant: 64).isActive = true
            let line = row([button, shortcut])
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            fullWidth(line)
        }
        let description = label("Teams button → \(actionDescription(library.active.settings))", secondary: true)
        fullWidth(description)
        let run = NSButton(title: "Open \(library.active.name) now", target: self, action: #selector(runActive))
        run.bezelStyle = .rounded; run.bezelColor = .controlAccentColor
        run.font = .systemFont(ofSize: 14, weight: .semibold)
        run.toolTip = library.active.runShortcut.map { "Run directly: \($0.label)" }
        let otherActions = NSPopUpButton(frame: .zero, pullsDown: true)
        otherActions.addItem(withTitle: "")
        otherActions.widthAnchor.constraint(equalToConstant: 32).isActive = true
        run.widthAnchor.constraint(equalToConstant: 268).isActive = true
        otherActions.setAccessibilityLabel("Run another profile action")
        for profile in library.enabledProfiles {
            let group = NSMenuItem(title: library.displayName(profile), action: nil, keyEquivalent: "")
            let menu = NSMenu()
            let open = NSMenuItem(title: "Open", action: #selector(runOther(_:)), keyEquivalent: "")
            open.target = self; open.representedObject = profile.id.uuidString; menu.addItem(open)
            for action in profile.secondaryActions ?? [] {
                let item = NSMenuItem(title: action.name + (action.isConfigured ? "" : " (set up)"), action: action.isConfigured ? #selector(runSecondary(_:)) : nil, keyEquivalent: "")
                item.target = self; item.representedObject = [profile.id.uuidString, action.id.uuidString]; menu.addItem(item)
            }
            menu.addItem(.separator())
            let configure = NSMenuItem(title: "Configure actions…", action: #selector(configureActions(_:)), keyEquivalent: "")
            configure.target = self; configure.representedObject = profile.id.uuidString; menu.addItem(configure)
            group.submenu = menu; otherActions.menu?.addItem(group)
        }
        run.setContentHuggingPriority(.defaultLow, for: .horizontal)
        fullWidth(row([run, otherActions])); separator()
        let settings = NSButton(title: "Open launcher…", target: self, action: #selector(showSettings)); settings.bezelStyle = .inline
        let advanced = NSButton(title: "Configuration…", target: self, action: #selector(showConfiguration)); advanced.bezelStyle = .inline
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        fullWidth(row([settings, spacer, advanced]))
        view.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(width: 334, height: stack.fittingSize.height + 24)
    }
    private func actionDescription(_ settings: ButtonSettings) -> String {
        switch settings.action {
        case .agentAction: return "Run agent action"
        case .none: return "No action"
        case .openURL: return "Open \(URL(string: settings.target)?.host ?? "URL")"
        case .openApp: return "Open \(Bundle(path: settings.target)?.bundleIdentifier == "com.openai.codex" ? "Codex" : URL(fileURLWithPath: settings.target).deletingPathExtension().lastPathComponent)"
        case .shortcut: return "Run \(settings.target)"
        }
    }
    @objc private func selectProfile(_ sender: NSButton) {
        guard library.enabledProfiles.indices.contains(sender.tag) else { return }
        onSelect?(library.enabledProfiles[sender.tag].id)
    }
    @objc private func runOther(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String, let id = UUID(uuidString: value) { onRun?(id) }
    }
    @objc private func runSecondary(_ sender: NSMenuItem) {
        guard let ids = sender.representedObject as? [String], let profile = UUID(uuidString: ids[0]), let action = UUID(uuidString: ids[1]) else { return }
        onSecondaryRun?(profile, action)
    }
    @objc private func configureActions(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value) else { return }
        onActions?(id)
    }
    @objc private func runActive() { onRun?(library.activeID) }
    @objc private func showSettings() { onSettings?() }
    @objc private func showConfiguration() { onConfiguration?() }
}
