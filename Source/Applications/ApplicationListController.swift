import Cocoa

// Retained by AppDelegate for the lifetime of the preferences view tree.
// Rows show the applications matching the search field, in `owner.bindings` order;
// `entryIndex(forRow:)` maps a row back to its entry.
final class ApplicationListController: NSObject, NSTableViewDataSource, NSTableViewDelegate, SearchableList {
    unowned let owner: AppDelegate
    let table = NSTableView()
    let search = ListSearch()
    var listTable: NSTableView { table }
    var entryNames: [String] { owner.bindings.map { $0.name } }
    var entryIDs: [String] { owner.bindings.map { $0.path } }

    init(owner: AppDelegate) {
        self.owner = owner
        super.init()
        table.delegate = self
        table.dataSource = self
        table.allowsMultipleSelection = true
        // Typing jumps to an application by name; shortcut fields take no part
        // (see typeSelectStringFor), since they all start with “⇪”.
        table.allowsTypeSelect = true
        connectSearch()
    }
    func reload() {
        table.reloadData()
        updateEmptyLabel()
    }

    // MARK: Table

    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
        // Keep click/keyboard selection, but do not extend it by sweeping the mouse.
        ListSelection.proposed(proposedSelectionIndexes, in: tableView)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleIndices.count }
    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        if let column = tableColumn, tableView.tableColumns.firstIndex(of: column) != 0 { return nil }
        return entryIndex(forRow: row).map { owner.bindings[$0].name }
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        InsetListRowView()
    }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard let index = entryIndex(forRow: row) else { return nil }
        let columnIndex = column.flatMap { tableView.tableColumns.firstIndex(of: $0) } ?? 0
        let cellWidth = tableView.frameOfCell(atColumn: columnIndex, row: row).width
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: cellWidth, height: AppDelegate.appRowHeight))
        let binding = owner.bindings[index]
        if columnIndex == 0 {
            cell.addSubview(owner.makeListIcon(path: binding.path))
            let name = NSTextField(labelWithString: binding.name)
            owner.configureListName(name, width: cellWidth)
            cell.addSubview(name)
            return cell
        }
        owner.addShortcutRecorder(to: cell, width: cellWidth, for: .app(path: binding.path),
                                  keys: binding.keys, table: tableView, row: row)
        return cell
    }
}
