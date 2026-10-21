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
    @discardableResult
    private func advance(processID: pid_t, cycle: Bool, frontWhenUnfocused: Bool) -> Bool {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.25)
        func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
            var result: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
            return result
        }
        guard let allWindows = value(application, kAXWindowsAttribute) as? [AXUIElement] else {
            order = ApplicationWindowOrder()
            return true
        }
        let available = allWindows.filter {
            (value($0, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole &&
            (value($0, kAXMinimizedAttribute) as? Bool) == false
        }
        guard !available.isEmpty else {
            order = ApplicationWindowOrder()
            return false
        }
        let focusedValue = value(application, kAXFocusedWindowAttribute)
        let focused: AXUIElement?
        if let focusedValue = focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() {
            focused = (focusedValue as! AXUIElement)
        } else {
            focused = nil
        }
        guard let next = order.next(processID: processID, available: available, focused: focused, cycle: cycle,
                                    frontWhenUnfocused: frontWhenUnfocused, equals: { CFEqual($0, $1) }) else { return true }
        guard AXUIElementPerformAction(next, kAXRaiseAction as CFString) == .success else { return true }
        AXUIElementSetAttributeValue(next, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(application, kAXFocusedWindowAttribute as CFString, next)
        return true
    }
}

// While Caps is held, the app that releasing Caps would open: its icon and name in a
// small HUD at the center of the screen. It never takes focus or mouse events.
// Releasing Caps hides it, unless the app is not running: then the launch
// confirmation takes its place and animates to its second stage in the same window.
final class LaunchHintOverlay {
    // The app path last requested by the key handler, set synchronously in the tap
    // callback so each key press compares against it without waiting for the UI.
    var target: String?
    private var panel: NSPanel?
    private var shownPath: String?
    private let content = LaunchHUDView()
    static let fade: TimeInterval = 0.12

    // The hint's frame while it is on screen, where a launch confirmation takes over.
    var visibleFrame: NSRect? {
        guard let panel = panel, panel.isVisible else { return nil }
        return panel.frame
    }

    func show(_ binding: AppShortcut) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if shownPath != binding.path {
            shownPath = binding.path
            content.icon = NSWorkspace.shared.icon(forFile: binding.path)
            content.name = binding.name
        }
        // The screen with the key window, where the user is working.
        panel.setFrame(LaunchHUD.frame(), display: false)
        if !panel.isVisible { panel.alphaValue = 0; panel.orderFrontRegardless() }
        guard panel.alphaValue < 1 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fade
            panel.animator().alphaValue = 1
        }
    }
    func hide() {
        guard let panel = panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fade
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            // A hint shown again during the fade stays visible.
            if let panel = panel, panel.alphaValue == 0 { panel.orderOut(nil) }
        })
    }
    // Without the fade, once a launch confirmation has taken the hint's place.
    func hideNow() {
        guard let panel = panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 0
        }
        panel.orderOut(nil)
    }
    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: LaunchHUD.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = content
        return panel
    }
}

extension AppDelegate {
    // Called for every key event the tap handles: shows the app that releasing Caps
    // would open, or hides the hint when there is none (including on Caps release).
    func updateLaunchHint(shortcutsEnabled: Bool) {
        let hint = shortcutsEnabled ? state.launchCandidate.flatMap { candidate in
            bindings.first { $0.matches(candidate.first, candidate.second) }
        } : nil
        guard hint?.path != launchHint.target else { return }
        launchHint.target = hint?.path
        afterKeyEvent { [weak self] in
            if let hint = hint { self?.launchHint.show(hint) } else { self?.launchHint.hide() }
        }
    }

    // `second` makes a two-key shortcut (Caps + code + second). Shortcuts run when Caps
    // is released, so Caps + M and Caps + M + W can belong to different apps.
    // Taking a shortcut asks first and names who loses it.
    func assignShortcut(_ code: UInt16, _ second: UInt16? = nil, to binding: AppShortcut, recorder: KeyRecorder) -> Bool {
        guard bindings.contains(where: { $0.path == binding.path }) else { return false }
        guard shortcutKeyAvailable(code), second.map({ self.shortcutKeyAvailable($0) }) ?? true else { return false }
        let conflicts = shortcutConflicts(code, second, excluding: binding.path)
        // A window action on the first key takes precedence; the Windows page shares this rule.
        let windowOwner = windowShortcuts.command(for: code)
        var inUse = conflicts.inUse
        if let command = windowOwner { inUse.append("Caps + \(keyName(code) ?? "?") already runs \(command.title).") }
        let losers = conflicts.indices.map { bindings[$0].name } + (windowOwner.map { [$0.title] } ?? [])
        let name = shortcutName(code, second) ?? "?"
        if !losers.isEmpty {
            recorder.cancelRecording()
            guard confirmShortcutReplacement(inUse: inUse, shortcut: name, newOwner: binding.name, losers: losers) else { return false }
        }
        guard let index = bindings.firstIndex(where: { $0.path == binding.path }) else { return false }
        for otherIndex in conflicts.indices { bindings[otherIndex].clearShortcut() }
        bindings[index].key = code
        bindings[index].secondKey = second
        // Finish recording before reload removes the focused view.
        recorder.recording = false
        saveBindings()
        if windowOwner != nil {
            windowShortcuts.clear(code)
            saveWindowShortcuts()
        }
        let replacement = losers.isEmpty ? "" : ". Cleared shortcut for \(losers.joined(separator: ", "))"
        setStatus("Saved: \(binding.name) → Caps + \(name)\(replacement)")
        return true
    }
    // Other apps that already use exactly Caps + code (+ second).
    func shortcutConflicts(_ code: UInt16, _ second: UInt16?, excluding path: String?) -> (indices: [Int], inUse: [String]) {
        let same = bindings.indices.filter { bindings[$0].path != path && bindings[$0].matches(code, second) }
        guard !same.isEmpty else { return ([], []) }
        return (same, ["Caps + \(shortcutName(code, second) ?? "?") already opens \(listNames(same.map { bindings[$0].name }))."])
    }
    // Apps a window action on `code` would take: window keys win over app shortcuts,
    // including two-key shortcuts that start with the key.
    func firstKeyConflicts(_ code: UInt16) -> (indices: [Int], inUse: [String]) {
        let others = bindings.indices.filter { bindings[$0].hasShortcut && bindings[$0].key == code }
        let alone = others.filter { bindings[$0].secondKey == nil }
        let starts = others.filter { bindings[$0].secondKey != nil }
        let key = keyName(code) ?? "?"
        var inUse: [String] = []
        if !alone.isEmpty { inUse.append("Caps + \(key) already opens \(listNames(alone.map { bindings[$0].name })).") }
        if !starts.isEmpty {
            let names = starts.map { "\(bindings[$0].name) (\(shortcutName(code, bindings[$0].secondKey) ?? "?"))" }
            inUse.append("Caps + \(key) already starts \(listNames(names)).")
        }
        return (alone + starts, inUse)
    }
    // Caps + Space opens Folders, so neither list can take it.
    func shortcutKeyAvailable(_ code: UInt16) -> Bool {
        guard code == KeyCode.space else { return true }
        NSSound.beep()
        setStatus("Caps + Space is reserved for Folders. Choose another key.")
        return false
    }
    // "A", "A and B", "A, B and C".
    func listNames(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names.last!
    }
    // Example: "Caps + M already opens Mail." / "To use Caps + M + W for Word, Mail will lose its shortcut."
    func confirmShortcutReplacement(inUse: [String], shortcut: String, newOwner: String, losers: [String]) -> Bool {
        let alert = NSAlert()
        alert.messageText = inUse.joined(separator: "\n")
        let loses = losers.count == 1 ? "will lose its shortcut" : "will lose their shortcuts"
        alert.informativeText = "To use Caps + \(shortcut) for \(newOwner), \(listNames(losers)) \(loses)."
        let replaceButton = alert.addButton(withTitle: "Replace")
        replaceButton.keyEquivalent = "\r"
        replaceButton.keyEquivalentModifierMask = []
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
            AppShortcut(key: $0.1, name: $0.0, path: $0.2, bundleID: Bundle(path: $0.2)?.bundleIdentifier)
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
            self.bindings.append(AppShortcut(key:unassignedKey,name:name,path:url.path,bundleID:bundle.bundleIdentifier))
            self.bindings.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            self.saveBindings()
            if let index = self.bindings.firstIndex(where: { $0.path == url.path }) {
                self.applicationList?.reveal(bindingAt: index)
            }
            self.setStatus("Added \(name). Click its shortcut field to assign a key.")
        }
    }
    // Rows may be filtered by the search field, so selected rows are mapped back to
    // their applications. The row now at the first removed position is selected.
    @objc func removeBinding() {
        guard let list = applicationList, let firstRow = list.table.selectedRowIndexes.first else { return }
        guard ListSelection.remove(list.selectedBindingIndices, from: &bindings) != nil else { return }
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
        let confirmed = LaunchConfirmation().run(appName: binding.name, icon: workspace.icon(forFile: target.path),
                                                 replacing: launchHint)
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
