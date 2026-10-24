import Cocoa

extension AppDelegate {
    func makeFoldersContent(size: NSSize, presentation: FolderListPresentation = .picker) -> (content: NSView, controller: FolderListController) {
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.autoresizingMask = [.width, .height]
        let inset = presentation.edgeInset
        let listWidth = size.width - inset * 2
        let scroll = makeListScroll(size: size,
                                    headerHeight: presentation.headerHeight,
                                    fitsTableToViewport: presentation.fitsTableToViewport)
        scroll.frame.size.height -= inset
        if inset > 0 {
            scroll.horizontalInset = inset
            scroll.verticalScroller = CenteredOverlayScroller()
        }
        let controller = FolderListController(owner: self, presentation: presentation)
        let list = controller.table
        configureList(list, width: listWidth, title: "Name")
        if presentation.fitsTableToViewport {
            // Let AppKit use the full viewport, shrinking it only for a visible legacy scroller.
            let hintColumn = list.tableColumns[1]
            hintColumn.width = listWidth - list.tableColumns[0].width
            hintColumn.resizingMask = .autoresizingMask
            list.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        }
        list.allowsMultipleSelection = true
        list.registerForDraggedTypes([folderDragType])
        list.setDraggingSourceOperationMask(.move, forLocal: true)
        scroll.documentView = list
        scroll.tile()
        content.addSubview(scroll)
        if presentation.headerHeight > 0 { addListHeader(to: content, table: list, size: size) }
        addListControls(to: content, width: size.width, leadingInset: inset,
                        add: { [weak self, weak controller] in
                            guard let controller = controller else { return }
                            self?.addFolders(to: controller)
                        }, remove: { [weak self, weak controller] in
                            guard let controller = controller else { return }
                            self?.removeFolders(from: controller)
                        }, itemName: "Folder")
        if presentation == .preferences {
            addListHelp([
                ("Caps + Space", "Open this list from any app"),
                ("Hold Caps + 1–9", "Select a folder"),
                ("Hold Caps + ↑↓", "Move the selection"),
                ("Release Caps", "Open the selection"),
                ("Set a shortcut", "Hold ⇪ + up to 3 keys; opens the folder"),
                ("Hover a folder", "Show its path"),
                ("Double-click a folder", "Edit its name and location"),
                ("Right-click a folder", "Open, edit or reveal it")
            ], to: content, trailing: size.width - 12)
        }
        return (content, controller)
    }
    @objc func showFolders() {
        guard !showingLaunchConfirmation else { return }
        closePreferencesForAction(keepingApplicationActive: true)
        if folderWindow == nil {
            // One window: the search field across its top, the list below. The search
            // field sits where the Caps pill was, so the pill seems to open into it.
            let contentSize = Self.preferenceSize
            let panelSize = NSSize(width: contentSize.width, height: contentSize.height + Self.folderSearchBarHeight)
            // A titled panel for the native rounded corners, with its title bar hidden.
            let panel = FolderPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                                    styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            panel.title = "Picker"
            panel.backgroundColor = .windowBackgroundColor
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                panel.standardWindowButton(kind)?.isHidden = true
            }
            panel.isMovableByWindowBackground = true
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            let folderContent = makeFoldersContent(size: contentSize)
            let list = folderContent.controller.table
            let shell = ListSurface(frame: NSRect(origin: .zero, size: panelSize))
            shell.addSubview(folderContent.content)
            // A native search field: system caret, selection and input methods.
            let field = NSSearchField()
            field.controlSize = .large
            field.font = .systemFont(ofSize: 15)
            field.placeholderString = "Search Folders"
            field.sendsSearchStringImmediately = true
            field.focusRingType = .none
            field.setAccessibilityLabel("Search folders")
            field.sizeToFit()
            let fieldHeight = field.frame.height
            field.frame = NSRect(x: 10, y: (contentSize.height + (Self.folderSearchBarHeight - fieldHeight) / 2).rounded(),
                                 width: panelSize.width - 20, height: fieldHeight)
            field.autoresizingMask = [.width, .minYMargin]
            field.delegate = folderContent.controller
            folderContent.controller.searchField = field
            shell.addSubview(field)
            panel.contentView = shell
            // The search field's center on the Caps pill's center.
            let pill = CapsHUDGeometry.keyFrame()
            let fieldInWindow = field.convert(field.bounds, to: nil)
            panel.setFrameOrigin(NSPoint(x: (pill.midX - panelSize.width / 2).rounded(),
                                         y: (pill.midY - fieldInWindow.midY).rounded()))
            panel.openSelection = list.openSelection
            panel.selectNumber = { [weak list] row in
                guard let list = list, (0..<list.numberOfRows).contains(row) else { return }
                // The search field keeps focus.
                list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                list.scrollRowToVisible(row)
            }
            folderWindow = panel; folderList = folderContent.controller
        }
        // Each opening starts a new search.
        folderList?.setFilter("")
        folderTable?.reloadData()
        if folderTable?.selectedRow == -1, !folders.isEmpty {
            folderTable?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        if let panel = folderWindow, !panel.isVisible {
            panel.previousFocus = PreviousFocus()
        }
        folderWindow?.makeKeyAndOrderFront(nil)
        let focus: NSResponder? = folderList?.searchField ?? folderTable
        folderWindow?.makeFirstResponder(focus)
        NSApp.activateFromBackground()
    }
    static let folderSearchBarHeight: CGFloat = 44
    // First-run Folders list, in order (Caps + 1…4). Folders that do not exist are skipped.
    static var defaultFolders: [FolderEntry] {
        let fileManager = FileManager.default
        let home: [FileManager.SearchPathDirectory] = [.downloadsDirectory, .desktopDirectory, .documentDirectory]
        let urls = home.compactMap { fileManager.urls(for: $0, in: .userDomainMask).first }
            + [URL(fileURLWithPath: "/Applications", isDirectory: true)]
        return urls.map { $0.standardizedFileURL.path }.filter(fileManager.isDirectory(atPath:)).map { FolderEntry(name: fileManager.displayName(atPath: $0), path: $0) }
    }
    // Falls back to the default list when nothing is saved. Unreadable saved data is
    // preserved and reported by the thrown error instead of being silently replaced.
    func loadFolders() throws {
        do {
            folders = try StoredList.load([FolderEntry].self, forKey: DefaultsKey.folders,
                                          description: "folders") ?? Self.defaultFolders
        } catch {
            folders = Self.defaultFolders
            throw error
        }
    }
    func saveFolders() {
        if let data = try? JSONEncoder().encode(folders) { UserDefaults.standard.set(data, forKey: DefaultsKey.folders) }
        folderTable?.reloadData()
        preferencesFolderTable?.reloadData()
    }
    // +: the sheet Websites shares (showFieldSheet), with Name and Location; Choose…
    // picks the folder. An empty name uses the folder's own name. A folder already listed
    // is selected instead.
    func addFolders(to controller: FolderListController) {
        showFieldSheet(on: controller.table.window, title: "Add Folder",
                       button: "Add", fields: Self.folderFields(name: "", location: "")) { [weak self, weak controller] values in
            guard let self = self, let controller = controller else { return }
            self.addFolder(name: values[0], location: values[1], to: controller)
        }
    }
    // While Name is empty it shows, in gray, the name of the folder Location names: that
    // is the name an empty field saves.
    static func folderFields(name: String, location: String) -> [SheetField] {
        [SheetField(label: "Name", value: name, placeholder: { values in
            values.count > 1 ? AppDelegate.folderDisplayName(forLocation: values[1]) : ""
         }),
         SheetField(label: "Location", value: location, choosesFolder: true)]
    }
    // The name Finder shows for a typed location ("~/Documents" → "Documents"), or "" when
    // it is not a folder.
    static func folderDisplayName(forLocation location: String) -> String {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let path = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath).standardizedFileURL.path
        guard FileManager.default.isDirectory(atPath: path) else { return "" }
        return FileManager.default.displayName(atPath: path)
    }
    func addFolder(name text: String, location: String, to controller: FolderListController) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let path = folderPath(for: location) else { return }
        let targetTable = controller.table
        // Rows equal folder indexes once nothing is filtered out.
        controller.setFilter("")
        let index: Int
        if let existing = folders.firstIndex(where: { $0.path == path }) {
            index = existing
        } else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            var folder = FolderEntry(name: trimmed, path: path)
            if trimmed.isEmpty { folder.name = folder.originalName }
            folders.append(folder)
            saveFolders()
            index = folders.count - 1
        }
        targetTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        targetTable.scrollRowToVisible(index)
    }
    // Typed or chosen text as a folder path: "~" expanded, standardized, and it must be
    // an existing folder; otherwise reported, and nil.
    func folderPath(for location: String) -> String? {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showError(ToolError(message: "Choose a folder, or type its location, such as ~/Documents."))
            return nil
        }
        let path = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath).standardizedFileURL.path
        guard FileManager.default.isDirectory(atPath: path) else {
            showError(ToolError(message: "“\(trimmed)” is not a folder."))
            return nil
        }
        return path
    }
    // Removes the selected folders (mapped through a search) and selects the row
    // that took the first one's place.
    func removeFolders(from controller: FolderListController) {
        let targetTable = controller.table
        let firstRow = targetTable.selectedRowIndexes.first
        guard ListSelection.remove(controller.selectedFolderIndices, from: &folders) else { return }
        saveFolders()
        let rows = targetTable.numberOfRows
        if let first = firstRow, rows > 0 {
            targetTable.selectRowIndexes(IndexSet(integer: min(first, rows - 1)), byExtendingSelection: false)
        }
    }
    // `selection`: indexes into `folders` (rows mapped through any search).
    func openSelectedFolders(_ selection: IndexSet, in targetTable: NSTableView) {
        guard targetTable.window?.attachedSheet == nil, !selection.isEmpty else { return }
        let selected = selection.compactMap { folders.indices.contains($0) ? folders[$0] : nil }
        let owner = targetTable.window
        let result = openFolders(selected)
        if result.openedCount > 0, let panel = owner as? FolderPanel { panel.close() }
        report(result)
    }
    // Opens the folder a Caps shortcut names, at its saved path.
    func openFolderShortcut(_ folder: FolderEntry) { report(openFolders([folder])) }
    private func openFolders(_ selected: [FolderEntry]) -> FolderBatchOpen.Result {
        FolderBatchOpen.run(selected, isDirectory: FileManager.default.isDirectory(atPath:), open: { folder in
            self.closePreferencesForAction()
            return NSWorkspace.shared.open(URL(fileURLWithPath: folder.path, isDirectory: true))
        })
    }
    // Every failure of a batch in one alert.
    private func report(_ result: FolderBatchOpen.Result) {
        guard !result.failures.isEmpty else { return }
        showError(ToolError(message: result.failures.joined(separator: "\n")))
    }

    // MARK: Names

    // Edit… for one folder: the sheet Websites shares (showFieldSheet), with its name and
    // location, like a website's name and URL. A folder showing its own name opens with
    // Name empty (the gray placeholder shows it); clearing the name goes back to the
    // folder's own name. Only what Clutch shows and opens changes; nothing on disk is
    // renamed or moved.
    func editFolder(at index: Int, in targetTable: NSTableView) {
        guard folders.indices.contains(index) else { return }
        let folder = folders[index]
        showFieldSheet(on: targetTable.window, title: "Edit Folder",
                       button: "Save",
                       fields: Self.folderFields(name: folder.isRenamed ? folder.name : "",
                                                 location: (folder.path as NSString).abbreviatingWithTildeInPath)) { [weak self] values in
            self?.updateFolder(path: folder.path, name: values[0], location: values[1], in: targetTable)
        }
    }
    // Found again by path: the list may have changed while the sheet was open. `location`
    // (nil keeps it) must be an existing folder that no other entry has; "~" is expanded.
    // A folder still showing its own name takes the new folder's name; a renamed one keeps
    // its name. The shortcut stays.
    func updateFolder(path: String, name text: String, location: String? = nil, in targetTable: NSTableView? = nil) {
        guard let index = folders.firstIndex(where: { $0.path == path }) else { return }
        var newPath = path
        if let location = location {
            guard let standardized = folderPath(for: location) else { return }
            if let other = folders.indices.first(where: { $0 != index && folders[$0].path == standardized }) {
                if let table = targetTable, let row = table.dataSource.flatMap({ $0 as? FolderListController })?.visibleIndices.firstIndex(of: other) {
                    table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    table.scrollRowToVisible(row)
                }
                showError(ToolError(message: "\((standardized as NSString).abbreviatingWithTildeInPath) is already in Folders as \(folders[other].name)."))
                return
            }
            newPath = standardized
        }
        let wasRenamed = folders[index].isRenamed
        var updated = folders[index]
        updated.path = newPath
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || (!wasRenamed && trimmed == folders[index].name) {
            updated.name = updated.originalName
        } else {
            updated.name = trimmed
        }
        guard updated != folders[index] else { return }
        folders[index] = updated
        saveFolders()
    }
    // Selects the folders in a Finder window. Finder comes forward, so the Picker closes.
    func revealFolders(_ selection: IndexSet) {
        let urls = selection.compactMap { folders.indices.contains($0) ? URL(fileURLWithPath: folders[$0].path, isDirectory: true) : nil }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
