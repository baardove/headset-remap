import Cocoa

final class ConfigurationSection: NSStackView {
    init(_ title: String, views: [NSView]) {
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 14
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 16, weight: .semibold)
        let divider = NSBox(); divider.boxType = .separator
        addArrangedSubview(heading); addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        for view in views { addArrangedSubview(view) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Optional controls are present, but closed until the user asks for them.
final class ConfigurationDisclosure: NSStackView {
    var onToggle: (() -> Void)?
    private let title: String
    private let toggle = NSButton()
    private let body = NSStackView()
    init(_ title: String, views: [NSView]) {
        self.title = title
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 14; detachesHiddenViews = true
        toggle.title = "▸ " + title; toggle.isBordered = false; toggle.alignment = .left
        toggle.font = .systemFont(ofSize: 14, weight: .semibold)
        toggle.target = self; toggle.action = #selector(changeExpansion)
        toggle.setAccessibilityLabel(title); toggle.setAccessibilityValue("Collapsed")
        body.orientation = .vertical; body.alignment = .leading; body.spacing = 14
        for view in views { body.addArrangedSubview(view) }
        body.isHidden = true
        addArrangedSubview(toggle); addArrangedSubview(body)
        toggle.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        body.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func changeExpansion() {
        body.isHidden.toggle()
        toggle.title = (body.isHidden ? "▸ " : "▾ ") + title
        toggle.setAccessibilityValue(body.isHidden ? "Collapsed" : "Expanded")
        onToggle?()
    }
}

/// A consistent way back from every setup screen.
final class ConfigurationNavigation: NSStackView {
    private let onBack: () -> Void

    init(section: String, backTitle: String = "Configuration", onBack: @escaping () -> Void) {
        self.onBack = onBack
        super.init(frame: .zero)
        orientation = .horizontal; alignment = .centerY; spacing = 12
        let back = NSButton(title: backTitle, target: self, action: #selector(goBack))
        let chevronStyle = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        back.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)?
            .withSymbolConfiguration(chevronStyle)
        back.image?.isTemplate = false
        back.imagePosition = .imageLeading
        back.bezelStyle = .rounded
        back.bezelColor = .systemBlue
        back.contentTintColor = .white
        back.controlSize = .regular
        back.font = .systemFont(ofSize: 16, weight: .medium)
        back.attributedTitle = NSAttributedString(string: back.title, attributes: [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white
        ])
        back.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        back.setAccessibilityLabel("Back to \(backTitle)")
        let location = NSTextField(labelWithString: section)
        location.font = .systemFont(ofSize: 16); location.textColor = .secondaryLabelColor
        addArrangedSubview(back); addArrangedSubview(location)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func goBack() { onBack() }
}

final class ConfigurationWindow: NSWindowController {
    var onLauncher: (() -> Void)?
    var onAgents: (() -> Void)?
    var onButtons: (() -> Void)?
    var onAdvanced: (() -> Void)?
    var onDebug: (() -> Void)?
    private let current = NSTextField(labelWithString: "")
    private let root = NSStackView()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Headset Remap · Configuration"; window.isReleasedWhenClosed = false
        super.init(window: window); window.center()
        let heading = NSTextField(labelWithString: "Configuration")
        heading.font = .systemFont(ofSize: 25, weight: .semibold)
        let intro = text("Set up what your headset does. Changes are saved inside each section.")
        current.font = .systemFont(ofSize: 12); current.textColor = .secondaryLabelColor
        let everyday = ConfigurationSection("Everyday setup", views: [
            destination("Agents & actions…", detail: "Choose apps, enable agents, and set what happens after an agent opens.", action: #selector(agents)),
            destination("Headset buttons…", detail: "Learn physical buttons and assign an extra action for each agent.", action: #selector(buttons))
        ])
        let optional = ConfigurationDisclosure("Advanced & troubleshooting", views: [
            destination("Advanced settings…", detail: "Edit keyboard shortcuts, activation timing, and Teams compatibility.", action: #selector(advanced)),
            destination("Input diagnostics…", detail: "Troubleshoot a button that is not detected. Shows live input and logs.", action: #selector(debug))
        ])
        optional.onToggle = { [weak self] in self?.resizeToContent() }
        for view in [
            ConfigurationNavigation(section: "Setup", backTitle: "Launcher", onBack: { [weak self] in self?.onLauncher?() }),
            heading, intro, current, everyday, optional
        ] { root.addArrangedSubview(view) }
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 24
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)
        ])
        for item in root.arrangedSubviews { item.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present(agent: String) {
        current.stringValue = "Headset currently uses: \(agent)"
        resizeToContent()
        showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func resizeToContent() {
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.setContentSize(NSSize(width: 780, height: root.fittingSize.height + 52))
    }
    private func text(_ value: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.textColor = .secondaryLabelColor; label.preferredMaxLayoutWidth = 724
        return label
    }
    private func destination(_ title: String, detail: String, action: Selector) -> NSStackView {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        let stack = NSStackView(views: [button, text(detail)])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        return stack
    }
    @objc private func agents() { onAgents?() }
    @objc private func buttons() { onButtons?() }
    @objc private func advanced() { onAdvanced?() }
    @objc private func debug() { onDebug?() }
}
