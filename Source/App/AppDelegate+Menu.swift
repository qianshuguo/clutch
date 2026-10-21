import Cocoa

extension AppDelegate: NSMenuItemValidation {
    func createMenu() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⇪+"
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Preferences", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self; menu.addItem(settingsItem)
        let foldersItem = NSMenuItem(title: "Folders…", action: #selector(showFolders), keyEquivalent: "")
        foldersItem.target = self; menu.addItem(foldersItem)
        let pauseItem = NSMenuItem(title: "Enable Clutch", action: #selector(toggle), keyEquivalent: "s")
        pauseItem.target = self; menu.addItem(pauseItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Clutch", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        let closeItem = NSMenuItem(title: "Close Window", action: #selector(closeSettings), keyEquivalent: "w")
        closeItem.target = self
        closeItem.isHidden = true
        closeItem.allowsKeyEquivalentWhenHidden = true
        menu.insertItem(closeItem, at: 1)
        let findItem = NSMenuItem(title: "Find", action: #selector(findApplication), keyEquivalent: "f")
        findItem.target = self
        findItem.isHidden = true
        findItem.allowsKeyEquivalentWhenHidden = true
        menu.insertItem(findItem, at: 2)
        item.menu = menu
        // App-scoped shortcuts; Command-S in another app keeps its normal meaning.
        let main = NSMenu()
        let root = NSMenuItem(); root.submenu = menu.copy() as? NSMenu
        main.addItem(root); NSApp.mainMenu = main
        toggleMenuItems = [pauseItem] + (root.submenu?.items.filter { $0.action == #selector(toggle) } ?? [])
    }
    func updateToggleMenuTitle(_ title: String? = nil) {
        let title = title ?? (tap != nil ? "Disable Clutch" : (wantsEnabled ? "Cancel Enabling" : "Enable Clutch"))
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
    func setStatus(_ message: String) {
        updateToggleMenuTitle()
        syncPreferences()
        NSLog("Clutch: %@", message)
    }
    func showError(_ error: Error) {
        setStatus(error.localizedDescription)
        let alert = NSAlert(); alert.messageText = "Clutch"; alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
