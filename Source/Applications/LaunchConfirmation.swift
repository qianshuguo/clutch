import Cocoa

// The Caps HUD's window (CapsOverlay). While Caps is held it never takes focus or mouse
// events; for the launch confirmation (an app that is not running) the same window
// becomes key and runs modal: Return opens, Escape / ⌘W / a click elsewhere cancels.
final class LaunchConfirmationPanel: NSPanel {
    private(set) var dismissedByOutsideClick = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private var isConfirming: Bool { NSApp.modalWindow === self }

    func resetOutsideClick() { dismissedByOutsideClick = false }

    func dismissForOutsideClick() {
        guard isConfirming else { return }
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

    override func performClose(_ sender: Any?) {
        if isConfirming { NSApp.stopModal(withCode: .cancel) }
    }
    override func cancelOperation(_ sender: Any?) { performClose(sender) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isConfirming else { return super.performKeyEquivalent(with: event) }
        if isWindowCloseShortcut(event) { performClose(nil); return true }
        guard KeyCode.isReturn(event.keyCode) else { return super.performKeyEquivalent(with: event) }
        NSApp.stopModal(withCode: .OK)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if !performKeyEquivalent(with: event) { super.keyDown(with: event) }
    }
}
