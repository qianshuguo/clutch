import Cocoa

// A shortcut field, recorded exactly as shortcuts are used: hold Caps, press the
// key(s), release Caps. The event tap delivers those keys through capsKeyPressed and
// capsReleased; keys typed without Caps are not recorded.
final class KeyRecorder: NSButton {
    var savedTitle = "Click to set"
    var recording = false
    weak var selectionTable: NSTableView?
    var onStart: (() -> Void)?
    // Called on Caps release with the first key and, when `maxKeys` is 2, an optional second.
    var onKeys: ((UInt16, UInt16?) -> Bool)?
    // 2 for App List (Caps + M + W), 1 for window actions.
    var maxKeys = 1
    // False while HyperCaps cannot see Caps (disabled, or no Accessibility access).
    var capsAvailable: (() -> Bool)?
    private var recordedKeys: [UInt16] = []
    var recordsWithCaps: Bool { onKeys != nil }
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
        recordedKeys = []
        title = prompt
    }
    var prompt: String {
        if capsAvailable?() == false { return "Turn on HyperCaps" }
        return maxKeys > 1 ? "Hold Caps + 1 or 2 keys" : "Hold Caps + a key"
    }
    // Keys arrive here only when Caps is not held: the prompt already says what to do.
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == KeyCode.escape { cancelRecording(); return }
        NSSound.beep()
    }
    // Caps went down: show that the field is listening for the key(s).
    func capsPressed() {
        guard recording, recordsWithCaps, capsAvailable?() != false else { return }
        recordedKeys = []
        title = "Caps + …"
    }
    // A key pressed while Caps is held, in press order.
    func capsKeyPressed(_ code: UInt16) {
        guard recording, recordsWithCaps else { return }
        if code == KeyCode.escape { cancelRecording(); return }
        guard keyName(code) != nil else { NSSound.beep(); return }
        guard recordedKeys.count < maxKeys else { NSSound.beep(); return }
        recordedKeys.append(code)
        if recordedKeys.count == 1 && maxKeys > 1 {
            title = "Caps + \(keyName(code) ?? "?") + …"
        } else {
            title = shortcutTitle(recordedKeys[0], recordedKeys.count > 1 ? recordedKeys[1] : nil)
        }
    }
    // Releasing Caps saves what was pressed; Caps alone records nothing.
    func capsReleased() {
        guard recording, let onKeys = onKeys else { return }
        guard let first = recordedKeys.first else { title = prompt; return }
        let second = recordedKeys.count > 1 ? recordedKeys[1] : nil
        recordedKeys = []
        if onKeys(first, second) {
            finishRecording()
        } else if recording {
            title = prompt
        }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        // Leave Command-S (toggle) and Command-W (close) to the menu.
        if event.modifierFlags.contains(.command), [KeyCode.s, KeyCode.w].contains(event.keyCode) { return false }
        keyDown(with: event)
        return true
    }
    private func finishRecording() {
        recording = false
        recordedKeys = []
        window?.makeFirstResponder(nil)
    }
    func cancelRecording() {
        recordedKeys = []
        if recording { title = savedTitle; recording = false }
    }
    override func resignFirstResponder() -> Bool {
        cancelRecording()
        return super.resignFirstResponder()
    }
}
