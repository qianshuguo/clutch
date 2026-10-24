import Cocoa

// Both folder views use the same Return/Escape handling, including when
// focus is on the panel rather than its table.
func handleFolderKey(_ event: NSEvent, window: NSWindow?, openSelection: (() -> Void)?) -> Bool {
    if KeyCode.isReturn(event.keyCode) { openSelection?(); return true }
    if event.keyCode == KeyCode.escape { window?.cancelOperation(nil); return true }
    return false
}

final class FolderTableView: NSTableView {
    var openSelection: (() -> Void)?
    // Shows the selected folders in Finder (the menu's Reveal in Finder).
    var revealSelection: (() -> Void)?
    // The menu's Open is `openSelection`; Edit… is for one folder.
    var editSelection: (() -> Void)?
    // The picker's search field keeps focus, so a right-click does not take it.
    var focusesOnRightClick = true
    // The picker's search: returns true when the key edited the search.
    var searchKey: ((NSEvent) -> Bool)?
    override func rightMouseDown(with event: NSEvent) {
        ListSelection.selectForMenu(event, in: self, focus: focusesOnRightClick)
        super.rightMouseDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard ListSelection.selectForMenu(event, in: self, focus: focusesOnRightClick) != nil else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let open = NSMenuItem(title: "Open", action: #selector(openSelected), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let edit = NSMenuItem(title: "Edit…", action: #selector(editSelected), keyEquivalent: "")
        edit.target = self
        edit.isEnabled = selectedRowIndexes.count == 1
        menu.addItem(edit)
        menu.addItem(.separator())
        let reveal = NSMenuItem(title: "Reveal in Finder", action: #selector(revealSelected), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)
        return menu
    }
    @objc func openSelected() { openSelection?() }
    @objc func editSelected() { editSelection?() }
    @objc func revealSelected() { revealSelection?() }
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
