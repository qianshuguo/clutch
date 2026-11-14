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
        // Typing jumps to an application by name (see typeSelectName).
        table.allowsTypeSelect = true
        connectSearch()
    }

    // MARK: Table

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
        let binding = owner.bindings[index]
        if columnIndex == 0 {
            owner.addListName(binding.name, icon: owner.makeListIcon(path: binding.path), to: cell, width: width)
        } else {
            owner.addShortcutRecorder(to: cell, width: width, for: .app(path: binding.path),
                                      keys: binding.keys, table: tableView, row: row)
        }
        return cell
    }
}
