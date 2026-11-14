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
        let (cell, columnIndex, width) = owner.makeListCell(in: tableView, column: column, row: row)
        let command = commands[row]
        if columnIndex == 0 {
            let symbolImage = NSImage(systemSymbolName: command.symbol, accessibilityDescription: command.title)
                ?? NSImage(systemSymbolName: command.fallbackSymbol, accessibilityDescription: command.title)
            let icon = owner.makeListIcon(image: symbolImage?.withSymbolConfiguration(.init(pointSize: 15, weight: .regular)))
            icon.imageScaling = .scaleProportionallyDown
            icon.contentTintColor = .secondaryLabelColor
            owner.addListName(command.title, icon: icon, to: cell, width: width)
            cell.toolTip = command.detail
        } else {
            owner.addShortcutRecorder(to: cell, width: width, for: .window(command),
                                      keys: owner.windowShortcuts.key(for: command).map { [$0] } ?? [],
                                      table: tableView, row: row)
        }
        return cell
    }
}

extension AppDelegate {
    func saveWindowShortcuts() {
        windowShortcuts.save()
        windowShortcutList?.table.reloadData()
    }
    // The App List layout, with Restore Defaults in place of + / − in the bottom bar.
    func addWindowsPage(to content: NSView) {
        let list = WindowShortcutListController(owner: self)
        windowShortcutList = list
        // Every action fits (the Preferences window is sized for them), so the list stays put:
        // no scrollbar, no rubber-band bounce.
        let scroll = addList(list.table, to: content, title: "Action")
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        let width = content.bounds.width
        addListBottomDivider(to: content, width: width)
        let button = ListActionButton(action: { [weak self] in self?.restoreDefaultWindowShortcuts() })
        button.title = "Restore Defaults"
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.sizeToFit()
        button.frame.origin = NSPoint(x: width - ListGeometry.trailingInset - button.frame.width,
                                      y: ListGeometry.bottomBarY(button.frame.height))
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
