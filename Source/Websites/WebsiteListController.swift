import Cocoa

// Preferences > Websites: the App List layout with websites on the left and their Caps
// shortcut on the right: the websites matching the search, in `owner.websites` order. Each row shows the name, or the address it
// matches when it has none; pointing at a row shows the full address. Return opens the selected
// websites; double-click or Edit… in the context menu changes the name and URL. Retained by AppDelegate with the preferences view tree.
final class WebsiteListController: NSObject, NSTableViewDataSource, NSTableViewDelegate, SearchableList {
    unowned let owner: AppDelegate
    let table = EntryTableView()
    let search = ListSearch()
    var listTable: NSTableView { table }
    var entryNames: [String] { owner.websites.map { $0.name } }
    var entryIDs: [String] { owner.websites.map { $0.url } }
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
            self.owner.openWebsites(self.selectedEntryIndices)
        }
        connectSearch()
    }

    // Double-click edits the website, like Folders in Settings.
    @objc private func doubleClick() {
        // Shortcut fields take their own clicks.
        guard let index = entryIndex(forRow: table.clickedRow) else { return }
        owner.editWebsite(at: index)
    }
    private func editSelected() {
        let selection = selectedEntryIndices
        guard selection.count == 1, let index = selection.first else { return }
        owner.editWebsite(at: index)
    }

    func reload() {
        icon = WebsiteEntry.browserIcon
        table.reloadData()
        updateEmptyLabel()
    }

    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
        // Keep click/keyboard selection, but do not extend it by sweeping the mouse.
        ListSelection.proposed(proposedSelectionIndexes, in: tableView)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleIndices.count }
    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        typeSelectName(in: tableView, column: tableColumn, row: row)
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        InsetListRowView()
    }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard let index = entryIndex(forRow: row) else { return nil }
        let (cell, columnIndex, width) = owner.makeListCell(in: tableView, column: column, row: row)
        let site = owner.websites[index]
        if columnIndex == 0 {
            let name = owner.addListName(site.name, icon: owner.makeListIcon(image: icon ?? WebsiteEntry.browserIcon),
                                         to: cell, width: width)
            // Pointing at the row shows the full address that opens, and whether its
            // subdomains count.
            let includes = site.scope?.includesSubdomains ?? false
            let tip = includes ? site.url + "\nIncluding subdomains" : site.url
            cell.toolTip = tip
            name.toolTip = tip
        } else {
            owner.addShortcutRecorder(to: cell, width: width, for: .website(url: site.url),
                                      keys: site.keys, table: tableView, row: row)
        }
        return cell
    }
}
