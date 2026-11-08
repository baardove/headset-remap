import Cocoa

private final class ButtonDebugDocument: NSView { override var isFlipped: Bool { true } }

/// Reversible, model-specific exclusions. This never deletes learned mappings.
final class ButtonDebugWindow: NSWindowController {
    var onChange: ((HeadsetDiagramModel) -> Void)?
    var onLiveInput: (() -> Void)?
    var canChange: (() -> Bool)?
    private var model: HeadsetDiagramModel
    private var allButtons: [HeadsetButton]
    private var buttons: [HeadsetButton] { model.ordered(allButtons) }
    private let picker: HeadsetModelTabs
    private let list = NSStackView()
    private let root = NSStackView()
    private let contentDocument = ButtonDebugDocument()
    private let scroll = NSScrollView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private var toggles: [NSButton] = []
    private let pairing = NSTextField(labelWithString: "")

    init(model: HeadsetDiagramModel, buttons: [HeadsetButton]) {
        self.model = model; self.allButtons = buttons; picker = HeadsetModelTabs(model: model)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Headset Remap · Button debug"; window.isReleasedWhenClosed = false
        super.init(window: window); window.center()
        let heading = NSTextField(labelWithString: "Button debug")
        heading.font = .systemFont(ofSize: 23, weight: .semibold)
        picker.onSelect = { [weak self] chosen in
            guard let self else { return }
            self.update(model: chosen, buttons: self.allButtons); self.status.stringValue = ""
        }
        let help = NSTextField(wrappingLabelWithString: "Checked buttons are shown in configuration and can trigger mapped actions. Uncheck a button to hide and disable its mapping for this headset model, across all agents. Its saved inputs and actions are kept.")
        let note = NSTextField(wrappingLabelWithString: "A physical control is not necessarily mappable. Test it with Learn input or Live input before deciding. Factory headset functions are unaffected.")
        for field in [help, note, status] {
            field.preferredMaxLayoutWidth = 472
            field.widthAnchor.constraint(equalToConstant: 472).isActive = true
        }
        help.textColor = .secondaryLabelColor; note.textColor = .secondaryLabelColor; note.font = .systemFont(ofSize: 12)
        pairing.font = .systemFont(ofSize: 12); pairing.textColor = .secondaryLabelColor
        list.orientation = .vertical; list.alignment = .leading; list.spacing = 12
        contentDocument.addSubview(list); scroll.documentView = contentDocument; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.heightAnchor.constraint(equalToConstant: 240).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 472).isActive = true
        let live = NSButton(title: "Live input…", target: self, action: #selector(showLiveInput))
        let done = NSButton(title: "Done", target: self, action: #selector(finish))
        let actions = NSStackView(views: [live, NSView(), done]); actions.orientation = .horizontal
        actions.widthAnchor.constraint(equalToConstant: 472).isActive = true
        for item in [heading, picker, pairing, help, scroll, note, actions, status] { root.addArrangedSubview(item) }
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)
        ])
        update(model: model, buttons: buttons)
        window.contentView!.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 520, height: root.fittingSize.height + 48))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present() { showWindow(nil); NSApp.activate(ignoringOtherApps: true) }
    func update(model: HeadsetDiagramModel, buttons: [HeadsetButton]) {
        self.model = model; self.allButtons = buttons
        picker.update(model)
        pairing.stringValue = "Settings for \(model.title). Numbers match the physical controls."
        for item in list.arrangedSubviews { list.removeArrangedSubview(item); item.removeFromSuperview() }
        toggles = []
        let availability = ButtonAvailability.load()
        for (index, button) in self.buttons.enumerated() {
            let title = (model.number(for: button.id).map { "\($0). " } ?? "") + button.name
            let toggle = NSButton(checkboxWithTitle: title, target: self, action: #selector(availabilityChanged(_:)))
            toggle.tag = index; toggle.state = availability.isAvailable(button.id, model: model) ? .on : .off
            toggle.toolTip = "Show and enable \(button.name) mappings for \(model.title)"
            toggle.widthAnchor.constraint(equalToConstant: 220).isActive = true
            let learned = !button.settings.learnedSignals.isEmpty
            let detail = NSTextField(labelWithString: learned ? "Input learned" : "Input not learned")
            detail.font = .systemFont(ofSize: 11); detail.textColor = .secondaryLabelColor
            let row = NSStackView(views: [toggle, detail]); row.orientation = .horizontal; row.spacing = 12
            list.addArrangedSubview(row); toggles.append(toggle)
        }
        list.layoutSubtreeIfNeeded()
        let height = max(240, list.fittingSize.height)
        list.setFrameSize(NSSize(width: 472, height: height)); contentDocument.setFrameSize(NSSize(width: 472, height: height))
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.setContentSize(NSSize(width: 520, height: root.fittingSize.height + 48))
    }
    @objc private func availabilityChanged(_ sender: NSButton) {
        guard buttons.indices.contains(sender.tag) else { return }
        guard canChange?() != false else { sender.state = sender.state == .on ? .off : .on; return }
        let button = buttons[sender.tag]
        var availability = ButtonAvailability.load()
        availability.setAvailable(sender.state == .on, id: button.id, model: model)
        do {
            try availability.save()
            status.stringValue = "\(button.name) \(sender.state == .on ? "restored" : "hidden and disabled") for \(model.title)."
            onChange?(model)
        } catch { status.stringValue = error.localizedDescription; update(model: model, buttons: allButtons) }
    }
    @objc private func showLiveInput() { onLiveInput?() }
    @objc private func finish() { close() }
}
