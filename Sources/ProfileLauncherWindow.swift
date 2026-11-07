import Cocoa

private final class LauncherDocument: NSView { override var isFlipped: Bool { true } }

final class ProfileLauncherWindow: NSWindowController {
    var onSelect: ((UUID) -> Void)?
    var onSelectDevice: ((String?) -> Void)?
    var onRun: ((UUID) -> Void)?
    var onSettings: (() -> Void)?
    private let stack = NSStackView()
    private let content = LauncherDocument()
    private let scroll = NSScrollView()
    private var library: ButtonProfileLibrary
    private var connection: String
    private var devices: [ConnectedHeadset]
    private var selectedDeviceID: String?

    init(library: ButtonProfileLibrary, connection: String, devices: [ConnectedHeadset], selectedDeviceID: String?) {
        self.library = library; self.connection = connection; self.devices = devices; self.selectedDeviceID = selectedDeviceID
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 530, height: 530),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Headset Remap"; window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
        scroll.frame = window.contentView!.bounds; scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true; scroll.scrollerStyle = .overlay; scroll.drawsBackground = false
        content.frame = scroll.bounds; scroll.documentView = content
        window.contentView!.addSubview(scroll)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24)
        ])
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(library: ButtonProfileLibrary, connection: String, devices: [ConnectedHeadset], selectedDeviceID: String?) {
        self.library = library; self.connection = connection; self.devices = devices; self.selectedDeviceID = selectedDeviceID
        rebuild()
    }
    func present() { showWindow(nil); NSApp.activate(ignoringOtherApps: true) }
    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight); field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.lineBreakMode = .byTruncatingTail
        return field
    }
    private func fullWidth(_ item: NSView) {
        stack.addArrangedSubview(item); item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func separator() { let line = NSBox(); line.boxType = .separator; fullWidth(line) }
    private func rebuild() {
        for child in stack.arrangedSubviews { stack.removeArrangedSubview(child); child.removeFromSuperview() }
        let icon = NSImageView(image: NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)!)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 36, weight: .light)
        let header = NSStackView(views: [icon, label("Launcher", size: 25, weight: .semibold), label(connection, secondary: true)])
        header.orientation = .vertical; header.alignment = .centerX; header.spacing = 10
        fullWidth(header)
        let purpose = label("Choose which agent your headset uses, or open an app now.", size: 12, secondary: true)
        fullWidth(purpose)
        let configure = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Open configuration")!,
                                 target: self, action: #selector(showSettings))
        configure.bezelStyle = .rounded
        configure.toolTip = "Open configuration"
        configure.setAccessibilityLabel("Open configuration")
        configure.widthAnchor.constraint(equalToConstant: 36).isActive = true
        fullWidth(HeadsetDevicePicker(devices: devices, selectedID: selectedDeviceID, trailingAccessory: configure, onSelect: { [weak self] id in self?.onSelectDevice?(id) }))
        separator()
        for (index, profile) in library.enabledProfiles.enumerated() {
            let selected = profile.id == library.activeID
            let select = NSButton(radioButtonWithTitle: "", target: self, action: #selector(selectProfile(_:)))
            select.tag = index; select.state = selected ? .on : .off
            select.setAccessibilityLabel("Use \(profile.name) for headset")
            let image: NSImage
            if profile.settings.action == .openApp { image = NSWorkspace.shared.icon(forFile: profile.settings.target) }
            else { image = NSImage(systemSymbolName: profile.settings.action == .shortcut ? "command" : "globe", accessibilityDescription: nil)! }
            let appIcon = NSImageView(image: image); appIcon.imageScaling = .scaleProportionallyUpOrDown
            appIcon.widthAnchor.constraint(equalToConstant: 32).isActive = true
            appIcon.heightAnchor.constraint(equalToConstant: 32).isActive = true
            let name = label(library.displayName(profile), size: 17, weight: .semibold)
            name.toolTip = profile.name
            let titleRow = NSStackView(views: [name]); titleRow.orientation = .horizontal; titleRow.spacing = 8
            if selected {
                let badge = label("Selected", size: 10, weight: .medium)
                badge.textColor = .controlAccentColor; titleRow.addArrangedSubview(badge)
            }
            let details = label(actionDescription(profile.settings), secondary: true)
            let names = NSStackView(views: [titleRow, details]); names.orientation = .vertical; names.alignment = .leading; names.spacing = 3
            names.widthAnchor.constraint(equalToConstant: 158).isActive = true
            details.widthAnchor.constraint(lessThanOrEqualToConstant: 158).isActive = true
            let key = label(profile.runShortcut?.label ?? "", size: 11, secondary: true)
            key.widthAnchor.constraint(equalToConstant: 52).isActive = true
            let run = NSButton(image: NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Run \(profile.name)")!, target: self, action: #selector(runProfile(_:)))
            run.bezelStyle = .rounded; run.tag = index; run.toolTip = "Open \(profile.name) now. Does not run the headset’s follow-up actions."
            run.setAccessibilityLabel("Run \(profile.name)")
            let row = NSStackView(views: [select, appIcon, names, key, run])
            row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 10
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            fullWidth(row); separator()
        }
        let followUps = library.active.automaticActions.map(\.name)
        let headsetFlow = (["Open \(library.active.name)"] + followUps).joined(separator: " → ")
        let help = label("Headset button: \(headsetFlow)", size: 12, secondary: true)
        help.toolTip = headsetFlow
        fullWidth(help)
        content.layoutSubtreeIfNeeded()
        let height = stack.fittingSize.height + 48
        let limit = (window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 850
        window?.setContentSize(NSSize(width: 530, height: min(height, limit - 100)))
        content.setFrameSize(NSSize(width: 530, height: height))
    }
    private func actionDescription(_ settings: ButtonSettings) -> String {
        switch settings.action {
        case .agentAction: return "Run agent action"
        case .none: return "No action assigned"
        case .openApp: return "Open \(Bundle(path: settings.target)?.bundleIdentifier == "com.openai.codex" ? "Codex" : URL(fileURLWithPath: settings.target).deletingPathExtension().lastPathComponent)"
        case .openURL: return "Open \(URL(string: settings.target)?.host ?? "URL")"
        case .shortcut: return "Run \(settings.target)"
        }
    }
    @objc private func selectProfile(_ sender: NSButton) {
        guard library.enabledProfiles.indices.contains(sender.tag) else { return }
        onSelect?(library.enabledProfiles[sender.tag].id)
        rebuild()
    }
    @objc private func runProfile(_ sender: NSButton) {
        guard library.enabledProfiles.indices.contains(sender.tag) else { return }
        onRun?(library.enabledProfiles[sender.tag].id)
    }
    @objc private func showSettings() { onSettings?() }
}
