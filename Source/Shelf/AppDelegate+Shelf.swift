import Cocoa

extension AppDelegate {
    static let shelfSearchBarHeight: CGFloat = 44

    func loadShelf() throws {
        shelf = try StoredList.load([ShelfEntry].self, forKey: DefaultsKey.shelf, description: "Shelf files") ?? []
    }
    func saveShelf() {
        StoredList.save(shelf, forKey: DefaultsKey.shelf)
        shelfList?.reload()
    }

    // Caps + Space, or Shelf… in the ⇪+ menu.
    @objc func showShelf() {
        guard !showingLaunchConfirmation else { return }
        // Files that were moved or deleted leave first.
        if Shelf.prune(&shelf) { saveShelf() }
        if shelfPanel == nil { createShelfPanel() }
        guard let panel = shelfPanel, let controller = shelfList else { return }
        // Each opening starts a new search, at the top file.
        controller.setFilter("")
        controller.reload()
        controller.select(row: 0)
        if !panel.isVisible { panel.previousFocus = PreviousFocus() }
        // Like Spotlight: the panel takes the keyboard without activating Clutch, so the
        // app in front stays active and its window keeps its active look.
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(controller.searchField ?? controller.table)
    }
    private func createShelfPanel() {
        let listSize = Self.shelfListSize
        let panelSize = NSSize(width: listSize.width, height: listSize.height + Self.shelfSearchBarHeight)
        // A titled panel for the native rounded corners, with its title bar hidden.
        // Non-activating: it becomes key while the app in front stays active. The style
        // has to be given here; adding it to an existing window does not take effect.
        let panel = ShelfPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                               styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.title = "Shelf"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(kind)?.isHidden = true
        }
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        // Stays up while files are dragged to it from another app.
        panel.hidesOnDeactivate = false
        panel.level = .floating
        // Opens on the Space in front, over full-screen apps too.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        let controller = ShelfListController(owner: self)
        let shell = ListSurface(frame: NSRect(origin: .zero, size: panelSize))

        // The list between the search field and the key hints.
        let scroll = makeListScroll(size: listSize)
        let table = controller.table
        styleList(table)
        // Like the other lists: a fixed column that leaves the scrollbar lane free in
        // both scroller styles, so an overlay scroller never covers the ⇪1–⇪9 hints.
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        let columnWidth = listSize.width - Self.listScrollbarWidth
        column.minWidth = columnWidth
        column.maxWidth = columnWidth
        column.width = columnWidth
        column.resizingMask = []
        table.addTableColumn(column)
        scroll.documentView = table
        scroll.tile()
        shell.addSubview(scroll)
        let empty = addEmptyListLabel("", over: scroll, to: shell)
        controller.emptyLabel = empty

        // What the keys do, in gray, under a divider.
        addListBottomDivider(to: shell, width: listSize.width)
        let hints = NSTextField(labelWithString: "↩ Open   ⌘↩ Reveal   ⌘⌫ Remove   ⌘V Add copied files")
        hints.font = .systemFont(ofSize: 11)
        hints.textColor = .secondaryLabelColor
        hints.alignment = .center
        hints.frame = NSRect(x: 12, y: ListGeometry.bottomBarY(16).rounded(), width: listSize.width - 24, height: 16)
        hints.autoresizingMask = [.width]
        shell.addSubview(hints)

        // A native search field: system caret, selection and input methods.
        let field = NSSearchField()
        field.controlSize = .large
        field.font = .systemFont(ofSize: 15)
        field.placeholderString = "Search Shelf"
        field.sendsSearchStringImmediately = true
        field.focusRingType = .none
        field.setAccessibilityLabel("Search Shelf")
        field.sizeToFit()
        let fieldHeight = field.frame.height
        field.frame = NSRect(x: 10, y: (listSize.height + (Self.shelfSearchBarHeight - fieldHeight) / 2).rounded(),
                             width: panelSize.width - 20, height: fieldHeight)
        field.autoresizingMask = [.width, .minYMargin]
        field.delegate = controller
        controller.searchField = field
        shell.addSubview(field)
        panel.contentView = shell

        // The search field's center on the Caps pill's center, so the pill seems to open into it.
        let pill = CapsHUDGeometry.keyFrame()
        let fieldInWindow = field.convert(field.bounds, to: nil)
        panel.setFrameOrigin(NSPoint(x: (pill.midX - panelSize.width / 2).rounded(),
                                     y: (pill.midY - fieldInWindow.midY).rounded()))
        panel.openSelection = { [weak controller] in controller?.table.openSelection?() }
        panel.revealSelection = { [weak controller] in controller?.table.revealSelection?() }
        panel.removeSelection = { [weak controller] in controller?.table.removeSelection?() }
        panel.pasteFiles = { [weak self] in
            let urls = ShelfListController.fileURLs(on: .general)
            guard let self = self, !urls.isEmpty else { return false }
            self.addShelfFiles(urls)
            return true
        }
        shelfPanel = panel
        shelfList = controller
    }

    // The open picker, when it has focus in its list or search field, so Caps + numbers,
    // letters and arrows select a file. Nil while a menu has focus.
    var shelfSelectionPanel: ShelfPanel? {
        guard let panel = shelfPanel, panel.isKeyWindow, let controller = shelfList else { return nil }
        // The search field's field editor has the focus while typing.
        let searching = (panel.firstResponder as? NSTextView).map { editor in
            controller.searchField.map { editor.delegate === $0 } ?? false
        } ?? false
        guard panel.firstResponder === controller.table || searching else { return nil }
        return panel
    }

    // MARK: Actions (indexes into `shelf`)

    // Returns the paths added (or moved up), in the order they now head the list.
    @discardableResult
    func addShelfFiles(_ urls: [URL]) -> [String] {
        let paths = urls.map { $0.standardizedFileURL.path }
        let added = Shelf.add(paths, to: &shelf)
        guard !added.isEmpty else { return [] }
        saveShelf()
        // Dropped from another app: give the panel the keyboard again to show what was
        // added, still without activating Clutch.
        if let panel = shelfPanel, panel.isVisible, !panel.isKeyWindow {
            panel.makeKeyAndOrderFront(nil)
            if let field = shelfList?.searchField { panel.makeFirstResponder(field) }
        }
        shelfList?.select(paths: added)
        return added
    }
    func openShelfFiles(_ indexes: IndexSet) {
        let selected = indexes.compactMap { shelf.indices.contains($0) ? shelf[$0] : nil }
        guard !selected.isEmpty else { NSSound.beep(); return }
        let opening = selected.map { $0.path }.filter { FileManager.default.fileExists(atPath: $0) }
        let missing = selected.map { $0.path }.filter { !opening.contains($0) }
        if !missing.isEmpty {
            shelf.removeAll { entry in missing.contains(entry.path) }
            saveShelf()
        }
        // The panel goes at once; Launch Services can take a moment to start the file's
        // app, so the files open asynchronously and the app comes forward when ready.
        if !opening.isEmpty { shelfPanel?.close() }
        if !missing.isEmpty { reportShelfFailures(missing) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        for path in opening {
            NSWorkspace.shared.open(URL(fileURLWithPath: path), configuration: configuration) { [weak self] _, error in
                guard error != nil else { return }
                DispatchQueue.main.async { self?.reportShelfFailures([path]) }
            }
        }
    }
    func revealShelfFiles(_ indexes: IndexSet) {
        let urls = indexes.compactMap { shelf.indices.contains($0) ? shelf[$0].path : nil }
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { NSSound.beep(); return }
        shelfPanel?.close()
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
    // Takes the files off the Shelf; the files themselves are left alone. The row that
    // took the first one's place is selected.
    func removeShelfFiles(_ indexes: IndexSet) {
        guard let table = shelfList?.table else { return }
        let firstRow = table.selectedRowIndexes.first ?? 0
        guard ListSelection.remove(indexes, from: &shelf) else { NSSound.beep(); return }
        saveShelf()
        ListSelection.selectAfterRemoval(at: firstRow, in: table)
    }
    private func reportShelfFailures(_ paths: [String]) {
        let names = paths.map { "“\(FileManager.default.displayName(atPath: $0))”" }.joined(separator: ", ")
        logStatus("Could not open \(names).")
        NSSound.beep()
    }
}
