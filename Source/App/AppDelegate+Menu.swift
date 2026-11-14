import Cocoa

extension AppDelegate: NSMenuItemValidation {
    func createMenu() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⇪+"
        @discardableResult
        func add(_ title: String, _ action: Selector, _ key: String = "", to menu: NSMenu) -> NSMenuItem {
            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
            menuItem.target = self
            menu.addItem(menuItem)
            return menuItem
        }
        // The ⇪+ menu and the app menu hold the same commands. Returns the menu's toggle item.
        // Caps + Tab opens Preferences and Caps + Space the Shelf, from anywhere; AppKit
        // cannot show ⇪ in a key equivalent, so General in Preferences names them instead.
        func addCommands(to menu: NSMenu) -> NSMenuItem {
            add("Preferences", #selector(showSettings), to: menu)
            add("Shelf…", #selector(showShelf), to: menu)
            let toggleItem = add("Enable Clutch", #selector(toggle), "s", to: menu)
            menu.addItem(.separator())
            add("Quit Clutch", #selector(quitApp), "q", to: menu)
            return toggleItem
        }
        let menu = NSMenu()
        let statusToggle = addCommands(to: menu)
        item.menu = menu
        // App-scoped shortcuts; Command-S in another app keeps its normal meaning.
        let main = NSMenu()
        let appMenu = NSMenu()
        let appToggle = addCommands(to: appMenu)
        // ⌘W and ⌘F work in Clutch's windows without showing in the menu.
        for hidden in [add("Close Window", #selector(closeSettings), "w", to: appMenu),
                       add("Find", #selector(findInList), "f", to: appMenu)] {
            hidden.isHidden = true
            hidden.allowsKeyEquivalentWhenHidden = true
        }
        let root = NSMenuItem(); root.submenu = appMenu
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
        toggleMenuItems = [statusToggle, appToggle]
    }
    func updateToggleMenuTitle() {
        let title = tap != nil ? "Disable Clutch" : (wantsEnabled ? "Cancel Enabling" : "Enable Clutch")
        for item in toggleMenuItems { item.title = title }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggle) { updateToggleMenuTitle() }
        if menuItem.action == #selector(findInList) { return visibleEntryList != nil }
        if menuItem.action == #selector(closeSettings) { return window?.isVisible == true || shelfPanel?.isVisible == true }
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
