import Cocoa

// Each folder view owns its actions; focus never decides which selection to use.
final class FolderListController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    unowned let owner: AppDelegate
    let table = FolderTableView()
    let presentation: FolderListPresentation

    init(owner: AppDelegate, presentation: FolderListPresentation) {
        self.owner = owner
        self.presentation = presentation
        super.init()
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(doubleClick)
        table.openSelection = { [weak self] in
            guard let self = self else { return }
            self.owner.openSelectedFolders(in: self.table)
        }
    }
    @objc private func doubleClick() {
        guard owner.folders.indices.contains(table.clickedRow) else { return }
        owner.openSelectedFolders(in: table)
    }
    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
        // Keep click/keyboard selection, but do not extend it by sweeping the mouse.
        ListSelection.proposed(proposedSelectionIndexes, in: tableView)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { owner.folders.count }
    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        owner.folders.indices.contains(row) ? owner.folders[row].name : nil
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        InsetListRowView()
    }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let columnIndex = column.flatMap { tableView.tableColumns.firstIndex(of: $0) } ?? 0
        let cellWidth = tableView.frameOfCell(atColumn: columnIndex, row: row).width
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: cellWidth, height: AppDelegate.appRowHeight))
        let folder = owner.folders[row]
        if columnIndex == 1 {
            let shortcutWidth = presentation.shortcutReservedWidth
            // Only Preferences shifts Path; the standalone picker keeps its layout.
            let pathOffset = presentation.pathOffset
            let path = owner.label(folder.path, frame: NSRect(x: ListGeometry.pathLeadingInset + pathOffset, y: AppDelegate.listNameFrame.minY,
                                                  width: max(0, cellWidth - ListGeometry.pathLeadingInset - ListGeometry.trailingInset - shortcutWidth), height: AppDelegate.listNameFrame.height), size: 12)
            path.autoresizingMask = [.width]
            path.textColor = .secondaryLabelColor
            path.lineBreakMode = .byTruncatingHead
            path.alignment = .left
            path.maximumNumberOfLines = 1
            path.attributedStringValue = formattedFolderPath(folder.path)
            cell.addSubview(path)
            if presentation.showsShortcuts, row < 9 {
                let hint = owner.label("⇪\(row + 1)", frame: NSRect(
                    x: cellWidth - ListGeometry.trailingInset - 28,
                    y: AppDelegate.listNameFrame.minY, width: 28, height: AppDelegate.listNameFrame.height), size: 12)
                hint.autoresizingMask = [.minXMargin]
                hint.alignment = .right
                hint.textColor = .secondaryLabelColor
                cell.addSubview(hint)
            }
            return cell
        }
        cell.addSubview(owner.makeListIcon(path: folder.path))
        let name = FolderNameField(labelWithString: folder.name)
        owner.configureListName(name, width: cellWidth)
        name.folderTable = tableView
        name.onRename = { [weak self] value in
            guard let self = self, let index = self.owner.folders.firstIndex(where: { $0.path == folder.path }) else { return }
            self.owner.folders[index].name = value
            self.owner.saveFolders()
        }
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
    func formattedFolderPath(_ path: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingHead
        let text = NSMutableAttributedString(string: path, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor.tertiaryLabelColor
        ])
        let leaf = URL(fileURLWithPath: path).lastPathComponent
        let range = (path as NSString).range(of: leaf, options: .backwards)
        if !leaf.isEmpty, range.location != NSNotFound {
            text.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        }
        return text
    }
}
