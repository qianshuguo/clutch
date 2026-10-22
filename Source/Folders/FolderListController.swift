import Cocoa

// Each folder view owns its actions; focus never decides which selection to use.
// The picker is filtered by its search field: rows show the matching folders in
// `owner.folders` order, and `folderIndex(forRow:)` maps a row back to its entry.
// Preferences always shows every folder.
final class FolderListController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    unowned let owner: AppDelegate
    let table = FolderTableView()
    let presentation: FolderListPresentation
    weak var searchField: NSTextField?
    private(set) var filter = ""
    private var compositionObserver: NSObjectProtocol?

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
            self.owner.openSelectedFolders(self.selectedFolderIndices, in: self.table)
        }
        if presentation == .picker {
            // Typing filters the list instead of jumping to a name.
            table.allowsTypeSelect = false
            table.searchKey = { [weak self] event in self?.typeIntoSearch(event) ?? false }
            // An input method's text still being composed (Pinyin before a character is
            // chosen) is not reported as a text change; the field editor's storage
            // holds it, so its edits filter too.
            compositionObserver = NotificationCenter.default.addObserver(
                forName: NSTextStorage.didProcessEditingNotification, object: nil, queue: nil) { [weak self] notification in
                guard let self = self, let storage = notification.object as? NSTextStorage,
                      let editor = self.searchField?.currentEditor() as? NSTextView,
                      editor.textStorage === storage else { return }
                self.setFilter(storage.string)
            }
        }
    }
    deinit {
        if let observer = compositionObserver { NotificationCenter.default.removeObserver(observer) }
    }
    @objc private func doubleClick() {
        guard folderIndex(forRow: table.clickedRow) != nil else { return }
        owner.openSelectedFolders(selectedFolderIndices, in: table)
    }

    // MARK: Search

    // How well a folder matches the search, best first, ignoring case and accents; nil
    // when it does not match. 0: a word of the name starts with the search ("doc" →
    // "My Documents"). 1: the search is the initials of words of the name, in order
    // ("pd" → "Project Docs"). 2: the name contains it. 3: the path contains it.
    // Chinese characters also match by their pinyin, one syllable per word ("文件夹":
    // "wen", "wenjian", "jian", initials "wjj"), with the input method's spaces and
    // apostrophes ignored ("wen'jian").
    static func rank(_ folder: FolderEntry, query: String) -> Int? {
        let search = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !search.isEmpty else { return 0 }
        let characters = Array(folder.name)
        var best = rank(words: characters.map { fold(String($0)) }, starts: wordStarts(characters), search: search)
        if let syllables = pinyin(folder.name) {
            let compact = search.filter { $0 != " " && $0 != "'" }
            if !compact.isEmpty, let byPinyin = rank(words: syllables.letters, starts: syllables.starts, search: compact) {
                best = min(best ?? byPinyin, byPinyin)
            }
        }
        if let best = best { return best }
        if fold(folder.path).contains(search) { return 3 }
        return nil
    }
    // 0: a word starts with the search; 1: word initials spell it; 2: contains it.
    private static func rank(words folded: [String], starts: [Int], search: String) -> Int? {
        if starts.contains(where: { folded[$0...].joined().hasPrefix(search) }) { return 0 }
        let letters = search.filter { $0 != " " }
        if letters.count > 1 {
            var remaining = Substring(letters)
            for start in starts {
                guard let next = remaining.first else { break }
                if folded[start].first == next { remaining = remaining.dropFirst() }
            }
            if remaining.isEmpty { return 1 }
        }
        if folded.joined().contains(search) { return 2 }
        return nil
    }
    // The name with each Chinese character spelled in toneless pinyin, as single
    // letters, and where each syllable or other word starts; nil without Chinese.
    private static var pinyinCache: [String: (letters: [String], starts: [Int])] = [:]
    private static func pinyin(_ name: String) -> (letters: [String], starts: [Int])? {
        guard name.unicodeScalars.contains(where: { $0.properties.isIdeographic }) else { return nil }
        if let cached = pinyinCache[name] { return cached }
        var letters: [String] = [], starts: [Int] = []
        var inWord = false
        for character in name {
            if character.unicodeScalars.allSatisfy({ $0.properties.isIdeographic }) {
                let syllable = NSMutableString(string: String(character))
                CFStringTransform(syllable, nil, kCFStringTransformMandarinLatin, false)
                CFStringTransform(syllable, nil, kCFStringTransformStripDiacritics, false)
                let spelled = fold(syllable as String).filter { $0.isLetter }.map { String($0) }
                if !spelled.isEmpty { starts.append(letters.count); letters += spelled }
                inWord = false
            } else if character.isLetter || character.isNumber {
                if !inWord { starts.append(letters.count) }
                letters += fold(String(character)).map { String($0) }
                inWord = true
            } else {
                inWord = false
            }
        }
        let result = (letters: letters, starts: starts)
        pinyinCache[name] = result
        return result
    }
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
    // Where words begin: after a space or punctuation, and at camel-case humps
    // ("MyProject" has words at M and P).
    private static func wordStarts(_ characters: [Character]) -> [Int] {
        characters.indices.filter { index in
            let character = characters[index]
            guard character.isLetter || character.isNumber else { return false }
            guard index > 0 else { return true }
            let previous = characters[index - 1]
            if !(previous.isLetter || previous.isNumber) { return true }
            return character.isUppercase && previous.isLowercase
        }
    }
    // Indexes into owner.folders that match, best match first; equal matches keep the
    // list order. Without a search, every folder in list order.
    static func ordered(_ folders: [FolderEntry], query: String) -> [Int] {
        folders.indices.compactMap { index in rank(folders[index], query: query).map { (index, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }
            .map { $0.0 }
    }
    // Indexes into owner.folders of the rows shown, in row order.
    var visibleIndices: [Int] { Self.ordered(owner.folders, query: filter) }
    func folderIndex(forRow row: Int) -> Int? {
        let visible = visibleIndices
        return visible.indices.contains(row) ? visible[row] : nil
    }
    var selectedFolderIndices: IndexSet {
        let visible = visibleIndices
        return IndexSet(table.selectedRowIndexes.filter { visible.indices.contains($0) }.map { visible[$0] })
    }
    // The best match is selected, so Return or releasing Caps opens it.
    func setFilter(_ text: String) {
        // Compared with what is being edited, input method composition included, so
        // filtering never overwrites text still being composed.
        if let field = searchField, ((field.currentEditor() as? NSTextView)?.string ?? field.stringValue) != text {
            field.stringValue = text
        }
        guard text != filter else { return }
        filter = text
        table.reloadData()
        if table.numberOfRows > 0 {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            table.scrollRowToVisible(0)
        } else {
            table.deselectAll(nil)
        }
    }
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === searchField else { return }
        setFilter(field.stringValue)
    }
    // The field keeps focus: ↑/↓ move the list selection, Return opens it, and Escape
    // clears the search, or closes the panel when the search is already empty.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === searchField else { return false }
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)):
            let rows = table.numberOfRows
            guard rows > 0 else { return true }
            let step = commandSelector == #selector(NSResponder.moveUp(_:)) ? -1 : 1
            let current = table.selectedRow
            let next = current < 0 ? 0 : min(max(current + step, 0), rows - 1)
            table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
            table.scrollRowToVisible(next)
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
    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
        // Keep click/keyboard selection, but do not extend it by sweeping the mouse.
        ListSelection.proposed(proposedSelectionIndexes, in: tableView)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleIndices.count }
    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        folderIndex(forRow: row).map { owner.folders[$0].name }
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = InsetListRowView()
        rowView.alwaysEmphasized = presentation == .picker
        return rowView
    }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let columnIndex = column.flatMap { tableView.tableColumns.firstIndex(of: $0) } ?? 0
        let cellWidth = tableView.frameOfCell(atColumn: columnIndex, row: row).width
        guard let index = folderIndex(forRow: row) else { return nil }
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: cellWidth, height: AppDelegate.appRowHeight))
        let folder = owner.folders[index]
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
        guard let index = folderIndex(forRow: row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(owner.folders[index].path, forType: owner.folderDragType)
        return item
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        let paths = draggedFolderPaths(info)
        // Reordering needs every folder in view.
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
