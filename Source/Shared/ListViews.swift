import Cocoa

enum ListGeometry {
    static let shortcutRecorderWidth: CGFloat = 130
    // A label's text starts this far inside its frame; the Shortcut header's text lines
    // up with the left edge of the shortcut fields below it, which end at the column's edge.
    static let labelTextInset: CGFloat = 2
    static let leadingInset: CGFloat = 16
    static let trailingInset: CGFloat = 12
}

// Match Mos's shared backdrop; lists and scrollers reveal this same surface.
final class ListSurface: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }
    private func configure() {
        wantsLayer = true
        material = .toolTip
        blendingMode = .behindWindow
        state = .active
    }
}

// The header sits outside the scroll view, so its rule always spans the page.
final class PlainListHeaderView: NSView {
    weak var tableView: NSTableView?
    override var isFlipped: Bool { true }
    let firstLabel = NSTextField(labelWithString: "")
    let secondLabel = NSTextField(labelWithString: "")
    let bottomRule = NSBox()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }
    private func configure() {
        for label in [firstLabel, secondLabel] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }
        bottomRule.boxType = .separator
        addSubview(bottomRule)
        needsLayout = true
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }
    override func layout() {
        super.layout()
        guard let table = tableView, table.tableColumns.count == 2 else { return }
        let firstColumn = table.tableColumns[0]
        let secondColumn = table.tableColumns[1]
        let firstBody = table.numberOfRows > 0 ? table.frameOfCell(atColumn: 0, row: 0)
            : NSRect(x: 0, y: 0, width: firstColumn.width, height: 0)
        let secondBody = table.numberOfRows > 0 ? table.frameOfCell(atColumn: 1, row: 0)
            : NSRect(x: firstColumn.width, y: 0, width: secondColumn.width, height: 0)
        firstLabel.stringValue = firstColumn.title
        secondLabel.stringValue = secondColumn.title
        firstLabel.frame = NSRect(x: firstBody.minX + ListGeometry.leadingInset, y: 7, width: max(0, firstBody.width - ListGeometry.leadingInset - ListGeometry.trailingInset), height: 18)
        let secondX = secondBody.maxX - ListGeometry.shortcutRecorderWidth - ListGeometry.labelTextInset
        secondLabel.frame = NSRect(x: secondX, y: 7, width: max(0, secondBody.maxX - secondX), height: 18)
        bottomRule.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
    }
}

final class InsetListRowView: NSTableRowView {
    static let selectionInset: CGFloat = 6
    override func drawSelection(in dirtyRect: NSRect) {
        let inset = Self.selectionInset
        // The viewport already excludes a visible legacy scrollbar. Hidden overlay
        // scrollers can still report a knob rect, so do not use it for row geometry.
        let scroll = enclosingScrollView
        let hasVisibleLegacyScroller = scroll?.scrollerStyle == .legacy
            && scroll?.hasVerticalScroller == true
            && scroll?.verticalScroller?.isHidden == false
        let trailingInset: CGFloat = hasVisibleLegacyScroller ? 0 : inset
        let selectionRect = NSRect(x: bounds.minX + inset, y: bounds.minY,
                                   width: max(0, bounds.width - inset - trailingInset),
                                   height: bounds.height)
        let color = isEmphasized ? NSColor.selectedContentBackgroundColor
                                 : NSColor.unemphasizedSelectedContentBackgroundColor
        color.setFill()
        // AppKit tracks adjacent selections and redraws the affected rows.
        // Move joined corners outside the row so only the group's ends are rounded.
        let radius: CGFloat = 6
        var joinedRect = selectionRect
        let joinsMinY = isFlipped ? isPreviousRowSelected : isNextRowSelected
        let joinsMaxY = isFlipped ? isNextRowSelected : isPreviousRowSelected
        if joinsMinY {
            joinedRect.origin.y -= radius
            joinedRect.size.height += radius
        }
        if joinsMaxY { joinedRect.size.height += radius }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: selectionRect).addClip()
        NSBezierPath(roundedRect: joinedRect, xRadius: radius, yRadius: radius).fill()
    }
}

final class ListActionButton: NSButton {
    private let handler: () -> Void
    init(action: @escaping () -> Void) {
        handler = action
        super.init(frame: .zero)
        title = ""
        target = self
        self.action = #selector(invoke)
    }
    required init?(coder: NSCoder) { fatalError("Use init(action:)") }
    @objc private func invoke() { handler() }
}

enum ListSelection {
    static func proposed(_ indexes: IndexSet, in table: NSTableView) -> IndexSet {
        NSApp.currentEvent?.type == .leftMouseDragged ? table.selectedRowIndexes : indexes
    }
    // A right-click selects the clicked row unless it is already part of the selection,
    // like Finder, so the context menu acts on it, and makes the table first responder
    // so the selection shows in the accent color. Drawn now: the menu's tracking loop
    // starts before the next display pass. nil outside the rows.
    @discardableResult
    static func selectForMenu(_ event: NSEvent, in table: NSTableView) -> Int? {
        let row = table.row(at: table.convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        if table.window?.firstResponder !== table { table.window?.makeFirstResponder(table) }
        if !table.selectedRowIndexes.contains(row) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        table.displayIfNeeded()
        return row
    }
    // False when no index was valid, so there is nothing to save. Callers reselect by
    // table row, since a search may be filtering the rows.
    static func remove<Item>(_ indexes: IndexSet, from items: inout [Item]) -> Bool {
        let valid = indexes.intersection(IndexSet(integersIn: items.indices))
        guard !valid.isEmpty else { return false }
        for row in valid.reversed() { items.remove(at: row) }
        return true
    }
}

// The native round "?" button. Clicking it shows a small two-column popover below
// the button, as in Mos: what to press on the left, what it does on the right.
// Clicking again, clicking elsewhere, or Escape closes it.
final class HelpButton: NSButton {
    typealias Item = (keys: String, action: String)
    let items: [Item]
    private var popover: NSPopover?

    init(_ items: [Item]) {
        self.items = items
        super.init(frame: .zero)
        bezelStyle = .helpButton
        title = ""
        controlSize = .small
        target = self
        action = #selector(togglePopover)
        setAccessibilityLabel("Help")
        setAccessibilityHelp(items.map { "\($0.keys): \($0.action)" }.joined(separator: "\n"))
        sizeToFit()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func makeContent() -> NSView {
        let fontSize = NSFont.smallSystemFontSize
        let rows: [[NSView]] = items.map { item in
            let keys = NSTextField(labelWithString: item.keys)
            keys.font = .systemFont(ofSize: fontSize, weight: .semibold)
            let action = NSTextField(wrappingLabelWithString: item.action)
            action.font = .systemFont(ofSize: fontSize)
            action.textColor = .secondaryLabelColor
            action.preferredMaxLayoutWidth = 180
            return [keys, action]
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 6
        grid.columnSpacing = 12
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .leading
        let size = grid.fittingSize
        let inset: CGFloat = 10
        grid.frame = NSRect(x: inset, y: inset, width: size.width, height: size.height)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: size.width + inset * 2,
                                           height: size.height + inset * 2))
        content.addSubview(grid)
        return content
    }

    @objc private func togglePopover() {
        if let shown = popover, shown.isShown {
            shown.performClose(nil)
            return
        }
        let controller = NSViewController()
        controller.view = makeContent()
        let newPopover = NSPopover()
        newPopover.behavior = .transient
        newPopover.contentViewController = controller
        popover = newPopover
        // Below the button on screen; AppKit flips it above when there is no room.
        newPopover.show(relativeTo: bounds, of: self, preferredEdge: isFlipped ? .maxY : .minY)
    }
}
