import Cocoa
import UniformTypeIdentifiers
import ApplicationServices

// Shared by every app mapping. Keep a stable order even when raising a window
// changes the order reported by Accessibility.
struct ApplicationWindowOrder<Window> {
    private var processID: pid_t?
    private var windows: [Window] = []

    // `available` is front to back, as Accessibility lists it. With `frontWhenUnfocused`,
    // focus outside every listed window (Finder's desktop) returns the frontmost one;
    // otherwise such focus never selects an unrelated window.
    mutating func next(processID: pid_t, available: [Window], focused: Window?,
                       cycle: Bool, frontWhenUnfocused: Bool = false,
                       equals: (Window, Window) -> Bool) -> Window? {
        if self.processID != processID || !cycle {
            windows = available
            self.processID = processID
        } else {
            windows.removeAll { old in !available.contains { equals(old, $0) } }
            for window in available where !windows.contains(where: { equals($0, window) }) {
                windows.append(window)
            }
        }
        guard cycle else { return nil }
        guard let focused = focused, let index = windows.firstIndex(where: { equals($0, focused) }) else {
            return frontWhenUnfocused ? available.first : nil
        }
        guard windows.count > 1 else { return nil }
        return windows[(index + 1) % windows.count]
    }
}

final class ApplicationWindowCycle {
    // Finder's desktop takes focus inside Finder but is not listed among its windows.
    static let finderBundleID = "com.apple.finder"
    // Each Accessibility call can wait up to the messaging timeout for a busy app.
    // Run them off the main thread, which also services the keyboard event tap;
    // the serial queue keeps rapid presses in order and owns `order`.
    private let queue = DispatchQueue(label: "local.maxvoid.Clutch.window-cycle", qos: .userInteractive)
    private var order = ApplicationWindowOrder<AXUIElement>()

    // `noWindows` runs on the main thread when the app reports no standard,
    // non-minimized window on the current Space (all closed or all minimized).
    // Activation alone then only switches the menu bar, so the caller reopens it.
    func advance(in app: NSRunningApplication, cycle: Bool, noWindows: @escaping () -> Void) {
        let processID = app.processIdentifier
        // From Finder's desktop, the shortcut returns to the frontmost Finder window.
        let frontWhenUnfocused = app.bundleIdentifier == Self.finderBundleID
        queue.async { [self] in
            if !advance(processID: processID, cycle: cycle, frontWhenUnfocused: frontWhenUnfocused) {
                DispatchQueue.main.async(execute: noWindows)
            }
        }
    }

    // Returns false only when Accessibility answered and listed no usable window;
    // a timeout or error returns true so a busy app is never sent a reopen.
    private func advance(processID: pid_t, cycle: Bool, frontWhenUnfocused: Bool) -> Bool {
        let application = AXQuery.application(processID)
        guard let allWindows = AXQuery.value(application, kAXWindowsAttribute) as? [AXUIElement] else {
            order = ApplicationWindowOrder()
            return true
        }
        let available = allWindows.filter {
            (AXQuery.value($0, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole &&
            (AXQuery.value($0, kAXMinimizedAttribute) as? Bool) == false
        }
        guard !available.isEmpty else {
            order = ApplicationWindowOrder()
            return false
        }
        let focused = AXQuery.element(application, kAXFocusedWindowAttribute)
        guard let next = order.next(processID: processID, available: available, focused: focused, cycle: cycle,
                                    frontWhenUnfocused: frontWhenUnfocused, equals: { CFEqual($0, $1) }) else { return true }
        guard AXUIElementPerformAction(next, kAXRaiseAction as CFString) == .success else { return true }
        AXUIElementSetAttributeValue(next, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(application, kAXFocusedWindowAttribute as CFString, next)
        return true
    }
}

// What an App List, Folders or Websites shortcut opens.
enum ShortcutTarget {
    case app(AppShortcut), folder(FolderEntry), website(WebsiteEntry)
    var name: String {
        switch self {
        case .app(let app): return app.name
        case .folder(let folder): return folder.name
        case .website(let site): return site.name
        }
    }
    // Identifies the target: the app's or folder's path, or the website's address.
    var path: String {
        switch self {
        case .app(let app): return app.path
        case .folder(let folder): return folder.path
        case .website(let site): return site.url
        }
    }
    // Shown on the HUD card.
    var icon: NSImage {
        switch self {
        case .app(let app): return NSWorkspace.shared.icon(forFile: app.path)
        case .folder(let folder): return NSWorkspace.shared.icon(forFile: folder.path)
        case .website: return WebsiteEntry.browserIcon
        }
    }
}

// Whoever holds a shortcut. App List, Folders and Websites share one set of Caps
// shortcuts (up to three keys); a window action holds a single key and takes precedence.
enum ShortcutOwner: Equatable {
    case app(path: String), folder(path: String), website(url: String), window(WindowCommand)
    var isWindow: Bool { if case .window = self { return true }; return false }
}

extension AppDelegate {
    // The App List, Folders or Websites entry Caps + `keys` opens.
    func shortcutTarget(for keys: [UInt16]) -> ShortcutTarget? {
        if let app = bindings.first(where: { $0.matches(keys) }) { return .app(app) }
        if let folder = folders.first(where: { $0.matches(keys) }) { return .folder(folder) }
        return websites.first { $0.matches(keys) }.map { .website($0) }
    }
    // A longer App List, Folders or Websites shortcut starts with `keys`.
    func shortcutExtends(_ keys: [UInt16]) -> Bool {
        bindings.contains { $0.extends(keys) } || folders.contains { $0.extends(keys) }
            || websites.contains { $0.extends(keys) }
    }
    // Called for every key event the tap handles: shows what releasing Caps would
    // open, or hides the hint when there is none (including on Caps release).
    func updateLaunchHint(shortcutsEnabled: Bool) {
        let hint = shortcutsEnabled ? state.launchCandidate.flatMap { shortcutTarget(for: $0) } : nil
        guard hint?.path != capsOverlay.target else { return }
        // Applied together with the keys from updateCapsHUD, after the key event.
        capsOverlay.setApp(hint)
    }

    // Every shortcut in App List, Folders, Websites and Windows, in that order.
    typealias ShortcutEntry = (owner: ShortcutOwner, name: String, keys: [UInt16])
    var allShortcuts: [ShortcutEntry] {
        let apps: [ShortcutEntry] = bindings.map { (owner: ShortcutOwner.app(path: $0.path), name: $0.name, keys: $0.keys) }
        let folderEntries: [ShortcutEntry] = folders.map { (owner: ShortcutOwner.folder(path: $0.path), name: $0.name, keys: $0.keys) }
        let websiteEntries: [ShortcutEntry] = websites.map { (owner: ShortcutOwner.website(url: $0.url), name: $0.name, keys: $0.keys) }
        let actions: [ShortcutEntry] = WindowCommand.allCases.map { command in
            let keys: [UInt16] = windowShortcuts.key(for: command).map { [$0] } ?? []
            return (owner: ShortcutOwner.window(command), name: command.title, keys: keys)
        }
        return apps + folderEntries + websiteEntries + actions
    }
    // The shortcuts `owner` would take by using `keys`, with their names and a line
    // per reason. App List, Folders and Websites conflict on exactly the same keys, and
    // with a window action on the first key. A window action takes every App List,
    // Folders and Websites shortcut that starts with its key.
    func shortcutConflicts(_ keys: [UInt16], for owner: ShortcutOwner) -> (owners: [ShortcutOwner], names: [String], inUse: [String]) {
        guard let first = keys.first else { return ([], [], []) }
        let others = allShortcuts.filter { $0.owner != owner && !$0.keys.isEmpty }
        let entries = others.filter { !$0.owner.isWindow }
        let label = shortcutLabel(keys)
        let same = entries.filter { $0.keys == keys }
        let longer = owner.isWindow ? entries.filter { $0.keys.count > 1 && $0.keys.first == first } : []
        let action = others.filter { $0.owner.isWindow && $0.keys == [first] }
        var inUse: [String] = []
        if !same.isEmpty { inUse.append("\(label) already opens \(listNames(same.map { $0.name })).") }
        if !longer.isEmpty {
            inUse.append("\(label) already starts \(listNames(longer.map { "\($0.name) (\(shortcutLabel($0.keys)))" })).")
        }
        if let command = action.first { inUse.append("\(shortcutLabel([first])) already runs \(command.name).") }
        let taken: [ShortcutEntry] = same + longer + action
        return (taken.map { $0.owner }, taken.map { $0.name }, inUse)
    }
    // `keys` are pressed in order while Caps is held: 1 to AppShortcut.maxKeys of them
    // (⇪M, ⇪M W, ⇪M W E), one for a window action. Shortcuts run when Caps is released,
    // so ⇪M, ⇪M W and ⇪M W E can belong to different owners. Taking a shortcut asks
    // first and names who loses it.
    func assignShortcut(_ keys: [UInt16], to owner: ShortcutOwner, recorder: KeyRecorder) -> Bool {
        guard !keys.isEmpty, keys.count <= (owner.isWindow ? 1 : AppShortcut.maxKeys),
              let name = allShortcuts.first(where: { $0.owner == owner })?.name else { return false }
        guard keys.allSatisfy({ shortcutKeyAvailable($0) }) else { return false }
        let conflicts = shortcutConflicts(keys, for: owner)
        let label = shortcutLabel(keys)
        if !conflicts.owners.isEmpty {
            recorder.cancelRecording()
            guard confirmShortcutReplacement(inUse: conflicts.inUse, shortcut: label, newOwner: name,
                                             losers: conflicts.names) else { return false }
        }
        // Finish recording before reload removes the focused view.
        recorder.recording = false
        let cleared: [ShortcutChange] = conflicts.owners.map { (owner: $0, keys: []) }
        setShortcuts(cleared + [(owner: owner, keys: keys)])
        let replacement = conflicts.names.isEmpty ? "" : ". Cleared shortcut for \(conflicts.names.joined(separator: ", "))"
        logStatus("Saved: \(name) → \(label)\(replacement)")
        return true
    }
    // The ✕ in a shortcut field: the entry stays listed without a shortcut.
    func clearShortcut(of owner: ShortcutOwner) {
        guard let entry = allShortcuts.first(where: { $0.owner == owner }), !entry.keys.isEmpty else { return }
        setShortcuts([(owner: owner, keys: [])])
        logStatus("Cleared shortcut for \(entry.name).")
    }
    // Applies the changes in order (empty keys clear), saving each changed list once.
    typealias ShortcutChange = (owner: ShortcutOwner, keys: [UInt16])
    func setShortcuts(_ changes: [ShortcutChange]) {
        var appsChanged = false, foldersChanged = false, websitesChanged = false, windowsChanged = false
        for change in changes {
            switch change.owner {
            case .app(let path):
                guard let index = bindings.firstIndex(where: { $0.path == path }) else { continue }
                bindings[index].keys = change.keys; appsChanged = true
            case .folder(let path):
                guard let index = folders.firstIndex(where: { $0.path == path }) else { continue }
                folders[index].keys = change.keys; foldersChanged = true
            case .website(let url):
                guard let index = websites.firstIndex(where: { $0.url == url }) else { continue }
                websites[index].keys = change.keys; websitesChanged = true
            case .window(let command):
                if let key = change.keys.first { windowShortcuts.assign(key, to: command) }
                else if let key = windowShortcuts.key(for: command) { windowShortcuts.clear(key) }
                windowsChanged = true
            }
        }
        if appsChanged { saveBindings() }
        if foldersChanged { saveFolders() }
        if websitesChanged { saveWebsites() }
        if windowsChanged { saveWindowShortcuts() }
    }
    // Caps + Space opens Folders, Caps + Delete takes back a key and Caps + Return
    // confirms, so no list can take them.
    func shortcutKeyAvailable(_ code: UInt16) -> Bool {
        guard code == KeyCode.space || code == KeyCode.delete || KeyCode.isReturn(code) else { return true }
        NSSound.beep()
        let use = code == KeyCode.space ? "Folders"
            : code == KeyCode.delete ? "taking back keys while Caps is held" : "confirming"
        logStatus("\(shortcutLabel([code])) is reserved for \(use). Choose another key.")
        return false
    }
    // "A", "A and B", "A, B and C".
    func listNames(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names.last!
    }
    // Example: "⇪M already opens Mail." / "To use ⇪M W for Word, Mail will lose its shortcut."
    // `shortcut` is the full label, ⇪ included.
    func confirmShortcutReplacement(inUse: [String], shortcut: String, newOwner: String, losers: [String]) -> Bool {
        let loses = losers.count == 1 ? "will lose its shortcut" : "will lose their shortcuts"
        return confirmAlert(inUse.joined(separator: "\n"),
                            "To use \(shortcut) for \(newOwner), \(listNames(losers)) \(loses).",
                            confirm: "Replace")
    }
    // Return confirms and Escape cancels, whichever button has focus.
    func confirmAlert(_ message: String, _ informative: String, confirm: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        let confirmButton = alert.addButton(withTitle: confirm)
        confirmButton.keyEquivalent = "\r"
        confirmButton.keyEquivalentModifierMask = []
        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.keyEquivalentModifierMask = []
        return alert.runModal() == .alertFirstButtonReturn
    }

    static var defaultShortcuts: [AppShortcut] {
        // First-run App List. Sorted by name, matching how added apps are ordered.
        let candidates: [(String, UInt16, String)] = [
            ("Finder",3,"/System/Library/CoreServices/Finder.app"),         // Caps + F
            ("Notes",45,"/System/Applications/Notes.app"),                  // Caps + N
            ("Preview",35,"/System/Applications/Preview.app"),              // Caps + P
            ("Reminders",15,"/System/Applications/Reminders.app")]          // Caps + R
        return candidates.filter { FileManager.default.fileExists(atPath: $0.2) }.map {
            AppShortcut(keys: [$0.1], name: $0.0, path: $0.2, bundleID: Bundle(path: $0.2)?.bundleIdentifier)
        }
    }
    // Falls back to the default list when nothing is saved. Unreadable saved data is
    // preserved and reported by the thrown error instead of being silently replaced.
    func loadBindings() throws {
        do {
            bindings = try StoredList.load([AppShortcut].self, forKey: DefaultsKey.shortcuts,
                                           description: "app shortcuts") ?? Self.defaultShortcuts
        } catch {
            bindings = Self.defaultShortcuts
            throw error
        }
    }
    func saveBindings() {
        if let data = try? JSONEncoder().encode(bindings) { UserDefaults.standard.set(data, forKey: DefaultsKey.shortcuts) }
        applicationList?.reload()
    }
    @objc func addBinding() {
        let panel = NSOpenPanel(); panel.title = "Choose an Application"
        panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath:"/Applications")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url, let bundle = Bundle(url:url), bundle.bundleIdentifier != nil else { return }
            let name = (bundle.object(forInfoDictionaryKey:"CFBundleDisplayName") as? String) ?? url.deletingPathExtension().lastPathComponent
            if let index = self.bindings.firstIndex(where: { $0.path == url.path || $0.bundleID == bundle.bundleIdentifier }) {
                self.applicationList?.reveal(bindingAt: index)
                return
            }
            self.bindings.append(AppShortcut(name: name, path: url.path, bundleID: bundle.bundleIdentifier))
            self.bindings.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            self.saveBindings()
            if let index = self.bindings.firstIndex(where: { $0.path == url.path }) {
                self.applicationList?.reveal(bindingAt: index)
            }
            self.logStatus("Added \(name). Click its shortcut field to assign a key.")
        }
    }
    // Rows may be filtered by the search field, so selected rows are mapped back to
    // their applications. The row now at the first removed position is selected.
    @objc func removeBinding() {
        guard let list = applicationList, let firstRow = list.table.selectedRowIndexes.first else { return }
        guard ListSelection.remove(list.selectedBindingIndices, from: &bindings) else { return }
        saveBindings()
        let rows = list.table.numberOfRows
        list.table.selectRowIndexes(rows == 0 ? IndexSet() : IndexSet(integer: min(firstRow, rows - 1)),
                                    byExtendingSelection: false)
    }
    // Command-F on the App List page.
    @objc func findApplication() {
        guard window?.isVisible == true, Self.preferenceTabs[selectedPage].id == "apps" else { NSSound.beep(); return }
        applicationList?.focusSearch()
    }
    // Where the app is now (its saved path, or where its bundle ID moved) and its
    // running instance, if any.
    func locate(_ binding: AppShortcut) -> (url: URL?, running: NSRunningApplication?) {
        let workspace = NSWorkspace.shared
        let original = URL(fileURLWithPath:binding.path)
        let url = FileManager.default.fileExists(atPath:binding.path) ? original : binding.bundleID.flatMap { workspace.urlForApplication(withBundleIdentifier:$0) }
        guard let target = url else { return (nil, nil) }
        let bundleID = Bundle(url: target)?.bundleIdentifier ?? binding.bundleID
        let running = workspace.runningApplications.first {
            !$0.isTerminated && ($0.bundleURL?.standardizedFileURL == target.standardizedFileURL ||
                (bundleID != nil && $0.bundleIdentifier == bundleID))
        }
        return (target, running)
    }
    func activate(_ binding: AppShortcut) {
        guard !showingLaunchConfirmation else { return }
        let workspace = NSWorkspace.shared
        // Checked again here: the app may have opened or quit while Caps was held.
        let (url, running) = locate(binding)
        guard let target = url else { showError(ToolError(message:"Could not find \(binding.name). Add the application again.")); return }
        if let app = running {
            let alreadyFrontmost = workspace.frontmostApplication?.processIdentifier == app.processIdentifier
            closePreferencesForAction()
            if !alreadyFrontmost {
                app.unhide()
                app.bringForward(allWindows: true)
            }
            applicationWindowCycle.advance(in: app, cycle: alreadyFrontmost) {
                AppDelegate.reopen(app, at: target)
            }
            return
        }
        showingLaunchConfirmation = true
        closePreferencesForAction(keepingApplicationActive: true)
        let confirmed = capsOverlay.confirm(appName: binding.name, icon: workspace.icon(forFile: target.path))
        showingLaunchConfirmation = false
        hideDockIfIdle()
        guard confirmed else { return }
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
        workspace.openApplication(at:target, configuration:configuration) { [weak self] app,error in
            DispatchQueue.main.async {
                if let error = error { self?.showError(error) }
                else { app?.unhide(); app?.bringForward(allWindows: true) }
            }
        }
    }
    // NSRunningApplication.activate never sends the reopen Apple Event, so an app
    // whose windows are all closed or minimized becomes frontmost with nothing on
    // screen. Opening the running app again through LaunchServices sends that
    // event, exactly like clicking its Dock icon: Finder/Safari/Terminal open a new
    // window and AppKit apps deminiaturize a minimized one.
    static func reopen(_ app: NSRunningApplication, at fallback: URL) {
        guard !app.isTerminated else { return }
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.bundleURL ?? fallback, configuration: configuration) { _, _ in }
    }
}
