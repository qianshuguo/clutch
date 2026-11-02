import Cocoa

extension AppDelegate {
    // The Folders page of Preferences: the list with a header and shortcut fields.
    func makeFoldersContent(size: NSSize) -> (content: NSView, controller: FolderListController) {
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.autoresizingMask = [.width, .height]
        let scroll = makeListScroll(size: size, headerHeight: 28)
        let controller = FolderListController(owner: self)
        let list = controller.table
        configureList(list, width: size.width, title: "Name")
        list.allowsMultipleSelection = true
        list.registerForDraggedTypes([folderDragType])
        list.setDraggingSourceOperationMask(.move, forLocal: true)
        scroll.documentView = list
        scroll.tile()
        content.addSubview(scroll)
        addListHeader(to: content, table: list, size: size)
        addListControls(to: content, width: size.width,
                        add: { [weak self, weak controller] in
                            guard let controller = controller else { return }
                            self?.addFolders(to: controller)
                        }, remove: { [weak self, weak controller] in
                            guard let controller = controller else { return }
                            self?.removeFolders(from: controller)
                        }, itemName: "Folder")
        addListHelp([
            ("Caps + shortcut, release Caps", "Open the folder in Finder"),
            ("Set a shortcut", "Hold ⇪ + up to 3 keys"),
            ("Hover a folder", "Show its path"),
            ("Double-click a folder", "Edit its name and location"),
            ("Right-click a folder", "Open, edit or reveal it")
        ], to: content, trailing: size.width - 12)
        return (content, controller)
    }
    // First-run Folders list, in order. Folders that do not exist are skipped.
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
    // Removes the selected folders and selects the row that took the first one's place.
    func removeFolders(from controller: FolderListController) {
        let targetTable = controller.table
        let firstRow = targetTable.selectedRowIndexes.first
        guard ListSelection.remove(targetTable.selectedRowIndexes, from: &folders) else { return }
        saveFolders()
        let rows = targetTable.numberOfRows
        if let first = firstRow, rows > 0 {
            targetTable.selectRowIndexes(IndexSet(integer: min(first, rows - 1)), byExtendingSelection: false)
        }
    }
    // `selection`: indexes into `folders`.
    func openSelectedFolders(_ selection: IndexSet, in targetTable: NSTableView) {
        guard targetTable.window?.attachedSheet == nil, !selection.isEmpty else { return }
        report(openFolders(selection.compactMap { folders.indices.contains($0) ? folders[$0] : nil }))
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
                if let table = targetTable {
                    table.selectRowIndexes(IndexSet(integer: other), byExtendingSelection: false)
                    table.scrollRowToVisible(other)
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
    // Selects the folders in a Finder window.
    func revealFolders(_ selection: IndexSet) {
        let urls = selection.compactMap { folders.indices.contains($0) ? URL(fileURLWithPath: folders[$0].path, isDirectory: true) : nil }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
