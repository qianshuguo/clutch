import Cocoa

// Keep the label cell's geometry while using AppKit's field editor for renaming.
final class FolderNameField: NSTextField, NSTextFieldDelegate {
    static weak var active: FolderNameField?
    weak var folderTable: NSTableView?
    var onRename: ((String) -> Void)?
    private var originalName = ""

    override func draw(_ dirtyRect: NSRect) {
        // A native cell border adds insets and shifts the field editor in this label-sized frame.
        // Draw the editing chrome separately so display and editing share the same baseline.
        if isEditable {
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            NSColor.textBackgroundColor.setFill()
            outline.fill()
            NSColor.keyboardFocusIndicatorColor.setStroke()
            outline.lineWidth = 1
            outline.stroke()
        }
        super.draw(dirtyRect)
    }

    @objc func beginRename() {
        guard !isEditable else { return }
        Self.active?.finishRename(cancelled: false)
        Self.active = self
        originalName = stringValue
        delegate = self
        isEditable = true
        isSelectable = true
        // Keep the cell borderless; its native border would change the text insets.
        needsDisplay = true
        selectText(nil)
    }

    func finishRename(cancelled: Bool) {
        guard isEditable else { return }
        let proposed = (currentEditor()?.string ?? stringValue).trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cancelled || proposed.isEmpty ? originalName : proposed
        isEditable = false
        if Self.active === self { Self.active = nil }
        isSelectable = false
        needsDisplay = true
        stringValue = name
        window?.makeFirstResponder(folderTable)
        if name != originalName { onRename?(name) }
    }

    func controlTextDidEndEditing(_ notification: Notification) { finishRename(cancelled: false) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finishRename(cancelled: true)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            finishRename(cancelled: false)
            return true
        }
        return false
    }
}

// Both folder views use the same Return/Escape handling, including when
// focus is on the panel rather than its table.
func handleFolderKey(_ event: NSEvent, window: NSWindow?, openSelection: (() -> Void)?) -> Bool {
    if KeyCode.isReturn(event.keyCode) { openSelection?(); return true }
    if event.keyCode == KeyCode.escape { window?.cancelOperation(nil); return true }
    return false
}

final class FolderTableView: NSTableView {
    var openSelection: (() -> Void)?
    // The picker's search: returns true when the key edited the search.
    var searchKey: ((NSEvent) -> Bool)?
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        if !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        guard let cell = view(atColumn: 0, row: row, makeIfNecessary: true),
              let field = cell.subviews.first(where: { $0 is FolderNameField }) as? FolderNameField else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let rename = NSMenuItem(title: "Rename", action: #selector(FolderNameField.beginRename), keyEquivalent: "")
        rename.target = field
        rename.isEnabled = selectedRowIndexes.count == 1
        menu.addItem(rename)
        return menu
    }
    override func flagsChanged(with event: NSEvent) { window?.flagsChanged(with: event) }
    override func keyDown(with event: NSEvent) {
        if searchKey?(event) == true { return }
        if !handleFolderKey(event, window: window, openSelection: openSelection) {
            super.keyDown(with: event)
        }
    }
}

final class FolderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var previousFocus: PreviousFocus?
    override func performClose(_ sender: Any?) {
        guard attachedSheet == nil else { return }
        close()
        previousFocus?.restore()
    }
    var openSelection: (() -> Void)?
    var selectNumber: ((Int) -> Void)?
    override func resignKey() {
        super.resignKey()
        if isVisible, attachedSheet == nil { close() }
    }
    override func cancelOperation(_ sender: Any?) {
        if isKeyWindow, attachedSheet == nil { performClose(sender) }
    }

    override func keyDown(with event: NSEvent) {
        if !handleFolderKey(event, window: self, openSelection: openSelection) {
            super.keyDown(with: event)
        }
    }
}
