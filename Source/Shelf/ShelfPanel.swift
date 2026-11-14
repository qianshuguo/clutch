import Cocoa

// The Shelf picker (Caps + Space): a search field where the Caps pill sits, the
// Shelf's files below, in the user's order (new files on top), and a line of keys at the
// bottom. Typing filters; ↑/↓ move, Return opens, ⌘Return reveals in Finder, ⌘⌫ takes
// the file off the Shelf (the file itself stays). Files are added by pasting files copied
// in Finder (⌘V) or dropping them on the panel; rows are dragged within the list to
// reorder them, or out, to attach a file somewhere.
final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var previousFocus: PreviousFocus?
    var openSelection: (() -> Void)?
    var revealSelection: (() -> Void)?
    var removeSelection: (() -> Void)?
    var pasteFiles: (() -> Bool)?

    override func performClose(_ sender: Any?) {
        close()
        previousFocus?.restore()
    }
    // Clicking another app (or opening a file) dismisses it. A press in another app may
    // be the start of dragging files here (from Finder, say), so the panel waits for the
    // button to come up: released over the panel, it stays and takes the keyboard back;
    // released anywhere else (a plain click, or a drag that went elsewhere), it closes.
    private var releaseTimer: Timer?
    override func resignKey() {
        super.resignKey()
        guard isVisible else { return }
        if NSEvent.pressedMouseButtons == 0 { close(); return }
        guard releaseTimer == nil else { return }
        // Polled: the drag runs in the other app, so its events never reach Clutch.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self = self, NSEvent.pressedMouseButtons == 0 else { return }
            self.stopWaitingForRelease()
            guard self.isVisible, !self.isKeyWindow else { return }
            if self.frame.contains(NSEvent.mouseLocation) {
                self.makeKeyAndOrderFront(nil)
            } else {
                self.close()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        releaseTimer = timer
    }
    private func stopWaitingForRelease() {
        releaseTimer?.invalidate()
        releaseTimer = nil
    }
    override func close() {
        stopWaitingForRelease()
        super.close()
    }
    override func cancelOperation(_ sender: Any?) {
        if isKeyWindow { performClose(sender) }
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
        guard ListSelection.selectForMenu(event, in: self, focus: false) != nil else { return nil }
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
final class ShelfListController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, FilteredList {
    unowned let owner: AppDelegate
    let table = ShelfTableView()
    var listTable: NSTableView { table }
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
            self.owner.removeShelfFiles(self.selectedEntryIndices)
        }
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.setDraggingSourceOperationMask(.move, forLocal: true)
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
        guard let text = keyName(key) else { return }
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
        let hintWidth: CGFloat = row < 9 ? 28 : 0
        // The column already stops short of the scrollbar lane, so the hint sits close to
        // the column's edge rather than a full list inset in.
        let hintTrailing: CGFloat = 4
        owner.addListName(entry.name, icon: owner.makeListIcon(path: entry.path), to: cell,
                          width: width - hintWidth - hintTrailing)
        if row < 9 {
            let hint = NSTextField(labelWithString: "⇪\(row + 1)")
            hint.font = .systemFont(ofSize: 12)
            hint.frame = NSRect(x: width - hintTrailing - hintWidth, y: AppDelegate.listNameFrame.minY,
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
    // Rows dragged within the list reorder it; files dropped from elsewhere go on the Shelf.
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        let urls = Self.fileURLs(on: info.draggingPasteboard)
        guard !urls.isEmpty else { return [] }
        if info.draggingSource as? NSTableView === tableView {
            // Drop rows are positions in the whole list, so reordering waits for an empty search.
            guard filter.isEmpty, (0...owner.shelf.count).contains(row) else { return [] }
            tableView.setDropRow(row, dropOperation: .above)
            return .move
        }
        // The whole list highlights: new files always go on top.
        tableView.setDropRow(-1, dropOperation: .on)
        return .copy
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        let urls = Self.fileURLs(on: info.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        if info.draggingSource as? NSTableView === tableView {
            let paths = urls.map { $0.standardizedFileURL.path }
            guard filter.isEmpty, let moved = ListOrder.move(&owner.shelf, paths: paths, to: row) else { return false }
            owner.saveShelf()
            tableView.selectRowIndexes(moved, byExtendingSelection: false)
            if let first = moved.first { tableView.scrollRowToVisible(first) }
            return true
        }
        owner.addShelfFiles(urls)
        return true
    }
    static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
}
