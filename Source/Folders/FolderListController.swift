import Cocoa

// The Folders page of Preferences. Each folder view owns its actions; focus never
// decides which selection to use. Rows are `owner.folders` in order.
final class FolderListController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    unowned let owner: AppDelegate
    let table = FolderTableView()

    init(owner: AppDelegate) {
        self.owner = owner
        super.init()
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(doubleClick)
        table.revealSelection = { [weak self] in
            guard let self = self else { return }
            self.owner.revealFolders(self.table.selectedRowIndexes)
        }
        table.openSelection = { [weak self] in
            guard let self = self else { return }
            self.owner.openSelectedFolders(self.table.selectedRowIndexes, in: self.table)
        }
        table.editSelection = { [weak self] in
            guard let self = self, self.table.selectedRowIndexes.count == 1,
                  let index = self.table.selectedRowIndexes.first else { return }
            self.owner.editFolder(at: index, in: self.table)
        }
    }
    // Double-click edits the folder.
    @objc private func doubleClick() {
        guard owner.folders.indices.contains(table.clickedRow) else { return }
        owner.editFolder(at: table.clickedRow, in: table)
    }
    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
        // Keep click/keyboard selection, but do not extend it by sweeping the mouse.
        ListSelection.proposed(proposedSelectionIndexes, in: tableView)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { owner.folders.count }
    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        owner.folders.indices.contains(row) ? owner.folders[row].name : nil
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { InsetListRowView() }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let columnIndex = column.flatMap { tableView.tableColumns.firstIndex(of: $0) } ?? 0
        let cellWidth = tableView.frameOfCell(atColumn: columnIndex, row: row).width
        guard owner.folders.indices.contains(row) else { return nil }
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: cellWidth, height: AppDelegate.appRowHeight))
        let folder = owner.folders[row]
        if columnIndex == 1 {
            // The same shortcut field as App List.
            owner.addShortcutRecorder(to: cell, width: cellWidth, for: .folder(path: folder.path),
                                      keys: folder.keys, table: tableView, row: row)
            return cell
        }
        let icon = owner.makeListIcon(path: folder.path)
        let name = NSTextField(labelWithString: folder.name)
        owner.configureListName(name, width: cellWidth)
        cell.addSubview(icon)
        // No path column: pointing at the folder shows where it is ("~/Projects/Clutch").
        let location = (folder.path as NSString).abbreviatingWithTildeInPath
        cell.toolTip = location
        name.toolTip = location
        cell.addSubview(name)
        return cell
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard owner.folders.indices.contains(row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(owner.folders[row].path, forType: owner.folderDragType)
        return item
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        let paths = draggedFolderPaths(info)
        guard info.draggingSource as? NSTableView === tableView,
              (0...owner.folders.count).contains(row),
              !paths.isEmpty,
              paths.allSatisfy({ path in owner.folders.contains { $0.path == path } }) else { return [] }
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard info.draggingSource as? NSTableView === tableView,
              let selection = FolderOrder.move(&owner.folders, paths: draggedFolderPaths(info), to: row) else { return false }
        owner.saveFolders()
        tableView.selectRowIndexes(selection, byExtendingSelection: false)
        if let first = selection.first { tableView.scrollRowToVisible(first) }
        return true
    }
    func draggedFolderPaths(_ info: NSDraggingInfo) -> [String] {
        (info.draggingPasteboard.pasteboardItems ?? []).compactMap { $0.string(forType: owner.folderDragType) }
    }
}
