import Cocoa

// The Shelf picker (Caps + Space): a search field where the Caps pill sits, the
// Shelf's files below, newest first, and a line of keys at the bottom. Typing filters;
// ↑/↓ move, Return opens, ⌘Return reveals in Finder, ⌘⌫ takes the file off the Shelf
// (the file itself stays). Files are added by pasting files copied in Finder (⌘V) or
// dropping them on the panel; rows can be dragged out, to attach a file somewhere.
final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var previousFocus: PreviousFocus?
    var openSelection: (() -> Void)?
    var revealSelection: (() -> Void)?
    var removeSelection: (() -> Void)?
    var pasteFiles: (() -> Bool)?

    override func performClose(_ sender: Any?) {
        guard attachedSheet == nil else { return }
        close()
        previousFocus?.restore()
    }
    // Clicking another app (or opening a file) dismisses it.
    override func resignKey() {
        super.resignKey()
        if isVisible, attachedSheet == nil { close() }
    }
    override func cancelOperation(_ sender: Any?) {
        if isKeyWindow, attachedSheet == nil { performClose(sender) }
    }
    // Command keys reach the window before the field editor or the Edit menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command {
            if KeyCode.isReturn(event.keyCode) { revealSelection?(); return true }
            if event.keyCode == KeyCode.delete { removeSelection?(); return true }
            // Files copied in Finder; plain text still pastes into the search.
            if event.keyCode == KeyCode.v, pasteFiles?() == true { return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class ShelfTableView: NSTableView {
    var openSelection: (() -> Void)?
    var revealSelection: (() -> Void)?
    var removeSelection: (() -> Void)?
    // Typing while the list has focus (after a click) goes to the search: true when it did.
    var searchKey: ((NSEvent) -> Bool)?

    override func menu(for event: NSEvent) -> NSMenu? {
        // The search field keeps focus while the menu is open.
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        if !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        displayIfNeeded()
        let menu = NSMenu()
        for (title, action) in [("Open", #selector(openSelected)), ("Reveal in Finder", #selector(revealSelected))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let remove = NSMenuItem(title: "Remove from Shelf", action: #selector(removeSelected), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)
        return menu
    }
    @objc func openSelected() { openSelection?() }
    @objc func revealSelected() { revealSelection?() }
    @objc func removeSelected() { removeSelection?() }
    override func keyDown(with event: NSEvent) {
        if searchKey?(event) == true { return }
        if KeyCode.isReturn(event.keyCode) { openSelection?(); return }
        if event.keyCode == KeyCode.escape { window?.cancelOperation(nil); return }
        super.keyDown(with: event)
    }
}

// The rows are the Shelf files matching the search, best match first (in Shelf order
// without a search). `entryIndex(forRow:)` maps a row back to `owner.shelf`.
final class ShelfListController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    unowned let owner: AppDelegate
    let table = ShelfTableView()
    weak var searchField: NSSearchField?
    weak var emptyLabel: NSTextField?
    private(set) var filter = ""
    private var jumpQuery = ""
    private var jumpTime: TimeInterval = 0
    private var compositionObserver: NSObjectProtocol?
    // Indexes into `owner.shelf` of the rows shown, in row order. Worked out in
    // reload(), once per change of the search or the Shelf, since names come from disk.
    private(set) var visibleIndices: [Int] = []

    init(owner: AppDelegate) {
        self.owner = owner
        super.init()
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(doubleClicked)
        table.allowsMultipleSelection = true
        // Typing filters the list instead of jumping to a name.
        table.allowsTypeSelect = false
        table.searchKey = { [weak self] event in self?.typeIntoSearch(event) ?? false }
        table.openSelection = { [weak self] in
            guard let self = self else { return }
            self.owner.openShelfFiles(self.selectedEntryIndices)
        }
        table.revealSelection = { [weak self] in
            guard let self = self else { return }
            self.owner.revealShelfFiles(self.selectedEntryIndices)
        }
        table.removeSelection = { [weak self] in
            guard let self = self else { return }
            self.owner.removeShelfFiles(self.selectedEntryIndices, in: self.table)
        }
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.draggingDestinationFeedbackStyle = .regular
        // An input method's text still being composed (Pinyin before a character is
        // chosen) is not reported as a text change; the field editor's storage holds
        // it, so its edits filter too.
        compositionObserver = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: nil, queue: nil) { [weak self] notification in
            guard let self = self, let storage = notification.object as? NSTextStorage,
                  let editor = self.searchField?.currentEditor() as? NSTextView,
                  editor.textStorage === storage else { return }
            self.setFilter(storage.string)
        }
    }
    deinit {
        if let observer = compositionObserver { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: Rows

    func entryIndex(forRow row: Int) -> Int? {
        let visible = visibleIndices
        return visible.indices.contains(row) ? visible[row] : nil
    }
    var selectedEntryIndices: IndexSet {
        let visible = visibleIndices
        return IndexSet(table.selectedRowIndexes.filter { visible.indices.contains($0) }.map { visible[$0] })
    }
    func reload() {
        visibleIndices = Shelf.ordered(owner.shelf.map { $0.name }, query: filter)
        table.reloadData()
        guard let label = emptyLabel else { return }
        label.stringValue = owner.shelf.isEmpty ? "Copy files in Finder, then press ⌘V here, or drop them here"
                                                : "No matching files"
        label.isHidden = table.numberOfRows > 0
    }
    func select(row: Int) {
        guard (0..<table.numberOfRows).contains(row) else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }
    // Selects these files, clearing a search that hides any of them.
    func select(paths: [String]) {
        if !filter.isEmpty { setFilter("") }
        let visibleIndices = self.visibleIndices
        let rows = IndexSet(paths.compactMap { path in
            visibleIndices.firstIndex { owner.shelf[$0].path == path }
        })
        table.selectRowIndexes(rows, byExtendingSelection: false)
        if let first = rows.first { table.scrollRowToVisible(first) }
    }
    @objc private func doubleClicked() {
        guard table.clickedRow >= 0 else { return }
        owner.openShelfFiles(selectedEntryIndices)
    }

    // MARK: Search

    // The best match is selected, so Return or releasing Caps opens it.
    func setFilter(_ text: String) {
        resetJump()
        // Compared with what is being edited, input method composition included, so
        // filtering never overwrites text still being composed.
        if let field = searchField, ((field.currentEditor() as? NSTextView)?.string ?? field.stringValue) != text {
            field.stringValue = text
        }
        guard text != filter else { return }
        filter = text
        reload()
        if table.numberOfRows > 0 { select(row: 0) } else { table.deselectAll(nil) }
    }
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === searchField else { return }
        setFilter(field.stringValue)
    }
    // The field keeps focus: ↑/↓ move the selection, Return opens it, and Escape clears
    // the search, or closes the panel when the search is already empty.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === searchField else { return false }
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)):
            let rows = table.numberOfRows
            guard rows > 0 else { return true }
            let step = commandSelector == #selector(NSResponder.moveUp(_:)) ? -1 : 1
            let current = table.selectedRow
            select(row: current < 0 ? 0 : min(max(current + step, 0), rows - 1))
            return true
        case #selector(NSResponder.insertNewline(_:)):
            table.openSelection?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if filter.isEmpty { control.window?.performClose(nil) } else { setFilter("") }
            return true
        default:
            return false
        }
    }
    // Typing while the list has focus (after a click) goes to the search field.
    func typeIntoSearch(_ event: NSEvent) -> Bool {
        guard let field = searchField,
              event.modifierFlags.intersection([.command, .control]).isEmpty,
              let text = event.characters, !text.isEmpty,
              text.unicodeScalars.allSatisfy({ scalar in
                  !CharacterSet.controlCharacters.contains(scalar) && !(0xF700...0xF8FF).contains(scalar.value)
              }) else { return false }
        field.window?.makeFirstResponder(field)
        field.currentEditor()?.insertText(text)
        return true
    }
    func resetJump() {
        jumpQuery = ""
        jumpTime = 0
    }
    // Caps + letters jump among the rows shown without changing the search; keys
    // pressed close together refine the match.
    func jump(key: UInt16, time: TimeInterval) {
        guard let text = keys.first(where: { $0.1 == key })?.0 else { return }
        let names = visibleIndices.map { owner.shelf[$0].name }
        let query = time - jumpTime < 0.8 ? jumpQuery + text : text
        let match = Shelf.ordered(names, query: query).first
        jumpQuery = match != nil ? query : text
        jumpTime = time
        if let row = match ?? Shelf.ordered(names, query: text).first { select(row: row) }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { visibleIndices.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = InsetListRowView()
        // The search field keeps focus; the selection still shows in the accent color.
        rowView.alwaysEmphasized = true
        return rowView
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let index = entryIndex(forRow: row) else { return nil }
        let entry = owner.shelf[index]
        let width = tableColumn?.width ?? tableView.bounds.width
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: width, height: AppDelegate.appRowHeight))
        cell.addSubview(owner.makeListIcon(path: entry.path))
        let hintWidth: CGFloat = row < 9 ? 28 : 0
        let name = NSTextField(labelWithString: entry.name)
        owner.configureListName(name, width: width - hintWidth - ListGeometry.trailingInset)
        cell.addSubview(name)
        if row < 9 {
            let hint = NSTextField(labelWithString: "⇪\(row + 1)")
            hint.font = .systemFont(ofSize: 12)
            hint.frame = NSRect(x: width - ListGeometry.trailingInset - hintWidth, y: AppDelegate.listNameFrame.minY,
                                width: hintWidth, height: AppDelegate.listNameFrame.height)
            hint.autoresizingMask = [.minXMargin]
            hint.alignment = .right
            hint.textColor = .secondaryLabelColor
            cell.addSubview(hint)
        }
        cell.toolTip = (entry.path as NSString).abbreviatingWithTildeInPath
        return cell
    }
    // Drag a file out (to attach it, or into a Finder window).
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        entryIndex(forRow: row).map { NSURL(fileURLWithPath: owner.shelf[$0].path) }
    }
    // Files dropped from elsewhere go on the Shelf.
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard info.draggingSource as? NSTableView !== tableView,
              !Self.fileURLs(on: info.draggingPasteboard).isEmpty else { return [] }
        // The whole list highlights: new files always go on top.
        tableView.setDropRow(-1, dropOperation: .on)
        return .copy
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        let urls = Self.fileURLs(on: info.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        owner.addShelfFiles(urls)
        return true
    }
    static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
}
