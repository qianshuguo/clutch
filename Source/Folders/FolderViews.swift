import Cocoa

final class FolderTableView: NSTableView {
    var openSelection: (() -> Void)?
    // Shows the selected folders in Finder (the menu's Reveal in Finder).
    var revealSelection: (() -> Void)?
    // The menu's Open is `openSelection`; Edit… is for one folder.
    var editSelection: (() -> Void)?
    override func rightMouseDown(with event: NSEvent) {
        ListSelection.selectForMenu(event, in: self)
        super.rightMouseDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard ListSelection.selectForMenu(event, in: self) != nil else { return nil }
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
        if KeyCode.isReturn(event.keyCode) { openSelection?(); return }
        if event.keyCode == KeyCode.escape { window?.cancelOperation(nil); return }
        super.keyDown(with: event)
    }
}
