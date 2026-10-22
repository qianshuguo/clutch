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
                ("Release Caps", "Open the selection")
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
    func addFolders(to controller: FolderListController) {
        let targetTable = controller.table
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
            // Rows equal folder indexes once nothing is filtered out.
            controller.setFilter("")
            self.saveFolders()
            if let index = selected {
                targetTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                targetTable.scrollRowToVisible(index)
            }
        }
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
        let result = FolderBatchOpen.run(selected, isDirectory: FileManager.default.isDirectory(atPath:), open: { folder in
            self.closePreferencesForAction()
            return NSWorkspace.shared.open(URL(fileURLWithPath: folder.path, isDirectory: true))
        })
        if result.openedCount > 0, let panel = owner as? FolderPanel { panel.close() }
        if !result.failures.isEmpty {
            showError(ToolError(message: result.failures.joined(separator: "\n")))
        }
    }
}
