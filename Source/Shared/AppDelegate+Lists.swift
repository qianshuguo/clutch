import Cocoa

extension AppDelegate {
    // Reserve the native scrollbar lane in both modes so fixed controls stay visible.
    static var listScrollbarWidth: CGFloat { NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) }
    // Two fixed columns: `title` (Application, Name, Action) and Shortcut. The shortcut
    // field is right-aligned in its column, so a wider first column (`nameWidth`) gives
    // names more room without moving the field or the Shortcut header.
    func configureList(_ list: NSTableView, width: CGFloat, title: String, nameWidth: CGFloat = 244) {
        styleList(list)
        let scrollbarWidth = Self.listScrollbarWidth
        let first = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        first.title = title
        first.resizingMask = []
        first.minWidth = 110
        first.maxWidth = max(width - 190, nameWidth)
        first.width = nameWidth
        let second = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shortcut"))
        second.title = "Shortcut"
        second.minWidth = min(190, width - nameWidth - scrollbarWidth)
        second.width = width - first.width - scrollbarWidth
        second.resizingMask = []
        for column in [first, second] { list.addTableColumn(column) }
        // Leave the trailing header lane unadorned.
        list.cornerView = nil
        list.allowsColumnReordering = false
        list.allowsColumnResizing = false
    }
    // What every list shares, the Shelf picker's included: plain rows of one height on
    // the list surface, and no native header.
    func styleList(_ list: NSTableView) {
        // Plain rows keep the same margins when AppKit switches scroller styles.
        list.style = .plain
        list.headerView = nil
        list.rowHeight = Self.appRowHeight
        list.intercellSpacing = .zero
        list.backgroundColor = .clear
        // Match Mos: changing the viewport never redistributes column widths.
        list.columnAutoresizingStyle = .noColumnAutoresizing
    }
    func addListHeader(to content: NSView, table: NSTableView, size: NSSize) {
        let header = PlainListHeaderView(frame: NSRect(x: 0, y: size.height - ListGeometry.headerHeight,
                                                       width: size.width, height: ListGeometry.headerHeight))
        header.tableView = table
        header.autoresizingMask = [.width, .minYMargin]
        content.addSubview(header)
        header.needsLayout = true
    }
    // Rows are rebuilt on every reload; icon lookups hit Launch Services and the disk.
    private static let listIcons = NSCache<NSString, NSImage>()
    func makeListIcon(path: String) -> NSImageView {
        if let cached = Self.listIcons.object(forKey: path as NSString) { return makeListIcon(image: cached) }
        let image = NSWorkspace.shared.icon(forFile: path)
        Self.listIcons.setObject(image, forKey: path as NSString)
        return makeListIcon(image: image)
    }
    func makeListIcon(image: NSImage?) -> NSImageView {
        let icon = NSImageView(frame: Self.listIconFrame)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.image = image
        return icon
    }
    // An empty cell for `row` in `column`, with the column's index (0 is the name, 1 the
    // shortcut) and the cell's width.
    func makeListCell(in tableView: NSTableView, column: NSTableColumn?,
                      row: Int) -> (cell: NSView, columnIndex: Int, width: CGFloat) {
        let columnIndex = column.flatMap { tableView.tableColumns.firstIndex(of: $0) } ?? 0
        let width = tableView.frameOfCell(atColumn: columnIndex, row: row).width
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: width, height: Self.appRowHeight))
        return (cell, columnIndex, width)
    }
    // A name cell's contents: the icon, then the name in the `width` left of anything
    // else in the cell. Returns the name's label.
    @discardableResult
    func addListName(_ text: String, icon: NSImageView, to cell: NSView, width: CGFloat) -> NSTextField {
        cell.addSubview(icon)
        let name = NSTextField(labelWithString: text)
        name.frame = Self.listNameFrame
        name.frame.size.width = max(0, width - name.frame.minX - 6)
        name.autoresizingMask = [.width]
        name.font = .systemFont(ofSize: 13)
        name.lineBreakMode = .byTruncatingTail
        cell.addSubview(name)
        return name
    }
    // One clickable field showing the whole shortcut (“⇪M W”), right-aligned and
    // vertically centered in a list's shortcut column, that records and clears
    // `owner`'s shortcut. KeyRecorder draws it the way Rectangle's shortcut fields look.
    @discardableResult
    func addShortcutRecorder(to cell: NSView, width: CGFloat, for owner: ShortcutOwner, keys: [UInt16],
                             table: NSTableView, row: Int) -> KeyRecorder {
        let height = KeyRecorder.fieldHeight
        let recorder = KeyRecorder(frame: NSRect(x: width - ListGeometry.shortcutRecorderWidth,
                                                 y: ((Self.appRowHeight - height) / 2).rounded(),
                                                 width: ListGeometry.shortcutRecorderWidth, height: height))
        recorder.selectionTable = table
        recorder.autoresizingMask = [.minXMargin]
        recorder.shortcutKeys = keys
        recorder.maxKeys = owner.isWindow ? 1 : KeyboardState.maxShortcutKeys
        recorder.capsAvailable = { [weak self] in self?.tap != nil }
        recorder.onStart = { [weak self, weak table] in
            self?.state.cancelGesture()
            table?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        recorder.onKeys = { [weak self, weak recorder] keys in
            guard let self = self, let recorder = recorder else { return false }
            return self.assignShortcut(keys, to: owner, recorder: recorder)
        }
        recorder.onClear = { [weak self] in self?.clearShortcut(of: owner) }
        cell.addSubview(recorder)
        return recorder
    }
    // Without a bottom bar (the Shelf picker), the rows end a gap above the bottom edge.
    func makeListScroll(size: NSSize, headerHeight: CGFloat = 0, bottomBar: Bool = true) -> NSScrollView {
        let headerSpacing: CGFloat = headerHeight > 0 ? ListGeometry.spacing : 0
        let footer = (bottomBar ? ListGeometry.bottomBarHeight + ListGeometry.bottomRuleHeight : 0) + ListGeometry.spacing
        let scroll = NSScrollView(frame: NSRect(x: 0, y: footer,
                                                width: size.width,
                                                height: size.height - footer - headerHeight - headerSpacing))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        return scroll
    }
    // A Preferences list page's table, configured by configureList, in a scroll view
    // between the column header and the bottom bar. Returns the scroll view.
    @discardableResult
    func addList(_ table: NSTableView, to page: NSView, title: String, nameWidth: CGFloat = 244) -> NSScrollView {
        let size = page.bounds.size
        let scroll = makeListScroll(size: size, headerHeight: ListGeometry.headerHeight)
        configureList(table, width: size.width, title: title, nameWidth: nameWidth)
        scroll.documentView = table
        scroll.tile()
        page.addSubview(scroll)
        addListHeader(to: page, table: table, size: size)
        return scroll
    }
    // Gray text centered over a list with no rows.
    func addEmptyListLabel(_ text: String, over scroll: NSScrollView, to page: NSView) -> NSTextField {
        let empty = NSTextField(labelWithString: text)
        empty.font = .systemFont(ofSize: 13)
        empty.textColor = .secondaryLabelColor
        empty.alignment = .center
        empty.frame = NSRect(x: 0, y: scroll.frame.midY - 9, width: scroll.frame.width, height: 18)
        empty.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        page.addSubview(empty)
        return empty
    }
    func makeListButton(symbol: String, x: CGFloat, action: @escaping () -> Void, tip: String) -> NSButton {
        let button = ListActionButton(action: action)
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .light))
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.frame = NSRect(x: x, y: ListGeometry.bottomBarY(28), width: 28, height: 28)
        button.setAccessibilityLabel(tip)
        return button
    }
    func addListControls(to content: NSView, width: CGFloat,
                         add: @escaping () -> Void, remove: @escaping () -> Void, itemName: String) {
        addListBottomDivider(to: content, width: width)
        content.addSubview(makeListButton(symbol: "plus", x: 8, action: add, tip: "Add \(itemName)"))
        content.addSubview(makeListButton(symbol: "minus", x: 38, action: remove, tip: "Remove \(itemName)"))
    }
    // The rule above a list's bottom bar.
    func addListBottomDivider(to content: NSView, width: CGFloat) {
        let divider = NSBox(frame: NSRect(x: 0, y: ListGeometry.bottomBarHeight, width: width,
                                          height: ListGeometry.bottomRuleHeight))
        divider.boxType = .separator
        divider.autoresizingMask = [.width]
        content.addSubview(divider)
    }
    // A "?" in a list's bottom bar, right-aligned at `trailing`, explaining the page's feature.
    @discardableResult
    func addListHelp(_ items: [HelpButton.Item], to content: NSView, trailing: CGFloat) -> HelpButton {
        let help = HelpButton(items)
        help.frame.origin = NSPoint(x: trailing - help.frame.width, y: ListGeometry.bottomBarY(help.frame.height))
        help.autoresizingMask = [.minXMargin]
        content.addSubview(help)
        return help
    }

    // App List, Folders and Websites: the list between its column header and a
    // bottom bar with + / −, a search field and ?, and a gray label over the list when it
    // has no entries or the search matches none. Everything these pages share is built
    // here; the spec holds only what differs. Windows has fixed actions and builds its own page.
    func addEntryListPage(_ spec: ListPageSpec, list: SearchableList, to page: NSView) {
        let width = page.bounds.width
        let scroll = addList(list.listTable, to: page, title: spec.entryName, nameWidth: spec.nameWidth)
        addListControls(to: page, width: width, add: spec.add, remove: spec.remove, itemName: spec.entryName)
        let shortcutHelp: [HelpButton.Item] = [("Caps + key, release Caps", spec.shortcutAction),
                                               ("Set a shortcut", "Hold ⇪ + up to 3 keys")]
        let help = addListHelp(shortcutHelp
                               + spec.help
                               + [("⌘F", "Search by name"),
                                  ("Type in the list", "Jump to one by name")],
                               to: page, trailing: width - ListGeometry.trailingInset)
        let search = list.search
        let field = NSSearchField()
        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.placeholderString = "Search"
        field.sendsSearchStringImmediately = true
        field.target = search
        field.action = #selector(ListSearch.fieldChanged(_:))
        field.delegate = search
        field.setAccessibilityLabel("Search \(spec.pluralName.lowercased())")
        field.sizeToFit()
        let fieldWidth: CGFloat = 160
        let fieldHeight = field.frame.height
        field.frame = NSRect(x: help.frame.minX - 8 - fieldWidth, y: ListGeometry.bottomBarY(fieldHeight).rounded(),
                             width: fieldWidth, height: fieldHeight)
        field.autoresizingMask = [.minXMargin]
        page.addSubview(field)
        search.field = field
        search.emptyText = "No \(spec.pluralName). Click + to add one."
        search.noMatchText = "No Matching \(spec.pluralName)"
        search.emptyLabel = addEmptyListLabel("", over: scroll, to: page)
        list.reload()
    }
    // − on a list page: removes the list's selected entries from the entries at
    // `entries`, saves, and selects the row that took the first one's place. Rows may be
    // filtered by the search, so selected rows are mapped back to their entries first.
    func removeSelectedEntries<Entry>(of list: SearchableList?,
                                      from entries: ReferenceWritableKeyPath<AppDelegate, [Entry]>,
                                      save: () -> Void) {
        guard let list = list, let firstRow = list.listTable.selectedRowIndexes.first else { return }
        let selection = list.selectedEntryIndices
        guard ListSelection.remove(selection, from: &self[keyPath: entries]) else { return }
        save()
        ListSelection.selectAfterRemoval(at: firstRow, in: list.listTable)
    }
    // The list on Preferences tab `index`, if that tab is a list page.
    func entryList(onPage index: Int) -> SearchableList? {
        switch Self.preferenceTabs[index].id {
        case "apps": return applicationList
        case "folders": return folderList
        case "websites": return websiteList
        default: return nil
        }
    }
    // The list page shown in Preferences, if the current tab is one.
    var visibleEntryList: SearchableList? {
        window?.isVisible == true ? entryList(onPage: selectedPage) : nil
    }
    // Command-F on a list page.
    @objc func findInList() {
        guard let list = visibleEntryList else { NSSound.beep(); return }
        list.search.focus()
    }

    // The Add/Edit sheet Websites and Folders share: a title, an optional message, one
    // labeled text field per row, and `button` with Cancel. A field that `choosesFolder`
    // has a Choose… button that fills it from a folder picker. A field with a
    // `placeholder` shows it in gray, worked out again from every field's text as the
    // person types or chooses. `button` is disabled while a `required` field is empty.
    // The first field has focus and Tab cycles through them. `completion` gets the fields' text, in order, when the person clicks `button`.
    func showFieldSheet(on owner: NSWindow?, title: String, message: String = "", button: String,
                        fields: [SheetField], completion: @escaping ([String]) -> Void) {
        showFieldSheet(on: owner, title: title, message: message, button: button, fields: fields,
                       checkbox: nil) { values, _ in completion(values) }
    }
    // The same sheet with a `checkbox` under the fields, lined up with them;
    // `completion` also gets whether it is checked.
    func showFieldSheet(on owner: NSWindow?, title: String, message: String = "", button: String,
                        fields: [SheetField], checkbox: SheetCheckbox?,
                        completion: @escaping ([String], Bool) -> Void) {
        guard let owner = owner, owner.attachedSheet == nil, !fields.isEmpty else { return }
        let alert = NSAlert()
        let confirm = alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let labelWidth = ceil(fields.map { ($0.label as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0) + 2
        let fieldWidth: CGFloat = 280, rowHeight: CGFloat = 22, spacing: CGFloat = 8
        let chooseWidth: CGFloat = 84, checkboxHeight: CGFloat = 18
        let fieldsHeight = CGFloat(fields.count) * rowHeight + CGFloat(fields.count - 1) * spacing
        let height = fieldsHeight + (checkbox == nil ? 0 : spacing + checkboxHeight)
        let form = NSView(frame: NSRect(x: 0, y: 0, width: labelWidth + 8 + fieldWidth, height: height))
        var textFields: [NSTextField] = []
        // Placeholders follow the text in every field, and `button` waits for the required ones.
        let refreshFields: () -> Void = {
            let values = textFields.map { $0.stringValue }
            for (field, item) in zip(textFields, fields) {
                if let placeholder = item.placeholder { field.placeholderString = placeholder(values) }
            }
            confirm.isEnabled = !zip(values, fields).contains { value, item in
                item.required && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
        textFields = fields.enumerated().map { index, item in
            let y = height - CGFloat(index + 1) * rowHeight - CGFloat(index) * spacing
            let label = NSTextField(labelWithString: item.label)
            label.font = font
            label.alignment = .right
            label.frame = NSRect(x: 0, y: y + 3, width: labelWidth, height: 16)
            form.addSubview(label)
            let width = item.choosesFolder ? fieldWidth - chooseWidth - 8 : fieldWidth
            let field = NSTextField(frame: NSRect(x: labelWidth + 8, y: y, width: width, height: rowHeight))
            field.stringValue = item.value
            field.lineBreakMode = .byTruncatingTail
            field.cell?.usesSingleLineMode = true
            form.addSubview(field)
            if item.choosesFolder {
                let choose = ListActionButton { [weak alert, weak field] in
                    guard let alert = alert, let field = field else { return }
                    Self.chooseFolder(for: field, on: alert.window, chosen: refreshFields)
                }
                choose.title = "Choose…"
                choose.bezelStyle = .rounded
                choose.frame = NSRect(x: field.frame.maxX + 8, y: y - 3, width: chooseWidth, height: 28)
                form.addSubview(choose)
            }
            return field
        }
        let checkButton = checkbox.map { item -> NSButton in
            let box = NSButton(checkboxWithTitle: item.title, target: nil, action: nil)
            box.state = item.isOn ? .on : .off
            box.frame = NSRect(x: labelWidth + 8, y: 0, width: fieldWidth, height: checkboxHeight)
            form.addSubview(box)
            return box
        }
        let keyViews: [NSView] = textFields + (checkButton.map { [$0] } ?? [])
        for (index, view) in keyViews.enumerated() {
            view.nextKeyView = keyViews[(index + 1) % keyViews.count]
        }
        refreshFields()
        let observers: [NSObjectProtocol] = fields.contains(where: { $0.placeholder != nil || $0.required })
            ? textFields.map { field in
                NotificationCenter.default.addObserver(forName: NSControl.textDidChangeNotification,
                                                       object: field, queue: .main) { _ in refreshFields() }
            } : []
        alert.messageText = title
        alert.informativeText = message
        alert.accessoryView = form
        alert.window.initialFirstResponder = textFields[0]
        alert.beginSheetModal(for: owner) { response in
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            guard response == .alertFirstButtonReturn else { return }
            completion(textFields.map { $0.stringValue }, checkButton?.state == .on)
        }
    }
    // Choose…: a folder picker over the sheet, starting at the folder already typed;
    // the chosen folder replaces the field's text ("~/Projects/Clutch").
    private static func chooseFolder(for field: NSTextField, on sheet: NSWindow, chosen: @escaping () -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let typed = existingFolder(atLocation: field.stringValue) { panel.directoryURL = URL(fileURLWithPath: typed, isDirectory: true) }
        panel.beginSheetModal(for: sheet) { response in
            guard response == .OK, let url = panel.url else { return }
            field.stringValue = (url.standardizedFileURL.path as NSString).abbreviatingWithTildeInPath
            chosen()
        }
    }
}

// The checkbox under showFieldSheet's fields, and whether it starts checked.
struct SheetCheckbox {
    var title: String
    var isOn: Bool
}

// One row of showFieldSheet.
struct SheetField {
    var label: String
    var value: String
    var choosesFolder = false
    // Gray text shown while the field is empty, from every field's current text, in order.
    var placeholder: (([String]) -> String)? = nil
    // The sheet's button stays disabled while this field is empty.
    var required = false
}

// What one list page differs in; addEntryListPage builds the rest the same way.
struct ListPageSpec {
    // The first column's title and the + / − tips: "Application".
    var entryName: String
    // The empty and no-match labels: "Applications".
    var pluralName: String
    var nameWidth: CGFloat = 244
    // What Caps + an entry's shortcut does, first in ?: "Switch to the app".
    var shortcutAction: String
    // This page's own ? rows, between the shared ones.
    var help: [HelpButton.Item]
    var add: () -> Void
    var remove: () -> Void
}
