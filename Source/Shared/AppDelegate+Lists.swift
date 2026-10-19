import Cocoa

extension AppDelegate {
    func configureList(_ list: NSTableView, width: CGFloat, columnID: String) {
        // Plain rows keep the same margins when AppKit switches scroller styles.
        list.style = .plain
        let folders = columnID == "folder"
        let first = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(columnID))
        first.title = folders ? "Name" : (columnID == "window" ? "Action" : "Application")
        first.minWidth = 110
        first.maxWidth = width - (folders ? 180 : 190)
        first.width = folders ? 144 : 244
        first.resizingMask = []
        let second = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(columnID + "Detail"))
        second.title = folders ? "Path" : "Shortcut"
        second.minWidth = folders ? 180 : 190
        // Reserve the native scrollbar lane in both modes so fixed controls stay visible.
        let scrollbarWidth = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
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
        let icon = NSImageView(frame: Self.listIconFrame.offsetBy(dx: ListGeometry.leadingInset - Self.listIconFrame.minX, dy: 0))
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
        name.frame = Self.listNameFrame.offsetBy(dx: ListGeometry.leadingInset - Self.listIconFrame.minX, dy: 0)
        name.frame.size.width = max(0, width - name.frame.minX - 6)
        name.autoresizingMask = [.width]
        name.font = .systemFont(ofSize: 13)
        name.lineBreakMode = .byTruncatingTail
    }
    // “Caps +” and a clickable key field, right-aligned in a list's shortcut column.
    func addShortcutRecorder(to cell: NSView, width: CGFloat, key: UInt16, table: NSTableView) -> KeyRecorder {
        let prefix = NSTextField(labelWithString: "Caps +")
        let shortcutX = ListGeometry.shortcutOrigin(in: NSRect(x: 0, y: 0, width: width, height: 0))
        prefix.frame = NSRect(x: shortcutX, y: Self.listNameFrame.minY, width: ListGeometry.shortcutPrefixWidth, height: Self.listNameFrame.height)
        prefix.autoresizingMask = [.minXMargin]
        prefix.font = .systemFont(ofSize: 13)
        cell.addSubview(prefix)
        let recorder = KeyRecorder(frame: NSRect(x: shortcutX + ListGeometry.shortcutRecorderOffset, y: 3, width: ListGeometry.shortcutRecorderWidth, height: 24))
        recorder.selectionTable = table
        recorder.autoresizingMask = [.minXMargin]
        recorder.bezelStyle = .rounded
        // Keep the native key button's white Aqua appearance on the list surface.
        recorder.appearance = NSAppearance(named: .aqua)
        recorder.controlSize = .small
        recorder.font = .systemFont(ofSize: 12)
        recorder.title = keyName(key) ?? "Click to set"
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
        let divider = NSBox(frame: NSRect(x: 0, y: 32, width: width, height: 1))
        divider.boxType = .separator
        divider.autoresizingMask = [.width]
        content.addSubview(divider)
        content.addSubview(makeListButton(symbol: "plus", x: 8 + leadingInset, action: add, tip: "Add \(itemName)"))
        content.addSubview(makeListButton(symbol: "minus", x: 38 + leadingInset, action: remove, tip: "Remove \(itemName)"))
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
}
