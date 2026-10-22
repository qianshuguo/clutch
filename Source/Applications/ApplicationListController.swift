import Cocoa

// Retained by AppDelegate for the lifetime of the preferences view tree.
// Rows show the applications matching the search field, in `owner.bindings` order;
// `bindingIndex(forRow:)` maps a row back to its entry.
final class ApplicationListController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    unowned let owner: AppDelegate
    let table = NSTableView()
    weak var searchField: NSSearchField?
    weak var emptyLabel: NSTextField?
    // Text in the search field; empty shows every application.
    private(set) var filter = ""

    init(owner: AppDelegate) {
        self.owner = owner
        super.init()
        table.delegate = self
        table.dataSource = self
        table.allowsMultipleSelection = true
        // Typing jumps to an application by name; shortcut fields take no part
        // (see typeSelectStringFor), since they all start with “Caps +”.
        table.allowsTypeSelect = true
    }

    // MARK: Search

    // Names only, anywhere in the name, ignoring case and accents.
    static func matches(_ shortcut: AppShortcut, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || shortcut.name.localizedStandardContains(trimmed)
    }
    // Indexes into owner.bindings of the rows shown, in row order.
    var visibleIndices: [Int] {
        owner.bindings.indices.filter { Self.matches(owner.bindings[$0], query: filter) }
    }
    func bindingIndex(forRow row: Int) -> Int? {
        let visible = visibleIndices
        return visible.indices.contains(row) ? visible[row] : nil
    }
    func row(forBindingAt index: Int) -> Int? { visibleIndices.firstIndex(of: index) }
    var selectedBindingIndices: IndexSet {
        let visible = visibleIndices
        return IndexSet(table.selectedRowIndexes.filter { visible.indices.contains($0) }.map { visible[$0] })
    }
    // Keeps the selected applications selected when they still match.
    func setFilter(_ text: String) {
        guard text != filter else { return }
        let selectedPaths = Set(selectedBindingIndices.map { owner.bindings[$0].path })
        filter = text
        reload()
        let visible = visibleIndices
        let rows = IndexSet(visible.indices.filter { selectedPaths.contains(owner.bindings[visible[$0]].path) })
        table.selectRowIndexes(rows, byExtendingSelection: false)
        if let first = rows.first { table.scrollRowToVisible(first) } else { table.scrollRowToVisible(0) }
    }
    func clearFilter() {
        searchField?.stringValue = ""
        setFilter("")
    }
    func reload() {
        table.reloadData()
        emptyLabel?.isHidden = filter.isEmpty || table.numberOfRows > 0
    }
    // Selects the application, clearing a search that hides it.
    func reveal(bindingAt index: Int) {
        if row(forBindingAt: index) == nil { clearFilter() }
        guard let row = row(forBindingAt: index) else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }
    func focusSearch() {
        guard let field = searchField else { return }
        field.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }
    @objc func searchChanged(_ sender: NSSearchField) { setFilter(sender.stringValue) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.insertNewline(_:)):
            // Down or Return moves into the results, keeping or starting a selection.
            guard table.numberOfRows > 0 else { return true }
            control.window?.makeFirstResponder(table)
            if table.selectedRowIndexes.isEmpty {
                table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            }
            table.scrollRowToVisible(table.selectedRow)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            // Escape only leaves the search: it clears the text and returns focus to
            // the list. It never closes Preferences from here; Escape in the list does.
            clearFilter()
            control.window?.makeFirstResponder(table)
            return true
        default:
            return false
        }
    }

    // MARK: Table

    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
        // Keep click/keyboard selection, but do not extend it by sweeping the mouse.
        ListSelection.proposed(proposedSelectionIndexes, in: tableView)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleIndices.count }
    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        if let column = tableColumn, tableView.tableColumns.firstIndex(of: column) != 0 { return nil }
        return bindingIndex(forRow: row).map { owner.bindings[$0].name }
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        InsetListRowView()
    }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard let index = bindingIndex(forRow: row) else { return nil }
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
        let recorder = owner.addShortcutRecorder(to: cell, width: cellWidth, key: binding.key,
                                                 secondKey: binding.secondKey, table: tableView)
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
