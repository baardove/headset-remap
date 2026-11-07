import Cocoa

/// Only Jabra USB HID interfaces are captured. No system keyboard hook is used.
final class InputDebugWindow: NSWindowController {
    var onActionsPaused: (() -> Void)?
    var statusProvider: (() -> String)?
    private let status = NSTextField(wrappingLabelWithString: "")
    private let actions = NSButton(checkboxWithTitle: "Run mapped actions", target: nil, action: nil)
    private let textView = NSTextView()
    private let toggle = NSButton(title: "Pause Logging", target: nil, action: nil)
    private var lines: [String] = []
    private var pending: [String] = []
    private var flushTimer: Timer?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 580),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Jabra Input Debug"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
        let info = NSTextField(wrappingLabelWithString: "Live Jabra input: VALUE shows decoded HID elements; RAW shows report IDs and bytes. Press the Teams button, then compare press and release. Logging does not stop your mapped action. Turn off Run mapped actions only for a passive test. The latest 2,000 lines are kept here; the log file rotates at 256 KB.")
        toggle.target = self; toggle.action = #selector(toggleCapture)
        actions.target = self; actions.action = #selector(toggleActions)
        actions.state = AppConfig.inputMode.actionsEnabled ? .on : .off
        let clear = NSButton(title: "Clear", target: self, action: #selector(clearLog))
        let copy = NSButton(title: "Copy Log", target: self, action: #selector(copyLog))
        let save = NSButton(title: "Save Log…", target: self, action: #selector(saveLog))
        let buttons = NSStackView(views: [toggle, actions, clear, copy, save])
        buttons.orientation = .horizontal; buttons.spacing = 10
        textView.isEditable = false; textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.documentView = textView; scroll.borderType = .bezelBorder
        textView.autoresizingMask = [.width]
        let stack = NSStackView(views: [info, buttons, status, scroll])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20),
            info.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosing),
                                               name: NSWindow.willCloseNotification, object: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { flushTimer?.invalidate(); NotificationCenter.default.removeObserver(self) }

    func present() {
        AppConfig.inputMode.tracingEnabled = true
        toggle.title = "Pause Logging"
        AppLog.onLine = { [weak self] line in self?.append(line) }
        if flushTimer == nil {
            flushTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.flush() }
        }
        showWindow(nil); NSApp.activate(ignoringOtherApps: true)
        AppLog.log("--- input logging started; mapped actions \(AppConfig.inputMode.actionsEnabled ? "enabled" : "paused") ---")
    }
    private func append(_ line: String) {
        // Bound pending data too, even during a resize or modal panel.
        pending.append(line)
        if pending.count > 2000 { pending.removeFirst(pending.count - 2000) }
    }
    private func flush() {
        status.stringValue = statusProvider?() ?? ""
        guard !pending.isEmpty else { return }
        lines.append(contentsOf: pending); pending.removeAll(keepingCapacity: true)
        if lines.count > 2000 { lines.removeFirst(lines.count - 2000) }
        textView.string = lines.joined()
        textView.scrollToEndOfDocument(nil)
    }
    @objc private func toggleCapture() {
        AppConfig.inputMode.tracingEnabled.toggle()
        toggle.title = AppConfig.inputMode.tracingEnabled ? "Pause Logging" : "Resume Logging"
        AppLog.log(AppConfig.inputMode.tracingEnabled ? "--- input logging resumed (action setting unchanged) ---" : "--- input logging paused (action setting unchanged) ---")
    }
    @objc private func toggleActions() {
        AppConfig.inputMode.actionsEnabled = actions.state == .on
        if !AppConfig.inputMode.actionsEnabled { onActionsPaused?() }
        AppLog.log(AppConfig.inputMode.actionsEnabled ? "--- mapped actions enabled ---" : "--- mapped actions paused; input logging unchanged ---")
    }
    @objc private func clearLog() { lines.removeAll(); pending.removeAll(); textView.string = "" }
    @objc private func copyLog() {
        flush(); NSPasteboard.general.clearContents(); NSPasteboard.general.setString(textView.string, forType: .string)
    }
    @objc private func saveLog() {
        flush()
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Jabra-Input-Debug.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try textView.string.write(to: url, atomically: true, encoding: .utf8) }
        catch { let alert = NSAlert(error: error); alert.runModal() }
    }
    @objc private func windowClosing() {
        AppConfig.inputMode.tracingEnabled = AppConfig.debug
        AppConfig.inputMode.actionsEnabled = true
        actions.state = .on
        AppLog.log("Debug window closed; mapped actions enabled")
        AppLog.onLine = nil
        flushTimer?.invalidate(); flushTimer = nil
    }
}
