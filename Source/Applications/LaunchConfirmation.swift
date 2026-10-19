import Cocoa

final class LaunchConfirmationPanel: NSPanel {
    private(set) var dismissedByOutsideClick = false

    func dismissForOutsideClick() {
        guard NSApp.modalWindow === self else { return }
        dismissedByOutsideClick = true
        NSApp.stopModal(withCode: .cancel)
        // Wake the modal event loop even when the click belongs to another app.
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windowNumber, context: nil, subtype: 0, data1: 0, data2: 0) {
            NSApp.postEvent(event, atStart: true)
        }
    }

    override func resignKey() {
        super.resignKey()
        dismissForOutsideClick()
    }

    override func performClose(_ sender: Any?) { NSApp.stopModal(withCode: .cancel) }
    override func cancelOperation(_ sender: Any?) { performClose(sender) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isWindowCloseShortcut(event) { performClose(nil); return true }
        guard KeyCode.isReturn(event.keyCode) else { return super.performKeyEquivalent(with: event) }
        NSApp.stopModal(withCode: .OK)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if !performKeyEquivalent(with: event) { super.keyDown(with: event) }
    }
}

final class LaunchConfirmation: NSObject {
    private let panel = LaunchConfirmationPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 88),
                                styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)

    func run(appName: String) -> Bool {
        let previousFocus = PreviousFocus()
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        guard let content = panel.contentView else { return false }
        let label = NSTextField(wrappingLabelWithString: "Open \(appName)?")
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24)
        ])
        panel.center()
        NSApp.activateFromBackground()
        panel.makeKeyAndOrderFront(nil)
        let mouseDowns: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDowns) { [weak panel] event in
            if let panel = panel, event.window !== panel { panel.dismissForOutsideClick() }
            return event
        }
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDowns) { [weak panel] _ in
            panel?.dismissForOutsideClick()
        }
        let confirmed = NSApp.runModal(for: panel) == .OK
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        panel.orderOut(nil)
        if !confirmed, !panel.dismissedByOutsideClick {
            previousFocus.restore()
        }
        return confirmed
    }

}
