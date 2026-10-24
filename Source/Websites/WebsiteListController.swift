import Cocoa

// Preferences > Websites: the App List layout with websites on the left and their Caps
// shortcut on the right, in `owner.websites` order. Each row shows the name, or the address it
// matches when it has none; pointing at a row shows the full address. Return opens the selected
// websites; double-click or Edit… in the context menu changes the name and URL. Retained by AppDelegate with the preferences view tree.
final class WebsiteListController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    unowned let owner: AppDelegate
    let table = WebsiteTableView()
    weak var emptyLabel: NSTextField?
    // Every row shows the default browser's icon: that is where the page opens.
    // Looked up once per reload, not for every row.
    private var icon: NSImage?

    init(owner: AppDelegate) {
        self.owner = owner
        super.init()
        table.delegate = self
        table.dataSource = self
        table.allowsMultipleSelection = true
        // Typing jumps to a website by name; shortcut fields take no part.
        table.allowsTypeSelect = true
        table.target = self
        table.doubleAction = #selector(doubleClick)
        table.editSelection = { [weak self] in self?.editSelected() }
        table.openSelection = { [weak self] in
            guard let self = self else { return }
            self.owner.openWebsites(self.table.selectedRowIndexes)
        }
    }

    // Double-click edits the website, like Folders in Settings.
    @objc private func doubleClick() {
        // Shortcut fields take their own clicks.
        guard owner.websites.indices.contains(table.clickedRow) else { return }
        owner.editWebsite(at: table.clickedRow)
    }
    private func editSelected() {
        guard table.selectedRowIndexes.count == 1, let row = table.selectedRowIndexes.first else { return }
        owner.editWebsite(at: row)
    }

    func reload() {
        icon = WebsiteEntry.browserIcon
        table.reloadData()
        emptyLabel?.isHidden = !owner.websites.isEmpty
    }
    func reveal(websiteAt index: Int) {
        guard owner.websites.indices.contains(index) else { return }
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        table.scrollRowToVisible(index)
    }

    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
        // Keep click/keyboard selection, but do not extend it by sweeping the mouse.
        ListSelection.proposed(proposedSelectionIndexes, in: tableView)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { owner.websites.count }
    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        if let column = tableColumn, tableView.tableColumns.firstIndex(of: column) != 0 { return nil }
        return owner.websites.indices.contains(row) ? owner.websites[row].name : nil
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        InsetListRowView()
    }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard owner.websites.indices.contains(row) else { return nil }
        let columnIndex = column.flatMap { tableView.tableColumns.firstIndex(of: $0) } ?? 0
        let cellWidth = tableView.frameOfCell(atColumn: columnIndex, row: row).width
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: cellWidth, height: AppDelegate.appRowHeight))
        let site = owner.websites[row]
        if columnIndex == 0 {
            let image = NSImageView(frame: AppDelegate.listIconFrame)
            image.imageScaling = .scaleProportionallyUpOrDown
            image.image = icon ?? WebsiteEntry.browserIcon
            cell.addSubview(image)
            let name = NSTextField(labelWithString: site.name)
            owner.configureListName(name, width: cellWidth)
            cell.addSubview(name)
            // Pointing at the row shows the full address that opens, and whether its
            // subdomains count.
            let includes = site.scope?.includesSubdomains ?? false
            let tip = includes ? site.url + "\nIncluding subdomains" : site.url
            cell.toolTip = tip
            name.toolTip = tip
            return cell
        }
        owner.addShortcutRecorder(to: cell, width: cellWidth, for: .website(url: site.url),
                                  keys: site.keys, table: tableView, row: row)
        return cell
    }
}

// The Websites table: Return opens the selection, and the context menu has Open and
// Edit…, like Folders. Right-clicking a website selects it first, like Finder.
final class WebsiteTableView: NSTableView {
    var openSelection: (() -> Void)?
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
        return menu
    }
    @objc func openSelected() { openSelection?() }
    @objc func editSelected() { editSelection?() }
    override func keyDown(with event: NSEvent) {
        if KeyCode.isReturn(event.keyCode) { openSelection?(); return }
        super.keyDown(with: event)
    }
}
