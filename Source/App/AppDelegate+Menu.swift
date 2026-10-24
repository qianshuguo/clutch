import Cocoa

extension AppDelegate: NSMenuItemValidation {
    func createMenu() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⇪+"
        let menu = NSMenu()
        @discardableResult
        func add(_ title: String, _ action: Selector, _ key: String, hidden: Bool = false) -> NSMenuItem {
            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
            menuItem.target = self
            // Hidden items keep their shortcut in the app menu below.
            menuItem.isHidden = hidden
            menuItem.allowsKeyEquivalentWhenHidden = hidden
            menu.addItem(menuItem)
            return menuItem
        }
        add("Preferences", #selector(showSettings), ",")
        add("Close Window", #selector(closeSettings), "w", hidden: true)
        add("Find", #selector(findApplication), "f", hidden: true)
        add("Picker…", #selector(showFolders), "")
        let toggleItem = add("Enable Clutch", #selector(toggle), "s")
        menu.addItem(.separator())
        add("Quit Clutch", #selector(quitApp), "q")
        item.menu = menu
        // App-scoped shortcuts; Command-S in another app keeps its normal meaning.
        let main = NSMenu()
        let root = NSMenuItem(); root.submenu = menu.copy() as? NSMenu
        main.addItem(root)
        // Text fields get ⌘X, ⌘C, ⌘V, ⌘A and ⌘Z only through these menu items (Clutch has
        // no other main menu); they go to whatever field or list has focus.
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        edit.submenu = editMenu
        main.addItem(edit)
        NSApp.mainMenu = main
        toggleMenuItems = [toggleItem] + (root.submenu?.items.filter { $0.action == #selector(toggle) } ?? [])
    }
    func updateToggleMenuTitle() {
        let title = tap != nil ? "Disable Clutch" : (wantsEnabled ? "Cancel Enabling" : "Enable Clutch")
        for item in toggleMenuItems { item.title = title }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggle) { updateToggleMenuTitle() }
        if menuItem.action == #selector(findApplication) {
            return window?.isVisible == true && Self.preferenceTabs[selectedPage].id == "apps"
        }
        if menuItem.action == #selector(closeSettings) { return window?.isVisible == true || folderWindow?.isVisible == true }
        return true
    }
    // Brings the toggle title and Preferences controls up to date with the enabled state.
    func refreshControls() {
        updateToggleMenuTitle()
        syncPreferences()
    }
    // Clutch has no status line; what happened goes to the system log.
    func logStatus(_ message: String) {
        NSLog("Clutch: %@", message)
    }
    func showError(_ error: Error) {
        logStatus(error.localizedDescription)
        refreshControls()
        let alert = NSAlert(); alert.messageText = "Clutch"; alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
