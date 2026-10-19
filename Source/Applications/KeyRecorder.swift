import Cocoa

final class KeyRecorder: NSButton {
    var savedTitle = "Click to set"
    var recording = false
    weak var selectionTable: NSTableView?
    var onStart: (() -> Void)?
    var onKey: ((UInt16) -> Bool)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        if !event.modifierFlags.intersection([.command, .shift]).isEmpty,
           let table = selectionTable {
            cancelRecording()
            guard window?.makeFirstResponder(table) == true else { return }
            table.mouseDown(with: event)
            return
        }
        guard window?.makeFirstResponder(self) == true else { return }
        if !recording { savedTitle = title; recording = true; onStart?() }
        title = "Press a key…"
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == KeyCode.escape { cancelRecording(); return }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers.isEmpty, keyName(event.keyCode) != nil else { NSSound.beep(); return }
        if onKey?(event.keyCode) == true {
            recording = false
            window?.makeFirstResponder(nil)
        }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        // Leave Command-S (toggle) and Command-W (close) to the menu.
        if event.modifierFlags.contains(.command), [KeyCode.s, KeyCode.w].contains(event.keyCode) { return false }
        keyDown(with: event)
        return true
    }
    func cancelRecording() {
        if recording { title = savedTitle; recording = false }
    }
    override func resignFirstResponder() -> Bool {
        cancelRecording()
        return super.resignFirstResponder()
    }
}
