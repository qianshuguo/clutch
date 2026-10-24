import Cocoa

extension AppDelegate: NSToolbarDelegate {
    func label(_ text: String, frame: NSRect, size: CGFloat = 13) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.frame = frame; field.font = .systemFont(ofSize: size); field.lineBreakMode = .byWordWrapping
        return field
    }
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
        let divider = NSBox(frame: NSRect(x: 24, y: 194, width: 412, height: 1))
        divider.boxType = .separator
        divider.autoresizingMask = [.width, .minYMargin]
        general.addSubview(divider)

        // Center a shared content column, with both sections left-aligned inside it.
        func optionGroup(centerFromTop: CGFloat, spacing: CGFloat) -> NSStackView {
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = spacing
            stack.detachesHiddenViews = true
            stack.translatesAutoresizingMaskIntoConstraints = false
            general.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: general.centerXAnchor),
                stack.leadingAnchor.constraint(greaterThanOrEqualTo: general.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: general.trailingAnchor, constant: -24),
                stack.centerYAnchor.constraint(equalTo: general.topAnchor, constant: centerFromTop)
            ])
            return stack
        }
        func addDetail(_ detail: NSView, to stack: NSStackView) {
            let inset = NSStackView(views: [detail])
            inset.orientation = .vertical
            inset.alignment = .leading
            inset.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)
            stack.addArrangedSubview(inset)
        }
        let activation = optionGroup(centerFromTop: 58, spacing: 4)
        let otherOptions = optionGroup(centerFromTop: 213, spacing: 14)
        activation.widthAnchor.constraint(equalTo: otherOptions.widthAnchor).isActive = true
        toggleButton = NSButton(checkboxWithTitle: "Enable Clutch", target: self, action: #selector(toggle))
        let notice = NSButton(title: "Waiting for Accessibility access", target: self, action: #selector(openPermissions))
        notice.isBordered = false
        notice.alignment = .left
        let noticeTitle = NSMutableAttributedString(string: notice.title, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        noticeTitle.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                                 range: (notice.title as NSString).range(of: "Accessibility access"))
        notice.attributedTitle = noticeTitle
        notice.setAccessibilityLabel("Waiting for Accessibility access. Open Accessibility settings.")
        activation.addArrangedSubview(toggleButton)
        // Place the notice below the checkbox without changing the centered group's height.
        notice.translatesAutoresizingMaskIntoConstraints = false
        general.addSubview(notice)
        NSLayoutConstraint.activate([
            notice.leadingAnchor.constraint(equalTo: toggleButton.leadingAnchor, constant: 20),
            notice.topAnchor.constraint(equalTo: toggleButton.bottomAnchor, constant: 4),
            notice.trailingAnchor.constraint(lessThanOrEqualTo: general.trailingAnchor, constant: -24)
        ])
        accessibilityNoticeRow = notice
        loginCheckbox = NSButton(checkboxWithTitle: "Launch on Login", target: self, action: #selector(changeLoginLaunch))
        otherOptions.addArrangedSubview(loginCheckbox!)
        hideCheckbox = NSButton(checkboxWithTitle: "Hide Status Bar Icon", target: self, action: #selector(changeStatusIcon))
        let hint = label("Open Clutch again to show Preferences.", frame: .zero, size: 11)
        hint.textColor = .secondaryLabelColor
        let visibility = NSStackView()
        visibility.orientation = .vertical
        visibility.alignment = .leading
        visibility.spacing = 4
        visibility.addArrangedSubview(hideCheckbox!)
        addDetail(hint, to: visibility)
        otherOptions.addArrangedSubview(visibility)

        let apps = pages[1]
        let scroll = makeListScroll(size: Self.preferenceSize, headerHeight: 28)
        let applicationList = ApplicationListController(owner: self)
        self.applicationList = applicationList
        let table = applicationList.table
        configureList(table, width: Self.preferenceSize.width, title: "Application")
        scroll.documentView = table
        apps.addSubview(scroll)
        addListHeader(to: apps, table: table, size: Self.preferenceSize)
        addListControls(to: apps, width: Self.preferenceSize.width,
                        add: { [weak self] in self?.addBinding() },
                        remove: { [weak self] in self?.removeBinding() }, itemName: "Application")
        let appsHelp = addListHelp([
            ("Caps + key, release Caps", "Switch to the app"),
            ("Set a shortcut", "Hold ⇪ + up to 3 keys"),
            ("Press again", "Next window of that app"),
            ("Not running", "Asks first; Return opens it"),
            ("⌘F", "Search by app name"),
            ("Type in the list", "Jump to an app by name")
        ], to: apps, trailing: Self.preferenceSize.width - 12)
        addApplicationSearch(to: apps, list: applicationList, scroll: scroll, before: appsHelp)
        let folderContent = makeFoldersContent(size: Self.preferenceSize, presentation: .preferences)
        preferencesFolderList = folderContent.controller
        pages[2].addSubview(folderContent.content)
        addWebsitesPage(to: pages[3])
        let windowsPage = pages[4]
        let windowScroll = makeListScroll(size: Self.preferenceSize, headerHeight: 28)
        let windowShortcutList = WindowShortcutListController(owner: self)
        self.windowShortcutList = windowShortcutList
        configureList(windowShortcutList.table, width: Self.preferenceSize.width, title: "Action")
        windowScroll.documentView = windowShortcutList.table
        windowsPage.addSubview(windowScroll)
        addListHeader(to: windowsPage, table: windowShortcutList.table, size: Self.preferenceSize)
        addWindowShortcutControls(to: windowsPage, width: Self.preferenceSize.width)
        syncPreferences()
        selectPage(selectedPage)
        return content
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

        let empty = NSTextField(labelWithString: "No Matching Applications")
        empty.font = .systemFont(ofSize: 13)
        empty.textColor = .secondaryLabelColor
        empty.alignment = .center
        empty.frame = NSRect(x: 0, y: scroll.frame.midY - 9, width: scroll.frame.width, height: 18)
        empty.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        empty.isHidden = true
        page.addSubview(empty)
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
        if Self.preferenceTabs[index].id == "folders" { window?.makeFirstResponder(preferencesFolderTable) }
    }
}
