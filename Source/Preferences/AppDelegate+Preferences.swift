import Cocoa

extension AppDelegate: NSToolbarDelegate {
    func createWindow() {
        window = PreferencesWindow(contentRect: NSRect(origin: .zero, size: Self.preferenceSize),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Preferences"
        // Give the toolbar a stable background distinct from the content surface.
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        let toolbar = NSToolbar(identifier: "Preferences")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .preference
        window.contentView = makePreferencesContent()
        // Adding the toolbar can change the frame; keep the content at its fixed size.
        window.setContentSize(Self.preferenceSize)
    }
    // Shared by the running app and Xcode Canvas. No keyboard services start here.
    func makePreferencesContent() -> NSView {
        let content = ListSurface(frame: NSRect(origin: .zero, size: Self.preferenceSize))
        pages = Self.preferenceTabs.map { _ in NSView(frame: content.bounds) }
        for page in pages {
            page.autoresizingMask = [.width, .height]
            content.addSubview(page)
        }
        // Keep the toolbar boundary consistent across tabs and Canvas.
        let toolbarDivider = NSBox(frame: NSRect(x: 0, y: content.bounds.height - 1,
                                                 width: content.bounds.width, height: 1))
        toolbarDivider.boxType = .separator
        toolbarDivider.autoresizingMask = [.width, .minYMargin]
        content.addSubview(toolbarDivider)
        let general = pages[0]
        // Traditional preference layout: native checkboxes on the shared surface,
        // with one quiet divider and a common leading edge.
        func group(_ views: [NSView], spacing: CGFloat) -> NSStackView {
            let stack = NSStackView(views: views)
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = spacing
            return stack
        }
        toggleButton = NSButton(checkboxWithTitle: "Enable Clutch", target: self, action: #selector(toggle))
        let notice = NSButton(title: "Grant Accessibility access…", target: self, action: #selector(openPermissions))
        notice.isBordered = false
        notice.alignment = .left
        notice.attributedTitle = NSAttributedString(string: notice.title, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.linkColor
        ])
        notice.setAccessibilityLabel("Grant Accessibility access. Open Accessibility settings.")
        notice.isHidden = true
        accessibilityNotice = notice
        askBeforeOpeningCheckbox = NSButton(checkboxWithTitle: "Ask Before Opening", target: self,
                                            action: #selector(changeAskBeforeOpening))
        loginCheckbox = NSButton(checkboxWithTitle: "Launch on Login", target: self, action: #selector(changeLoginLaunch))
        hideCheckbox = NSButton(checkboxWithTitle: "Hide Status Bar Icon", target: self, action: #selector(changeStatusIcon))
        // Both states share one fixed line, so permission changes never move the form.
        let permissionLine = NSView()
        let hint = NSTextField(labelWithString: "Use Caps Lock shortcuts.")
        hint.font = .systemFont(ofSize: 11)
        hint.lineBreakMode = .byWordWrapping
        hint.textColor = .secondaryLabelColor
        accessibilityHint = hint
        for view in [hint, notice] {
            view.translatesAutoresizingMaskIntoConstraints = false
            permissionLine.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: permissionLine.leadingAnchor, constant: 20),
                view.trailingAnchor.constraint(lessThanOrEqualTo: permissionLine.trailingAnchor),
                view.centerYAnchor.constraint(equalTo: permissionLine.centerYAnchor)
            ])
        }
        permissionLine.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let enable = group([toggleButton, permissionLine], spacing: 4)
        permissionLine.widthAnchor.constraint(equalTo: enable.widthAnchor).isActive = true
        func describedOption(_ checkbox: NSButton, text: String) -> NSStackView {
            let hint = NSTextField(wrappingLabelWithString: text)
            hint.font = .systemFont(ofSize: 11)
            hint.textColor = .secondaryLabelColor
            hint.preferredMaxLayoutWidth = 280
            hint.widthAnchor.constraint(equalToConstant: 280).isActive = true
            let inset = group([hint], spacing: 0)
            inset.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)
            return group([checkbox, inset], spacing: 4)
        }
        let confirmation = describedOption(askBeforeOpeningCheckbox!,
            text: "Ask before launching an app or opening a website that isn’t already open.")
        let activation = group([enable, confirmation], spacing: 18)
        let visibility = describedOption(hideCheckbox!, text: "Open Clutch again to show Preferences.")
        let otherOptions = group([loginCheckbox!, visibility], spacing: 18)
        let divider = NSBox()
        divider.boxType = .separator
        let column = group([activation, divider, otherOptions], spacing: 22)
        column.translatesAutoresizingMaskIntoConstraints = false
        general.addSubview(column)
        NSLayoutConstraint.activate([
            column.widthAnchor.constraint(equalToConstant: 300),
            column.centerXAnchor.constraint(equalTo: general.centerXAnchor),
            column.centerYAnchor.constraint(equalTo: general.centerYAnchor),
            activation.widthAnchor.constraint(equalTo: column.widthAnchor),
            divider.widthAnchor.constraint(equalTo: column.widthAnchor)
        ])

        addApplicationsPage(to: pages[1])
        addFoldersPage(to: pages[2])
        addWebsitesPage(to: pages[3])
        addWindowsPage(to: pages[4])
        syncPreferences()
        selectPage(selectedPage)
        return content
    }
    func addApplicationsPage(to page: NSView) {
        let list = ApplicationListController(owner: self)
        applicationList = list
        let scroll = addList(list.table, to: page, title: "Application")
        let width = page.bounds.width
        addListControls(to: page, width: width,
                        add: { [weak self] in self?.addBinding() },
                        remove: { [weak self] in self?.removeBinding() }, itemName: "Application")
        let help = addListHelp([
            ("Caps + key, release Caps", "Switch to the app"),
            ("Set a shortcut", "Hold ⇪ + up to 3 keys"),
            ("Press again", "Next window of that app"),
            ("Not running", "Asks first; Return opens it"),
            ("⌘F", "Search by app name"),
            ("Type in the list", "Jump to an app by name")
        ], to: page, trailing: width - 12)
        addApplicationSearch(to: page, list: list, scroll: scroll, before: help)
    }
    // A small search field in the App List bottom bar, ending just before the ? button,
    // plus the notice shown over the list when nothing matches.
    func addApplicationSearch(to page: NSView, list: ApplicationListController, scroll: NSScrollView, before help: NSView) {
        let search = NSSearchField()
        search.controlSize = .small
        search.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        search.placeholderString = "Search"
        search.sendsSearchStringImmediately = true
        search.target = list
        search.action = #selector(ApplicationListController.searchChanged(_:))
        search.delegate = list
        search.setAccessibilityLabel("Search applications")
        search.sizeToFit()
        let width: CGFloat = 160
        let height = search.frame.height
        search.frame = NSRect(x: help.frame.minX - 8 - width, y: ((32 - height) / 2).rounded(),
                              width: width, height: height)
        search.autoresizingMask = [.minXMargin]
        page.addSubview(search)
        list.searchField = search

        let empty = addEmptyListLabel("No Matching Applications", over: scroll, to: page)
        empty.isHidden = true
        list.emptyLabel = empty
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.preferenceTabs.map { NSToolbarItem.Identifier($0.id) }
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let index = Self.preferenceTabs.firstIndex(where: { $0.id == identifier.rawValue }) else { return nil }
        let tab = Self.preferenceTabs[index]
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = tab.title
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)?.withSymbolConfiguration(symbolConfiguration)
        item.target = self; item.action = #selector(changePage)
        item.tag = index
        return item
    }
    @objc func changePage(_ sender: NSToolbarItem) { selectPage(sender.tag) }
    func selectPage(_ index: Int) {
        // Also ends a recording: KeyRecorder cancels when it resigns first responder.
        window?.makeFirstResponder(nil)
        selectedPage = index
        for (position, page) in pages.enumerated() { page.isHidden = position != index }
        window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(Self.preferenceTabs[index].id)
        if Self.preferenceTabs[index].id == "folders" { window?.makeFirstResponder(preferencesFolderList?.table) }
    }
}
