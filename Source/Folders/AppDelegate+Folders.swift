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
        configureList(list, width: listWidth, columnID: "folder")
        if presentation.fitsTableToViewport {
            // Let AppKit use the full viewport, shrinking it only for a visible legacy scroller.
            let pathColumn = list.tableColumns[1]
            pathColumn.width = listWidth - list.tableColumns[0].width
            pathColumn.resizingMask = .autoresizingMask
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
                        add: { [weak self, weak list] in
                            guard let list = list else { return }
                            self?.addFolders(to: list)
                        }, remove: { [weak self, weak list] in
                            guard let list = list else { return }
                            self?.removeFolders(from: list)
                        }, itemName: "Folder")
        if presentation == .preferences {
            addListHelp([
                ("Caps + Space", "Open this list from any app"),
                ("Hold Caps + 1–9", "Select a folder"),
                ("Hold Caps + ↑↓", "Move the selection"),
                ("Release Caps", "Open the selection")
            ], to: content, trailing: size.width - 12)
        }
        return (content, controller)
    }
    @objc func showFolders() {
        guard !showingLaunchConfirmation else { return }
        closePreferencesForAction(keepingApplicationActive: true)
        if folderWindow == nil {
            let contentSize = Self.preferenceSize
            let panelSize = NSSize(width: contentSize.width, height: contentSize.height + 6)
            // Match the launch confirmation's native rounded, transparent title-bar shell.
            let panel = FolderPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                                    styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            panel.title = "Folders"
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
            panel.center()
            let folderContent = makeFoldersContent(size: contentSize)
            let list = folderContent.controller.table
            let shell = ListSurface(frame: NSRect(origin: .zero, size: panelSize))
            shell.addSubview(folderContent.content)
            panel.contentView = shell
            panel.openSelection = list.openSelection
            panel.selectNumber = { [weak list] row in
                guard let list = list, (0..<list.numberOfRows).contains(row) else { return }
                list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                list.scrollRowToVisible(row)
                list.window?.makeFirstResponder(list)
            }
            folderWindow = panel; folderList = folderContent.controller
        }
        folderTable?.reloadData()
        if folderTable?.selectedRow == -1, !folders.isEmpty {
            folderTable?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        if let panel = folderWindow, !panel.isVisible {
            panel.previousFocus = PreviousFocus()
        }
        folderWindow?.makeKeyAndOrderFront(nil)
        folderWindow?.makeFirstResponder(folderTable)
        NSApp.activateFromBackground()
    }
    // First-run Folders list, in order (Caps + 1…4). Folders that do not exist are skipped.
    static var defaultFolders: [FolderEntry] {
        let fileManager = FileManager.default
        let home: [FileManager.SearchPathDirectory] = [.downloadsDirectory, .desktopDirectory, .documentDirectory]
        let urls = home.compactMap { fileManager.urls(for: $0, in: .userDomainMask).first }
            + [URL(fileURLWithPath: "/Applications", isDirectory: true)]
        return urls.map { $0.standardizedFileURL.path }.filter { path in
            var directory: ObjCBool = false
            return fileManager.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
        }.map { FolderEntry(name: fileManager.displayName(atPath: $0), path: $0) }
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
    func addFolders(to targetTable: NSTableView) {
        guard let owner = targetTable.window else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Folders"
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: owner) { [weak self] response in
            guard let self = self, response == .OK else { return }
            var selected: Int?
            for url in panel.urls {
                let path = url.standardizedFileURL.path
                if let index = self.folders.firstIndex(where: { $0.path == path }) { selected = index; continue }
                self.folders.append(FolderEntry(name: FileManager.default.displayName(atPath: path), path: path))
                selected = self.folders.count - 1
            }
            self.saveFolders()
            if let index = selected {
                targetTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                targetTable.scrollRowToVisible(index)
            }
        }
    }
    func removeFolders(from targetTable: NSTableView) {
        guard let selection = ListSelection.remove(targetTable.selectedRowIndexes, from: &folders) else { return }
        saveFolders()
        targetTable.selectRowIndexes(selection, byExtendingSelection: false)
    }
    func openSelectedFolders(in targetTable: NSTableView) {
        guard targetTable.window?.attachedSheet == nil,
              !targetTable.selectedRowIndexes.isEmpty else { return }
        let selection = targetTable.selectedRowIndexes
        let selected = selection.compactMap { folders.indices.contains($0) ? folders[$0] : nil }
        let owner = targetTable.window
        let result = FolderBatchOpen.run(selected, isDirectory: { path in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
        }, open: { folder in
            self.closePreferencesForAction()
            return NSWorkspace.shared.open(URL(fileURLWithPath: folder.path, isDirectory: true))
        })
        if result.openedCount > 0, let panel = owner as? FolderPanel { panel.close() }
        if !result.failures.isEmpty {
            showError(ToolError(message: result.failures.joined(separator: "\n")))
        }
    }
}
