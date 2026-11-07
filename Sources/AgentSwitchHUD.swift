import Cocoa

private final class AgentHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A transient, non-activating label anchored to the menu bar item.
final class AgentSwitchHUD {
    private let panel: NSPanel
    private let title = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private var timer: Timer?

    init() {
        panel = AgentHUDPanel(contentRect: NSRect(x: 0, y: 0, width: 330, height: 94), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true; panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.title = "Headset agent changed"
        let background = NSVisualEffectView(frame: panel.contentView!.bounds)
        background.material = .popover; background.blendingMode = .behindWindow; background.state = .active
        background.wantsLayer = true; background.layer?.cornerRadius = 14; background.layer?.masksToBounds = true
        panel.contentView = background
        icon.frame = NSRect(x: 18, y: 23, width: 48, height: 48); icon.imageScaling = .scaleProportionallyUpOrDown
        title.frame = NSRect(x: 80, y: 43, width: 232, height: 31); title.font = .systemFont(ofSize: 24, weight: .semibold); title.lineBreakMode = .byTruncatingTail
        let subtitle = NSTextField(labelWithString: "Headset agent selected")
        subtitle.frame = NSRect(x: 81, y: 22, width: 230, height: 18); subtitle.font = .systemFont(ofSize: 12); subtitle.textColor = .secondaryLabelColor
        background.addSubview(icon); background.addSubview(title); background.addSubview(subtitle)
    }
    deinit { timer?.invalidate() }
    func show(_ profile: ButtonProfile, number: Int?, beside anchor: NSView?) {
        timer?.invalidate()
        title.stringValue = number.map { "\($0). \(profile.name)" } ?? profile.name
        if profile.settings.action == .openApp { icon.image = NSWorkspace.shared.icon(forFile: profile.settings.target) }
        else { icon.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil) }
        let screen = anchor?.window?.screen ?? NSScreen.main
        let available = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let anchorRect = anchor.flatMap { view in view.window?.convertToScreen(view.convert(view.bounds, to: nil)) }
        let center = anchorRect?.midX ?? available.maxX - panel.frame.width / 2 - 12
        let x = max(available.minX + 8, min(center - panel.frame.width / 2, available.maxX - panel.frame.width - 8))
        let y = min((anchorRect?.minY ?? available.maxY) - panel.frame.height - 10, available.maxY - panel.frame.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y)); panel.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: false) { [weak self] _ in self?.panel.orderOut(nil) }
    }
}
