import Cocoa

extension WebsiteEntry {
    // The default browser's icon, on the HUD card and in the list: websites open there.
    static var browserIcon: NSImage {
        if let app = Browser.defaultApplication() { return NSWorkspace.shared.icon(forFile: app.url.path) }
        return NSImage(systemSymbolName: "globe", accessibilityDescription: "Website") ?? NSImage()
    }
}

extension AppDelegate {
    // MARK: Saved list

    // Starts empty. Unreadable saved data is preserved and reported by the thrown error
    // instead of being silently replaced.
    func loadWebsites() throws {
        websites = []
        if let saved = try StoredList.load([WebsiteEntry].self, forKey: DefaultsKey.websites,
                                           description: "websites") { websites = saved }
    }
    func saveWebsites() {
        StoredList.save(websites, forKey: DefaultsKey.websites)
        websiteList?.reload()
    }

    // MARK: Preferences page

    // Websites rows show a name and an address, so the first column runs up to just
    // before the shortcut field, which stays where it is on the other pages.
    static var websiteNameColumnWidth: CGFloat {
        preferenceSize.width - listScrollbarWidth - ListGeometry.shortcutRecorderWidth - 12
    }

    func addWebsitesPage(to page: NSView) {
        let list = WebsiteListController(owner: self)
        websiteList = list
        addEntryListPage(ListPageSpec(
            entryName: "Website", pluralName: "Websites",
            nameWidth: Self.websiteNameColumnWidth,
            shortcutAction: "Go to the website",
            help: [("Already open", "Switches to its tab"),
                   ("Press again", "Next tab of that website"),
                   ("Only a domain", "Matches the whole site"),
                   ("Domain and path", "Matches that page and below"),
                   ("Double-click a website", "Edit its name and URL"),
                   ("Right-click a website", "Open or edit it")],
            add: { [weak self] in self?.addWebsite() },
            remove: { [weak self] in self?.removeWebsites() }), list: list, to: page)
    }

    // Add and Edit use the sheet Folders shares (showFieldSheet): Name and URL, like a
    // browser's bookmark editor, and Include subdomains, on for a new website.
    @objc func addWebsite() { showAddWebsiteSheet(name: "", address: "", includesSubdomains: true) }
    private func showAddWebsiteSheet(name: String, address: String, includesSubdomains: Bool) {
        showWebsiteSheet(title: "Add Website", button: "Add", name: name, address: address,
                         includesSubdomains: includesSubdomains) { [weak self] name, address, subdomains in
            guard let self = self,
                  !self.addWebsite(address: address, name: name, includesSubdomains: subdomains) else { return }
            // Not a web address: the sheet comes back with what was typed.
            DispatchQueue.main.async {
                self.showAddWebsiteSheet(name: name, address: address, includesSubdomains: subdomains)
            }
        }
    }
    func editWebsite(at index: Int) {
        guard websites.indices.contains(index) else { return }
        let site = websites[index]
        showEditWebsiteSheet(at: index, name: site.title, address: Self.editableAddress(site.url),
                             includesSubdomains: site.includesSubdomains)
    }
    private func showEditWebsiteSheet(at index: Int, name: String, address: String, includesSubdomains: Bool) {
        showWebsiteSheet(title: "Edit Website", button: "Save", name: name, address: address,
                         includesSubdomains: includesSubdomains) { [weak self] name, address, subdomains in
            guard let self = self,
                  !self.updateWebsite(at: index, name: name, address: address, includesSubdomains: subdomains) else { return }
            // Not a web address: the sheet comes back with what was typed.
            DispatchQueue.main.async {
                self.showEditWebsiteSheet(at: index, name: name, address: address, includesSubdomains: subdomains)
            }
        }
    }
    // The saved address without "https://", the way it was typed; other schemes stay.
    static func editableAddress(_ url: String) -> String {
        url.hasPrefix("https://") ? String(url.dropFirst("https://".count)) : url
    }
    // Name shows, in gray, what an empty name shows: the address typed below it.
    private func showWebsiteSheet(title: String, button: String, name: String, address: String,
                                  includesSubdomains: Bool,
                                  completion: @escaping (_ name: String, _ address: String, _ includesSubdomains: Bool) -> Void) {
        let fields = [SheetField(label: "Name", value: name, placeholder: { values in
                          guard values.count > 1, let url = WebsiteAddress.normalize(values[1]) else { return "" }
                          return WebsiteAddress(url)?.display ?? ""
                      }),
                      SheetField(label: "URL", value: address, placeholder: { _ in "github.com or github.com/you/project" },
                                 required: true)]
        showFieldSheet(on: window, title: title,
                       message: "Include subdomains to also match sites like mail.google.com.",
                       button: button, fields: fields,
                       checkbox: SheetCheckbox(title: "Include subdomains", isOn: includesSubdomains)) { values, checked in
            completion(values[0], values[1], checked)
        }
    }
    private func websiteURL(for text: String) -> (url: String, address: WebsiteAddress)? {
        guard let url = WebsiteAddress.normalize(text), let address = WebsiteAddress(url) else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            showError(ToolError(message: trimmed.isEmpty ? "Enter the website’s address, such as github.com."
                                                         : "“\(trimmed)” is not a web address. Enter one such as github.com."))
            return nil
        }
        return (url, address)
    }
    // Adding an address already in the list (the same site and path) selects it instead.
    // False when the text is not a web address (reported), so the sheet can come back.
    @discardableResult
    func addWebsite(address text: String, name: String = "", includesSubdomains: Bool = true) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !name.isEmpty else { return true }
        guard let parsed = websiteURL(for: text) else { return false }
        let url = parsed.url, address = parsed.address
        if let index = websites.firstIndex(where: { WebsiteAddress($0.url) == address }) {
            websiteList?.reveal(entryAt: index)
            return true
        }
        let site = WebsiteEntry(url: url, title: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                includesSubdomains: includesSubdomains)
        websites.append(site)
        saveWebsites()
        websiteList?.reveal(entryAt: websites.count - 1)
        logStatus("Added \(site.name). Click its shortcut field to assign a key.")
        return true
    }
    // Renames a website and changes its address, keeping its shortcut. An address another
    // website already has is refused, and that website is selected. `includesSubdomains`
    // nil keeps it. False when the text is not a web address (reported), so the sheet can
    // come back.
    @discardableResult
    func updateWebsite(at index: Int, name: String, address text: String, includesSubdomains: Bool? = nil) -> Bool {
        guard websites.indices.contains(index) else { return true }
        guard let parsed = websiteURL(for: text) else { return false }
        let url = parsed.url, address = parsed.address
        if let other = websites.indices.first(where: { $0 != index && WebsiteAddress(websites[$0].url) == address }) {
            websiteList?.reveal(entryAt: other)
            showError(ToolError(message: "\(address.display) is already in Websites as \(websites[other].name)."))
            return true
        }
        websites[index].url = url
        websites[index].title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let includesSubdomains = includesSubdomains { websites[index].includesSubdomains = includesSubdomains }
        saveWebsites()
        websiteList?.reveal(entryAt: index)
        return true
    }
    func removeWebsites() {
        removeSelectedEntries(of: websiteList, from: \.websites, save: saveWebsites)
    }

    // Return or Open in the list, like opening a folder there: switches to
    // an open tab of each website, or opens it in a new tab. Choosing Open is the
    // confirmation, so nothing asks first.
    func openWebsites(_ selection: IndexSet) {
        let sites = selection.compactMap { websites.indices.contains($0) ? websites[$0] : nil }
        guard !sites.isEmpty else { return }
        for site in sites { openWebsite(site) }
    }
    // The address to open and the pages it matches; nil, reported, for a saved address
    // that no longer parses.
    private func destination(of site: WebsiteEntry) -> (url: URL, scope: WebsiteScope)? {
        guard let url = URL(string: site.url), let scope = site.scope else {
            showError(ToolError(message: "Could not open \(site.name). Add the website again."))
            return nil
        }
        return (url, scope)
    }
    private func openWebsite(_ site: WebsiteEntry) {
        guard case let (url, scope)? = destination(of: site) else { return }
        guard let (browser, running) = Browser.runningScriptableDefault() else {
            NSWorkspace.shared.open(url)
            return
        }
        // Choosing Open is the confirmation: with no open tab, the same pass opens one.
        browserTabs.focus(scope, others: otherWebsiteScopes(than: site), in: browser,
                          browserFrontmost: false, orOpen: url) { [weak self] outcome in
            switch outcome {
            case .focused, .opened:
                running.unhideAndBringForward()
            case .notFound, .failed:
                self?.openInBrowser(url)
            case .notPermitted:
                NSWorkspace.shared.open(url)
                self?.reportAutomationDenied(browser)
            }
        }
    }

    // Opens a website's address in a new tab. In a running browser Clutch can script,
    // the tab goes into the window used last, which then comes to the front; otherwise,
    // or when scripting fails, the system opens the address.
    func openInBrowser(_ url: URL) {
        guard let (browser, running) = Browser.runningScriptableDefault() else {
            NSWorkspace.shared.open(url)
            return
        }
        browserTabs.open(url, in: browser) { outcome in
            switch outcome {
            case .opened:
                running.unhideAndBringForward()
            case .notPermitted, .failed:
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: Shortcut

    // Switches to an open tab of the website in the default browser when it can see
    // the tabs (Safari and Chromium browsers, with Automation allowed), like switching
    // to a running app. Otherwise it asks first in the HUD, like launching an app, and
    // opens the address: in a new tab, or by launching the browser.
    func openWebsiteShortcut(_ site: WebsiteEntry) {
        guard !showingLaunchConfirmation, case let (url, scope)? = destination(of: site) else { return }
        guard let (browser, running) = Browser.runningScriptableDefault() else {
            confirmOpening(site, url: url)
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == running.processIdentifier
        // The card stays up while the tabs are looked up, so asking to open continues it
        // instead of the HUD disappearing and coming back.
        capsOverlay.holdCard()
        // With Ask Before Opening off there is nothing to ask in between, so the pass that
        // finds no tab opens one too.
        browserTabs.focus(scope, others: otherWebsiteScopes(than: site), in: browser,
                          browserFrontmost: frontmost, orOpen: asksBeforeOpening ? nil : url) { [weak self] outcome in
            guard let self = self else { return }
            switch outcome {
            case .focused, .opened:
                self.capsOverlay.releaseCard()
                running.unhideAndBringForward()
            case .notFound, .failed:
                self.confirmOpening(site, url: url)
            case .notPermitted:
                if self.confirmOpening(site, url: url) { self.reportAutomationDenied(browser) }
            }
        }
    }
    // Every other website, so a tab one of them owns is left to its own shortcut.
    private func otherWebsiteScopes(than site: WebsiteEntry) -> [WebsiteScope] {
        websites.filter { $0.url != site.url }.compactMap { $0.scope }
    }
    // The launch confirmation, with the website's name and the browser's icon:
    // Return opens the address, Escape cancels. Returns whether it opened.
    // With Ask Before Opening off (General) it opens the address at once.
    @discardableResult
    private func confirmOpening(_ site: WebsiteEntry, url: URL) -> Bool {
        guard !showingLaunchConfirmation else { return false }
        guard asksBeforeOpening else {
            capsOverlay.releaseCard()
            openInBrowser(url)
            return true
        }
        guard askToOpen(site.name, icon: WebsiteEntry.browserIcon) else { return false }
        openInBrowser(url)
        return true
    }
    // Once per browser while Clutch runs: without Automation access every press opens
    // another tab, and nothing else would say why.
    private func reportAutomationDenied(_ browser: Browser) {
        guard !automationDeniedBrowsers.contains(browser.bundleID) else { return }
        automationDeniedBrowsers.insert(browser.bundleID)
        logStatus("Automation access to \(browser.name) is off; opened a new tab.")
        showError(ToolError(message: "Clutch opened a new tab because it is not allowed to see \(browser.name)’s tabs. To switch to a tab that is already open, turn on \(browser.name) for Clutch in System Settings › Privacy & Security › Automation."))
    }
}
