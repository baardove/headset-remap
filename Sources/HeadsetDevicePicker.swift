import Cocoa

final class HeadsetDevicePicker: NSStackView {
    private let picker = NSPopUpButton()
    private let onSelect: (String?) -> Void

    init(devices: [ConnectedHeadset], selectedID: String?, trailingAccessory: NSView? = nil, onSelect: @escaping (String?) -> Void) {
        self.onSelect = onSelect
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 6
        let label = NSTextField(labelWithString: "Use buttons from")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        addArrangedSubview(label)
        if let trailingAccessory {
            let spacer = NSView()
            let row = NSStackView(views: [picker, trailingAccessory, spacer])
            row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 10
            addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
            let compactWidth = picker.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 2.0 / 3.0)
            compactWidth.priority = .defaultHigh
            compactWidth.isActive = true
            picker.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
            trailingAccessory.setContentHuggingPriority(.required, for: .horizontal)
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        } else {
            addArrangedSubview(picker)
            picker.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        picker.setAccessibilityLabel("Headset used for button actions")
        picker.addItem(withTitle: "All connected headsets")
        for device in devices {
            let duplicates = devices.filter { $0.name == device.name }.count > 1
            picker.addItem(withTitle: device.name + (duplicates ? " · USB \(String(device.locationID, radix: 16))" : ""))
            picker.lastItem?.representedObject = device.id
        }
        if let selectedID {
            if let index = picker.itemArray.firstIndex(where: { $0.representedObject as? String == selectedID }) { picker.selectItem(at: index) }
            else {
                picker.addItem(withTitle: "Selected headset disconnected")
                picker.lastItem?.representedObject = selectedID
                picker.selectItem(at: picker.numberOfItems - 1)
            }
        }
        if devices.isEmpty && selectedID == nil { picker.item(at: 0)?.title = "No Jabra headset detected"; picker.isEnabled = false }
        picker.target = self; picker.action = #selector(changed)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func changed() { onSelect(picker.selectedItem?.representedObject as? String) }
}
