import Cocoa

// Preferences > Windows: the App List layout with window actions on the left and
// their Caps shortcut on the right. Retained by AppDelegate with the preferences view tree.
final class WindowShortcutListController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    unowned let owner: AppDelegate
    let table = NSTableView()
    private let commands = WindowCommand.allCases

    init(owner: AppDelegate) {
        self.owner = owner
        super.init()
        table.delegate = self
        table.dataSource = self
        table.allowsMultipleSelection = false
        table.allowsTypeSelect = false
    }
    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
        ListSelection.proposed(proposedSelectionIndexes, in: tableView)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { commands.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        InsetListRowView()
    }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let columnIndex = column.flatMap { tableView.tableColumns.firstIndex(of: $0) } ?? 0
        let cellWidth = tableView.frameOfCell(atColumn: columnIndex, row: row).width
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: cellWidth, height: AppDelegate.appRowHeight))
        let command = commands[row]
        if columnIndex == 0 {
            let icon = NSImageView(frame: AppDelegate.listIconFrame)
            let symbolImage = NSImage(systemSymbolName: command.symbol, accessibilityDescription: command.title)
                ?? NSImage(systemSymbolName: command.fallbackSymbol, accessibilityDescription: command.title)
            icon.image = symbolImage?.withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
            icon.imageScaling = .scaleProportionallyDown
            icon.contentTintColor = .secondaryLabelColor
            cell.addSubview(icon)
            let name = NSTextField(labelWithString: command.title)
            owner.configureListName(name, width: cellWidth)
            cell.addSubview(name)
            cell.toolTip = command.detail
            return cell
        }
        owner.addShortcutRecorder(to: cell, width: cellWidth, for: .window(command),
                                  keys: owner.windowShortcuts.key(for: command).map { [$0] } ?? [],
                                  table: tableView, row: row)
        return cell
    }
}

extension AppDelegate {
    func saveWindowShortcuts() {
        windowShortcuts.save()
        windowShortcutList?.table.reloadData()
    }
    // Bottom bar matching App List's, with Restore Defaults in place of + / −.
    func addWindowShortcutControls(to content: NSView, width: CGFloat) {
        addListBottomDivider(to: content, width: width)
        let button = ListActionButton(action: { [weak self] in self?.restoreDefaultWindowShortcuts() })
        button.title = "Restore Defaults"
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.sizeToFit()
        button.frame.origin = NSPoint(x: width - 12 - button.frame.width, y: (32 - button.frame.height) / 2)
        button.autoresizingMask = [.minXMargin]
        content.addSubview(button)
        addListHelp([
            ("Set a shortcut", "Hold ⇪ + a key"),
            ("Holding Caps", "Preview; release Caps to apply"),
            ("Left / Right Half again", "Cycle ½ → ⅔ → ⅓"),
            ("Fill Height again", "Full height ⇄ full screen"),
            ("Restore", "Size before Clutch moved it"),
            ("Hover an action", "Full description")
        ], to: content, trailing: button.frame.minX - 8)
    }
    // App List, Folders and Websites shortcuts that start with a default window key lose them,
    // after asking.
    func restoreDefaultWindowShortcuts() {
        (window?.firstResponder as? KeyRecorder)?.cancelRecording()
        let defaults = WindowShortcuts.defaults
        let taken = allShortcuts.filter { entry in
            !entry.owner.isWindow && entry.keys.first.map { defaults.command(for: $0) != nil } == true
        }
        if !taken.isEmpty {
            let list = taken.map { "\($0.name) (\(shortcutLabel($0.keys)))" }.joined(separator: ", ")
            guard confirmAlert("Restore default window shortcuts?",
                               "These will stay in their lists without a shortcut: \(list).",
                               confirm: "Restore") else { return }
        }
        let cleared: [ShortcutChange] = taken.map { (owner: $0.owner, keys: []) }
        setShortcuts(cleared)
        windowShortcuts = defaults
        saveWindowShortcuts()
        logStatus("Restored default window shortcuts.")
    }
}
