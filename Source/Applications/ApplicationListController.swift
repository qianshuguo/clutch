import Cocoa

// Retained by AppDelegate for the lifetime of the preferences view tree.
final class ApplicationListController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    unowned let owner: AppDelegate
    let table = NSTableView()

    init(owner: AppDelegate) {
        self.owner = owner
        super.init()
        table.delegate = self
        table.dataSource = self
        table.allowsMultipleSelection = true
        // Every shortcut field starts with “Caps +”; native type selection is misleading.
        table.allowsTypeSelect = false
    }
    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
        // Keep click/keyboard selection, but do not extend it by sweeping the mouse.
        ListSelection.proposed(proposedSelectionIndexes, in: tableView)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { owner.bindings.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        InsetListRowView()
    }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let columnIndex = column.flatMap { tableView.tableColumns.firstIndex(of: $0) } ?? 0
        let cellWidth = tableView.frameOfCell(atColumn: columnIndex, row: row).width
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: cellWidth, height: AppDelegate.appRowHeight))
        let binding = owner.bindings[row]
        if columnIndex == 0 {
            cell.addSubview(owner.makeListIcon(path: binding.path))
            let name = NSTextField(labelWithString: binding.name)
            owner.configureListName(name, width: cellWidth)
            cell.addSubview(name)
            return cell
        }
        let recorder = owner.addShortcutRecorder(to: cell, width: cellWidth, key: binding.key, table: tableView)
        recorder.title = shortcutTitle(binding.key, binding.secondKey)
        recorder.onStart = { [weak self] in
            self?.owner.state.cancelGesture()
            self?.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        recorder.maxKeys = 2
        recorder.onKeys = { [weak self, weak recorder] code, second in
            guard let self = self, let recorder = recorder else { return false }
            return self.owner.assignShortcut(code, second, to: binding, recorder: recorder)
        }
        return cell
    }
}
