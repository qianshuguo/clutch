import Cocoa

extension AppDelegate {
    // Reserve the native scrollbar lane in both modes so fixed controls stay visible.
    static var listScrollbarWidth: CGFloat { NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) }
    // Two fixed columns: `title` (Application, Name, Action) and Shortcut. The shortcut
    // field is right-aligned in its column, so a wider first column (`nameWidth`) gives
    // names more room without moving the field or the Shortcut header.
    func configureList(_ list: NSTableView, width: CGFloat, title: String, nameWidth: CGFloat = 244) {
        // Plain rows keep the same margins when AppKit switches scroller styles.
        list.style = .plain
        let scrollbarWidth = Self.listScrollbarWidth
        let first = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        first.title = title
        first.minWidth = 110
        first.maxWidth = max(width - 190, nameWidth)
        first.width = nameWidth
        first.resizingMask = []
        let second = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shortcut"))
        second.title = "Shortcut"
        second.minWidth = min(190, width - nameWidth - scrollbarWidth)
        second.width = width - first.width - scrollbarWidth
        second.resizingMask = []
        for column in [first, second] { list.addTableColumn(column) }
        list.headerView = nil
        // Leave the trailing header lane unadorned.
        list.cornerView = nil
        list.allowsColumnReordering = false
        list.allowsColumnResizing = false
        list.rowHeight = Self.appRowHeight
        list.intercellSpacing = .zero
        list.backgroundColor = .clear
        // Match Mos: changing the viewport never redistributes column widths.
        list.columnAutoresizingStyle = .noColumnAutoresizing
    }
    func addListHeader(to content: NSView, table: NSTableView, size: NSSize) {
        let header = PlainListHeaderView(frame: NSRect(x: 0, y: size.height - 28,
                                                       width: size.width, height: 28))
        header.tableView = table
        header.autoresizingMask = [.width, .minYMargin]
        content.addSubview(header)
        header.needsLayout = true
    }
    // Rows are rebuilt on every reload; icon lookups hit Launch Services and the disk.
    private static let listIcons = NSCache<NSString, NSImage>()
    func makeListIcon(path: String) -> NSImageView {
        let icon = NSImageView(frame: Self.listIconFrame)
        icon.imageScaling = .scaleProportionallyUpOrDown
        if let cached = Self.listIcons.object(forKey: path as NSString) {
            icon.image = cached
        } else {
            let image = NSWorkspace.shared.icon(forFile: path)
            Self.listIcons.setObject(image, forKey: path as NSString)
            icon.image = image
        }
        return icon
    }
    func configureListName(_ name: NSTextField, width: CGFloat) {
        name.frame = Self.listNameFrame
        name.frame.size.width = max(0, width - name.frame.minX - 6)
        name.autoresizingMask = [.width]
        name.font = .systemFont(ofSize: 13)
        name.lineBreakMode = .byTruncatingTail
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
        recorder.maxKeys = owner.isWindow ? 1 : AppShortcut.maxKeys
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
    func makeListScroll(size: NSSize, headerHeight: CGFloat = 0,
                        fitsTableToViewport: Bool = false) -> ListScrollView {
        let headerSpacing: CGFloat = headerHeight > 0 ? 6 : 0
        let footerSpacing: CGFloat = 6
        let scroll = ListScrollView(frame: NSRect(x: 0, y: 33 + footerSpacing,
                                                width: size.width,
                                                height: size.height - 33 - headerHeight - headerSpacing - footerSpacing))
        scroll.fitsTableToViewport = fitsTableToViewport
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
    func makeListButton(symbol: String, x: CGFloat, action: @escaping () -> Void, tip: String) -> NSButton {
        let button = ListActionButton(action: action)
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .light))
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.frame = NSRect(x: x, y: 2, width: 28, height: 28)
        button.setAccessibilityLabel(tip)
        return button
    }
    func addListControls(to content: NSView, width: CGFloat, leadingInset: CGFloat = 0,
                         add: @escaping () -> Void, remove: @escaping () -> Void, itemName: String) {
        addListBottomDivider(to: content, width: width)
        content.addSubview(makeListButton(symbol: "plus", x: 8 + leadingInset, action: add, tip: "Add \(itemName)"))
        content.addSubview(makeListButton(symbol: "minus", x: 38 + leadingInset, action: remove, tip: "Remove \(itemName)"))
    }
    // The rule above a list's 32 pt bottom bar.
    func addListBottomDivider(to content: NSView, width: CGFloat) {
        let divider = NSBox(frame: NSRect(x: 0, y: 32, width: width, height: 1))
        divider.boxType = .separator
        divider.autoresizingMask = [.width]
        content.addSubview(divider)
    }
    // A "?" in a list's bottom bar, right-aligned at `trailing`, explaining the page's feature.
    @discardableResult
    func addListHelp(_ items: [HelpButton.Item], to content: NSView, trailing: CGFloat) -> HelpButton {
        let help = HelpButton(items)
        help.frame.origin = NSPoint(x: trailing - help.frame.width, y: (32 - help.frame.height) / 2)
        help.autoresizingMask = [.minXMargin]
        content.addSubview(help)
        return help
    }

    // The Add/Edit sheet Websites and Folders share: a title, an optional message, one
    // labeled text field per row, and `button` with Cancel. A field that `choosesFolder`
    // has a Choose… button that fills it from a folder picker. A field with a
    // `placeholder` shows it in gray, worked out again from every field's text as the
    // person types or chooses. The first field has focus and Tab cycles through them.
    // `completion` gets the fields' text, in order, when the person clicks `button`.
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
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let labelWidth = ceil(fields.map { ($0.label as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0) + 2
        let fieldWidth: CGFloat = 280, rowHeight: CGFloat = 22, spacing: CGFloat = 8
        let chooseWidth: CGFloat = 84, checkboxHeight: CGFloat = 18
        let fieldsHeight = CGFloat(fields.count) * rowHeight + CGFloat(fields.count - 1) * spacing
        let height = fieldsHeight + (checkbox == nil ? 0 : spacing + checkboxHeight)
        let form = NSView(frame: NSRect(x: 0, y: 0, width: labelWidth + 8 + fieldWidth, height: height))
        var textFields: [NSTextField] = []
        // Placeholders follow the text in every field.
        let refreshPlaceholders: () -> Void = {
            let values = textFields.map { $0.stringValue }
            for (field, item) in zip(textFields, fields) {
                if let placeholder = item.placeholder { field.placeholderString = placeholder(values) }
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
                    Self.chooseFolder(for: field, on: alert.window, chosen: refreshPlaceholders)
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
        refreshPlaceholders()
        let observers: [NSObjectProtocol] = fields.contains(where: { $0.placeholder != nil })
            ? textFields.map { field in
                NotificationCenter.default.addObserver(forName: NSControl.textDidChangeNotification,
                                                       object: field, queue: .main) { _ in refreshPlaceholders() }
            } : []
        alert.messageText = title
        alert.informativeText = message
        alert.accessoryView = form
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
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
        let typed = (field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        if FileManager.default.isDirectory(atPath: typed) { panel.directoryURL = URL(fileURLWithPath: typed, isDirectory: true) }
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
}
