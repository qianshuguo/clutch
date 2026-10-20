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
            let icon = NSImageView(frame: AppDelegate.listIconFrame.offsetBy(dx: ListGeometry.leadingInset - AppDelegate.listIconFrame.minX, dy: 0))
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
        let recorder = owner.addShortcutRecorder(to: cell, width: cellWidth,
                                                 key: owner.windowShortcuts.key(for: command), table: tableView)
        recorder.onStart = { [weak self] in
            self?.owner.state.cancelGesture()
            self?.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        recorder.onKeys = { [weak self, weak recorder] code, _ in
            guard let self = self, let recorder = recorder else { return false }
            return self.owner.assignWindowShortcut(code, to: command, recorder: recorder)
        }
        return cell
    }
}

extension AppDelegate {
    // Same rule as App List: one key, one owner. Taking a key from an app (used alone or
    // starting two-key shortcuts) or another action asks first and names who loses it.
    func assignWindowShortcut(_ code: UInt16, to command: WindowCommand, recorder: KeyRecorder) -> Bool {
        guard shortcutKeyAvailable(code) else { return false }
        let otherCommand = windowShortcuts.command(for: code).flatMap { $0 == command ? nil : $0 }
        // As if setting the key alone: catches apps using it alone and two-key shortcuts starting with it.
        let apps = shortcutConflicts(code, nil, excluding: nil)
        let appNames = apps.indices.map { bindings[$0].name }
        let replacedNames: [String] = appNames + (otherCommand.map { [$0.title] } ?? [])
        if !replacedNames.isEmpty {
            recorder.cancelRecording()
            let inUse = apps.inUse + (otherCommand.map { ["Caps + \(keyName(code) ?? "?") already runs \($0.title)."] } ?? [])
            guard confirmShortcutReplacement(inUse: inUse, shortcut: keyName(code) ?? "?", newOwner: command.title,
                                             losers: replacedNames) else { return false }
        }
        if !appNames.isEmpty {
            for index in bindings.indices where bindings[index].hasShortcut && bindings[index].key == code { bindings[index].clearShortcut() }
            saveBindings()
        }
        windowShortcuts.assign(code, to: command)
        // Finish recording before reload removes the focused view.
        recorder.recording = false
        saveWindowShortcuts()
        let replacement = replacedNames.isEmpty ? "" : ". Cleared shortcut for \(replacedNames.joined(separator: ", "))"
        setStatus("Saved: \(command.title) → Caps + \(keyName(code) ?? "?")\(replacement)")
        return true
    }
    func saveWindowShortcuts() {
        windowShortcuts.save()
        windowShortcutList?.table.reloadData()
    }
    // Bottom bar matching App List's, with Restore Defaults in place of + / −.
    func addWindowShortcutControls(to content: NSView, width: CGFloat) {
        let divider = NSBox(frame: NSRect(x: 0, y: 32, width: width, height: 1))
        divider.boxType = .separator
        divider.autoresizingMask = [.width]
        content.addSubview(divider)
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
            ("Set a shortcut", "Hold Caps + a key"),
            ("Left / Right Half again", "Cycle ½ → ⅔ → ⅓"),
            ("Fill Height again", "Fill the screen"),
            ("Restore", "Size before HyperCaps moved it"),
            ("Hover an action", "Full description")
        ], to: content, trailing: button.frame.minX - 8)
    }
    func restoreDefaultWindowShortcuts() {
        (window?.firstResponder as? KeyRecorder)?.cancelRecording()
        let defaults = WindowShortcuts.defaults
        let conflicts = bindings.filter { $0.key != unassignedKey && defaults.command(for: $0.key) != nil }
        if !conflicts.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Restore default window shortcuts?"
            let list = conflicts.map { "\($0.name) (Caps + \(shortcutName($0.key, $0.secondKey) ?? "?"))" }.joined(separator: ", ")
            alert.informativeText = "These apps will stay in App List without a shortcut: \(list)."
            let restoreButton = alert.addButton(withTitle: "Restore")
            restoreButton.keyEquivalent = "\r"
            restoreButton.keyEquivalentModifierMask = []
            let cancelButton = alert.addButton(withTitle: "Cancel")
            cancelButton.keyEquivalent = "\u{1b}"
            cancelButton.keyEquivalentModifierMask = []
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            for index in bindings.indices where defaults.command(for: bindings[index].key) != nil {
                bindings[index].clearShortcut()
            }
            saveBindings()
        }
        windowShortcuts = defaults
        saveWindowShortcuts()
        setStatus("Restored default window shortcuts.")
    }
}
