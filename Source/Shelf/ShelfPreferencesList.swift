import Cocoa

// The Shelf page of Preferences: the Shelf's files in Shelf order (newest first), with
// + / −, search and ? like the other list pages, but no Shortcut column — Shelf files
// are opened from Caps + Space. Double-click or Return opens, right-click opens or
// reveals; files dropped on the list are added, and rows can be dragged out.
final class ShelfPreferencesListController: NSObject, NSTableViewDataSource, NSTableViewDelegate, SearchableList {
    unowned let owner: AppDelegate
    let table = EntryTableView()
    let search = ListSearch()
    var listTable: NSTableView { table }
    var entryNames: [String] { owner.shelf.map { $0.name } }
    var entryIDs: [String] { owner.shelf.map { $0.path } }

    init(owner: AppDelegate) {
        self.owner = owner
        super.init()
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(doubleClick)
        table.allowsMultipleSelection = true
        table.openSelection = { [weak self] in
            guard let self = self, self.table.window?.attachedSheet == nil else { return }
            self.owner.openShelfFiles(self.selectedEntryIndices)
        }
        table.revealSelection = { [weak self] in
            guard let self = self else { return }
            self.owner.revealShelfFiles(self.selectedEntryIndices)
        }
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.draggingDestinationFeedbackStyle = .regular
        connectSearch()
    }
    func reload() {
        table.reloadData()
        updateEmptyLabel()
    }
    // Selects these files, clearing a search that hides any of them.
    func select(paths: [String]) {
        let indices = paths.compactMap { path in owner.shelf.firstIndex { $0.path == path } }
        if indices.contains(where: { row(forEntryAt: $0) == nil }) { clearFilter() }
        let rows = IndexSet(indices.compactMap { row(forEntryAt: $0) })
        table.selectRowIndexes(rows, byExtendingSelection: false)
        if let first = rows.first { table.scrollRowToVisible(first) }
    }
    @objc private func doubleClick() {
        guard table.clickedRow >= 0 else { return }
        table.openSelection?()
    }

    // MARK: Table

    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
        ListSelection.proposed(proposedSelectionIndexes, in: tableView)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleIndices.count }
    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        entryIndex(forRow: row).map { owner.shelf[$0].name }
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { InsetListRowView() }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard let index = entryIndex(forRow: row) else { return nil }
        let entry = owner.shelf[index]
        let width = tableView.frameOfCell(atColumn: 0, row: row).width
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: width, height: AppDelegate.appRowHeight))
        cell.addSubview(owner.makeListIcon(path: entry.path))
        let name = NSTextField(labelWithString: entry.name)
        owner.configureListName(name, width: width - ListGeometry.trailingInset)
        // No path column: pointing at the file shows where it is, as in Folders.
        let location = (entry.path as NSString).abbreviatingWithTildeInPath
        cell.toolTip = location
        name.toolTip = location
        cell.addSubview(name)
        return cell
    }
    // Drag a file out (to attach it, or into a Finder window).
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        entryIndex(forRow: row).map { NSURL(fileURLWithPath: owner.shelf[$0].path) }
    }
    // Files dropped from elsewhere go on top of the Shelf.
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard info.draggingSource as? NSTableView !== tableView, tableView.window?.attachedSheet == nil,
              !ShelfListController.fileURLs(on: info.draggingPasteboard).isEmpty else { return [] }
        tableView.setDropRow(-1, dropOperation: .on)
        return .copy
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        let urls = ShelfListController.fileURLs(on: info.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        select(paths: owner.addShelfFiles(urls))
        return true
    }
}

extension AppDelegate {
    // The Shelf page of Preferences.
    func addShelfPage(to page: NSView) {
        // Files that were moved or deleted leave, as when the picker opens.
        if Shelf.prune(&shelf) { StoredList.save(shelf, forKey: DefaultsKey.shelf) }
        let controller = ShelfPreferencesListController(owner: self)
        preferencesShelfList = controller
        addEntryListPage(ListPageSpec(
            entryName: "File", pluralName: "Files",
            shortcutAction: nil,
            help: [("Caps + Space", "Open the Shelf"),
                   ("⌘V in the Shelf", "Add files copied in Finder"),
                   ("Drop files on the list", "Add them to the Shelf"),
                   ("Drag a file out", "Attach or copy it elsewhere"),
                   ("Double-click a file", "Open it"),
                   ("Right-click a file", "Open or reveal it")],
            add: { [weak self, weak controller] in
                guard let controller = controller else { return }
                self?.chooseShelfFiles(for: controller)
            },
            remove: { [weak self, weak controller] in
                guard let controller = controller else { return }
                self?.removeShelfFiles(controller.selectedEntryIndices, in: controller.table)
            }), list: controller, to: page)
    }
    // +: an Open panel over Preferences; the chosen files and folders go on top.
    func chooseShelfFiles(for controller: ShelfPreferencesListController) {
        guard let window = controller.table.window, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.beginSheetModal(for: window) { [weak self, weak controller] response in
            guard response == .OK, let self = self, let controller = controller else { return }
            controller.select(paths: self.addShelfFiles(panel.urls))
        }
    }
}
