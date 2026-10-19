import Cocoa
import UniformTypeIdentifiers
import ApplicationServices

// Shared by every app mapping. Keep a stable order even when raising a window
// changes the order reported by Accessibility.
struct ApplicationWindowOrder<Window> {
    private var processID: pid_t?
    private var windows: [Window] = []

    mutating func next(processID: pid_t, available: [Window], focused: Window?,
                       cycle: Bool, equals: (Window, Window) -> Bool) -> Window? {
        if self.processID != processID || !cycle {
            windows = available
            self.processID = processID
        } else {
            windows.removeAll { old in !available.contains { equals(old, $0) } }
            for window in available where !windows.contains(where: { equals($0, window) }) {
                windows.append(window)
            }
        }
        guard cycle, windows.count > 1, let focused = focused,
              let index = windows.firstIndex(where: { equals($0, focused) }) else { return nil }
        return windows[(index + 1) % windows.count]
    }
}

final class ApplicationWindowCycle {
    // Each Accessibility call can wait up to the messaging timeout for a busy app.
    // Run them off the main thread, which also services the keyboard event tap;
    // the serial queue keeps rapid presses in order and owns `order`.
    private let queue = DispatchQueue(label: "local.maxvoid.HyperCaps.window-cycle", qos: .userInteractive)
    private var order = ApplicationWindowOrder<AXUIElement>()

    // `noWindows` runs on the main thread when the app reports no standard,
    // non-minimized window on the current Space (all closed or all minimized).
    // Activation alone then only switches the menu bar, so the caller reopens it.
    func advance(in app: NSRunningApplication, cycle: Bool, noWindows: @escaping () -> Void) {
        let processID = app.processIdentifier
        queue.async { [self] in
            if !advance(processID: processID, cycle: cycle) { DispatchQueue.main.async(execute: noWindows) }
        }
    }

    // Returns false only when Accessibility answered and listed no usable window;
    // a timeout or error returns true so a busy app is never sent a reopen.
    @discardableResult
    private func advance(processID: pid_t, cycle: Bool) -> Bool {
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
        guard let next = order.next(processID: processID, available: available,
                                    focused: focused, cycle: cycle, equals: { CFEqual($0, $1) }) else { return true }
        guard AXUIElementPerformAction(next, kAXRaiseAction as CFString) == .success else { return true }
        AXUIElementSetAttributeValue(next, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(application, kAXFocusedWindowAttribute as CFString, next)
        return true
    }
}

extension AppDelegate {
    func assignShortcut(_ code: UInt16, to binding: AppShortcut, recorder: KeyRecorder) -> Bool {
        guard bindings.contains(where: { $0.path == binding.path }) else { return false }
        guard shortcutKeyAvailable(code) else { return false }
        // A key belongs to one app or one window action; the Windows page shares this rule.
        let windowOwner = windowShortcuts.command(for: code)
        let replacedNames: [String] = bindings.indices.filter { bindings[$0].path != binding.path && bindings[$0].key == code }
            .map { bindings[$0].name } + (windowOwner.map { [$0.title] } ?? [])
        if !replacedNames.isEmpty {
            recorder.cancelRecording()
            guard confirmShortcutReplacement(code, owners: replacedNames, newOwner: binding.name) else { return false }
        }
        guard let index = bindings.firstIndex(where: { $0.path == binding.path }) else { return false }
        for otherIndex in bindings.indices where otherIndex != index && bindings[otherIndex].key == code {
            bindings[otherIndex].key = unassignedKey
        }
        bindings[index].key = code
        // Finish recording before reload removes the focused view.
        recorder.recording = false
        saveBindings()
        if windowOwner != nil {
            windowShortcuts.clear(code)
            saveWindowShortcuts()
        }
        let replacement = replacedNames.isEmpty ? "" : ". Cleared shortcut for \(replacedNames.joined(separator: ", "))"
        setStatus("Saved: \(binding.name) → Caps + \(keyName(code) ?? "?")\(replacement)")
        return true
    }
    // Caps + Space opens Folders, so neither list can take it.
    func shortcutKeyAvailable(_ code: UInt16) -> Bool {
        guard code == KeyCode.space else { return true }
        NSSound.beep()
        setStatus("Caps + Space is reserved for Folders. Choose another key.")
        return false
    }
    func confirmShortcutReplacement(_ code: UInt16, owners: [String], newOwner: String) -> Bool {
        let names = owners.joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = "Replace shortcut?"
        alert.informativeText = "Caps + \(keyName(code) ?? "?") is already assigned to \(names). Replace it with \(newOwner)? \(names) will stay in the list without a shortcut."
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
        table?.reloadData()
    }
    @objc func addBinding() {
        let panel = NSOpenPanel(); panel.title = "Choose an Application"
        panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath:"/Applications")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url, let bundle = Bundle(url:url), bundle.bundleIdentifier != nil else { return }
            let name = (bundle.object(forInfoDictionaryKey:"CFBundleDisplayName") as? String) ?? url.deletingPathExtension().lastPathComponent
            if let index = self.bindings.firstIndex(where: { $0.path == url.path || $0.bundleID == bundle.bundleIdentifier }) {
                self.table?.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                self.table?.scrollRowToVisible(index)
                return
            }
            self.bindings.append(AppShortcut(key:unassignedKey,name:name,path:url.path,bundleID:bundle.bundleIdentifier))
            self.bindings.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            self.saveBindings()
            if let index = self.bindings.firstIndex(where: { $0.path == url.path }) {
                self.table?.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                self.table?.scrollRowToVisible(index)
            }
            self.setStatus("Added \(name). Click its shortcut field to assign a key.")
        }
    }
    @objc func removeBinding() {
        guard let table = table else { return }
        guard let selection = ListSelection.remove(table.selectedRowIndexes, from: &bindings) else { return }
        saveBindings()
        table.selectRowIndexes(selection, byExtendingSelection: false)
    }
    func activate(_ binding: AppShortcut) {
        guard !showingLaunchConfirmation else { return }
        let workspace = NSWorkspace.shared
        let original = URL(fileURLWithPath:binding.path)
        let url = FileManager.default.fileExists(atPath:binding.path) ? original : binding.bundleID.flatMap { workspace.urlForApplication(withBundleIdentifier:$0) }
        guard let target = url else { showError(ToolError(message:"Could not find \(binding.name). Add the application again.")); return }
        let bundleID = Bundle(url: target)?.bundleIdentifier ?? binding.bundleID
        let running = workspace.runningApplications.first {
            !$0.isTerminated && ($0.bundleURL?.standardizedFileURL == target.standardizedFileURL ||
                (bundleID != nil && $0.bundleIdentifier == bundleID))
        }
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
        let confirmed = LaunchConfirmation().run(appName: binding.name)
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
