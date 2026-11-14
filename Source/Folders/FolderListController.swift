import Cocoa

// The Folders page of Preferences. Rows are the folders matching the search, in
// `owner.folders` order; `entryIndex(forRow:)` maps a row back to its folder.
final class FolderListController: NSObject, NSTableViewDataSource, NSTableViewDelegate, SearchableList {
    unowned let owner: AppDelegate
    let table = EntryTableView()
    let search = ListSearch()
    var listTable: NSTableView { table }
    var entryNames: [String] { owner.folders.map { $0.name } }
    var entryIDs: [String] { owner.folders.map { $0.path } }

    init(owner: AppDelegate) {
        self.owner = owner
        super.init()
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(doubleClick)
        table.revealSelection = { [weak self] in
            guard let self = self else { return }
            self.owner.revealFolders(self.selectedEntryIndices)
        }
        table.openSelection = { [weak self] in
            guard let self = self else { return }
            self.owner.openSelectedFolders(self.selectedEntryIndices)
        }
        table.editSelection = { [weak self] in
            guard let self = self, self.selectedEntryIndices.count == 1,
                  let index = self.selectedEntryIndices.first else { return }
            self.owner.editFolder(at: index)
        }
        connectSearch()
    }
    // Double-click edits the folder.
    @objc private func doubleClick() {
        guard let index = entryIndex(forRow: table.clickedRow) else { return }
        owner.editFolder(at: index)
    }
    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
        // Keep click/keyboard selection, but do not extend it by sweeping the mouse.
        ListSelection.proposed(proposedSelectionIndexes, in: tableView)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleIndices.count }
    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        typeSelectName(in: tableView, column: tableColumn, row: row)
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { InsetListRowView() }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard let index = entryIndex(forRow: row) else { return nil }
        let (cell, columnIndex, width) = owner.makeListCell(in: tableView, column: column, row: row)
        let folder = owner.folders[index]
        if columnIndex == 0 {
            let name = owner.addListName(folder.name, icon: owner.makeListIcon(path: folder.path), to: cell, width: width)
            // No path column: pointing at the folder shows where it is ("~/Projects/Clutch").
            let location = (folder.path as NSString).abbreviatingWithTildeInPath
            cell.toolTip = location
            name.toolTip = location
        } else {
            owner.addShortcutRecorder(to: cell, width: width, for: .folder(path: folder.path),
                                      keys: folder.keys, table: tableView, row: row)
        }
        return cell
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let index = entryIndex(forRow: row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(owner.folders[index].path, forType: owner.folderDragType)
        return item
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        let paths = draggedFolderPaths(info)
        // Drop rows are positions in the whole list, so reordering waits for an empty search.
        guard filter.isEmpty, info.draggingSource as? NSTableView === tableView,
              (0...owner.folders.count).contains(row),
              !paths.isEmpty,
              paths.allSatisfy({ path in owner.folders.contains { $0.path == path } }) else { return [] }
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard filter.isEmpty, info.draggingSource as? NSTableView === tableView,
              let selection = ListOrder.move(&owner.folders, paths: draggedFolderPaths(info), to: row) else { return false }
        owner.saveFolders()
        tableView.selectRowIndexes(selection, byExtendingSelection: false)
        if let first = selection.first { tableView.scrollRowToVisible(first) }
        return true
    }
    func draggedFolderPaths(_ info: NSDraggingInfo) -> [String] {
        (info.draggingPasteboard.pasteboardItems ?? []).compactMap { $0.string(forType: owner.folderDragType) }
    }
}
