import Cocoa
import PDFKit

private final class DiagramMarkerOverlay: NSView {
    weak var viewer: PDFView?
    var markers: [(PDFPage, NSRect, Int, Bool)] = []
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let viewer else { return }
        for (page, anchor, number, selected) in markers {
            let label = convert(viewer.convert(anchor, from: page), from: viewer)
            let rect = NSRect(x: max(1, label.minX - 21), y: label.midY - 9, width: 18, height: 18)
            guard bounds.intersects(rect) else { continue }
            (selected ? NSColor.systemBlue : NSColor.darkGray).setFill()
            NSBezierPath(ovalIn: rect).fill()
            let text = String(number) as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: NSColor.white]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
        }
    }
}

private final class NumberedPDFView: PDFView {
    let numbering = DiagramMarkerOverlay()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect); numbering.viewer = self; addSubview(numbering)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout(); numbering.frame = bounds; numbering.needsDisplay = true
    }
}

/// Compact family + model tabs, used only when the actual headset model is unknown.
final class HeadsetModelTabs: NSStackView {
    var onSelect: ((HeadsetDiagramModel) -> Void)?
    private var model: HeadsetDiagramModel
    private let family = NSSegmentedControl(labels: ["Evolve2", "Evolve3"], trackingMode: .selectOne, target: nil, action: nil)
    private let variants = NSStackView()
    private let maxRowWidth: CGFloat
    private var rows: [[HeadsetDiagramModel]] = []
    init(model: HeadsetDiagramModel, maxRowWidth: CGFloat = 472) {
        self.model = model; self.maxRowWidth = maxRowWidth; super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 8
        family.target = self; family.action = #selector(familyChanged)
        family.setAccessibilityLabel("Headset series")
        variants.orientation = .vertical; variants.alignment = .leading; variants.spacing = 6
        addArrangedSubview(family); addArrangedSubview(variants)
        update(model)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(_ model: HeadsetDiagramModel) {
        self.model = model; family.selectedSegment = model.family == "Evolve2" ? 0 : 1
        for view in variants.arrangedSubviews { variants.removeArrangedSubview(view); view.removeFromSuperview() }
        let models = HeadsetDiagramModel.allCases.filter { $0.family == model.family }
        rows = []
        var current: [HeadsetDiagramModel] = []
        for candidate in models {
            let labels = (current + [candidate]).map(\.variant)
            let measure = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: nil, action: nil)
            if !current.isEmpty && measure.fittingSize.width > maxRowWidth { rows.append(current); current = [] }
            current.append(candidate)
        }
        if !current.isEmpty { rows.append(current) }
        for (index, row) in rows.enumerated() {
            let control = NSSegmentedControl(labels: row.map(\.variant), trackingMode: .selectOne, target: self, action: #selector(modelChanged(_:)))
            control.tag = index; control.selectedSegment = row.firstIndex(of: model) ?? -1
            control.setAccessibilityLabel("\(model.family) model choices, row \(index + 1)")
            variants.addArrangedSubview(control)
        }
    }
    @objc private func familyChanged() { choose(family.selectedSegment == 0 ? .evolve2 : .evolve3) }
    @objc private func modelChanged(_ sender: NSSegmentedControl) {
        guard rows.indices.contains(sender.tag), rows[sender.tag].indices.contains(sender.selectedSegment) else { return }
        choose(rows[sender.tag][sender.selectedSegment])
    }
    private func choose(_ model: HeadsetDiagramModel) { update(model); onSelect?(model) }
}

/// Original model-specific Jabra overview, with matching physical-button numbers.
final class HeadsetDiagramCard: NSStackView {
    private let heading = NSTextField(labelWithString: "")
    private let source = NSButton(title: "Jabra manual ↗", target: nil, action: nil)
    private let viewer = NumberedPDFView(frame: .zero)
    private let legend = NSStackView()
    private var model: HeadsetDiagramModel
    private var selectedID = "teams"
    private var hiddenIDs: Set<String> = []
    private var sourceURL: URL?

    init(model: HeadsetDiagramModel) {
        self.model = model; super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 12
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        source.target = self; source.action = #selector(openManual); source.isBordered = false; source.contentTintColor = .linkColor
        let titleRow = NSStackView(views: [heading, NSView(), source]); titleRow.orientation = .horizontal
        titleRow.widthAnchor.constraint(equalToConstant: 852).isActive = true
        viewer.displayMode = .singlePage; viewer.displayBox = .cropBox; viewer.autoScales = true
        viewer.displaysPageBreaks = false; viewer.backgroundColor = .white
        viewer.setAccessibilityLabel("Current headset button placement")
        viewer.widthAnchor.constraint(equalToConstant: 510).isActive = true
        viewer.heightAnchor.constraint(equalToConstant: 530).isActive = true
        legend.orientation = .vertical; legend.alignment = .leading; legend.spacing = 10
        legend.widthAnchor.constraint(equalToConstant: 310).isActive = true
        let drawingRow = NSStackView(views: [viewer, legend]); drawingRow.orientation = .horizontal; drawingRow.alignment = .top; drawingRow.spacing = 32
        addArrangedSubview(titleRow); addArrangedSubview(drawingRow)
        widthAnchor.constraint(equalToConstant: 852).isActive = true
        update(model: model, selectedID: "teams", hiddenIDs: [])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(model: HeadsetDiagramModel, selectedID: String, hiddenIDs: Set<String>) {
        let changed = self.model != model || viewer.document == nil
        self.model = model; self.selectedID = selectedID; self.hiddenIDs = hiddenIDs
        heading.stringValue = "\(model.family) · \(model.variant)"
        if changed {
            if let url = Bundle.main.url(forResource: model.assetName, withExtension: "pdf", subdirectory: "HeadsetDiagrams"), let document = PDFDocument(url: url), let page = document.page(at: 0) {
                let box = page.bounds(for: .mediaBox)
                var lower = box.minY + box.height * 0.04
                for term in ["SECURITY NOTE:", "Included accessories"] {
                    if let selection = document.findString(term, withOptions: .caseInsensitive).first {
                        lower = max(lower, selection.bounds(for: page).maxY + 8)
                    }
                }
                let upper = document.findString("Left", withOptions: .caseInsensitive).first.map { $0.bounds(for: page).maxY + 2 } ?? box.height * 0.87
                page.setBounds(NSRect(x: box.minX, y: lower, width: box.width, height: max(60, upper - lower)), for: .cropBox)
                viewer.document = document
            }
            if let url = Bundle.main.url(forResource: "sources", withExtension: "json", subdirectory: "HeadsetDiagrams"),
               let data = try? Data(contentsOf: url), let sources = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]],
               let address = sources[model.assetName]?["url"] as? String { sourceURL = URL(string: address) }
            viewer.autoScales = true
        }
        for view in legend.arrangedSubviews { legend.removeArrangedSubview(view); view.removeFromSuperview() }
        var side = ""
        viewer.numbering.markers = []
        for (index, control) in model.controls.enumerated() {
            if control.side != side {
                side = control.side
                let label = NSTextField(labelWithString: "\(side) side")
                label.font = .systemFont(ofSize: 13, weight: .semibold); legend.addArrangedSubview(label)
            }
            let hidden = control.ids.allSatisfy(hiddenIDs.contains)
            let label = NSTextField(wrappingLabelWithString: "\(index + 1). \(control.name)" + (hidden ? " · hidden" : ""))
            label.font = .systemFont(ofSize: 13, weight: control.ids.contains(selectedID) ? .semibold : .regular)
            label.textColor = control.ids.contains(selectedID) ? .controlAccentColor : hidden ? .tertiaryLabelColor : .labelColor
            label.preferredMaxLayoutWidth = 310
            label.widthAnchor.constraint(equalToConstant: 310).isActive = true
            legend.addArrangedSubview(label)
            addNumber(index + 1, to: control)
        }
        let note = NSTextField(wrappingLabelWithString: selectedID == "micArm" && !model.hasBoom
            ? "This model has built-in microphones and no microphone arm."
            : "Numbered left side first, top to bottom; then right side, top to bottom. Shared functions use the same number.")
        note.font = .systemFont(ofSize: 12); note.textColor = .secondaryLabelColor; note.preferredMaxLayoutWidth = 310
        note.widthAnchor.constraint(equalToConstant: 310).isActive = true
        legend.addArrangedSubview(note)
        viewer.addSubview(viewer.numbering, positioned: .above, relativeTo: nil)
        viewer.numbering.frame = viewer.bounds; viewer.numbering.needsDisplay = true
    }
    private func addNumber(_ number: Int, to control: HeadsetPhysicalControl) {
        guard let doc = viewer.document, let page = doc.page(at: 0) else { return }
        for term in control.terms {
            guard let selection = doc.findString(term, withOptions: .caseInsensitive).first else { continue }
            let anchor = selection.bounds(for: page)
            guard !anchor.isEmpty else { continue }
            viewer.numbering.markers.append((page, anchor, number, control.ids.contains(selectedID))); break
        }
    }
    @objc private func openManual() { if let sourceURL { NSWorkspace.shared.open(sourceURL) } }
}
