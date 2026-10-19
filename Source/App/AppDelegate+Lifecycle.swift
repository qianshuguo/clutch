import Cocoa

extension AppDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Canvas needs the AppKit event loop, but none of the utility's startup
        // side effects (single-instance exit, mapping recovery, or event taps).
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        // Prevent two instances fighting over the same global mapping.
        // Xcode 15's Canvas host has the same bundle ID but never owns the
        // utility lifecycle or observes reopen requests. Ignore that host.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { app in
               app.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
                   !(app.bundleURL?.path.contains("/Intermediates.noindex/Previews/") ?? false)
           }) {
            DistributedNotificationCenter.default().postNotificationName(reopenNotification, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil); return
        }
        ownsLifecycle = true
        // Copy the former application's settings once when adopting the new identity.
        let defaults = UserDefaults.standard
        if let id = Bundle.main.bundleIdentifier, id == "local.maxvoid.HyperCaps",
           !defaults.bool(forKey: DefaultsKey.migratedHyperKeyPreferences) {
            var preferences = defaults.persistentDomain(forName: "local.maxvoid.HyperKey") ?? [:]
            preferences.merge(defaults.persistentDomain(forName: id) ?? [:]) { _, current in current }
            preferences[DefaultsKey.migratedHyperKeyPreferences] = true
            defaults.setPersistentDomain(preferences, forName: id)
        }
        var loadErrors: [Error] = []
        do { try loadBindings() } catch { loadErrors.append(error) }
        do { try loadFolders() } catch { loadErrors.append(error) }
        createMenu()
        item.isVisible = !defaults.bool(forKey: DefaultsKey.hideStatusBarIcon)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showSettings), name: reopenNotification, object: nil)
        if !loadErrors.isEmpty {
            showError(ToolError(message: loadErrors.map { $0.localizedDescription }.joined(separator: "\n\n")))
        }
        do { try mapping.restore() } catch { showError(error) }
        wantsEnabled = defaults.bool(forKey: DefaultsKey.enabled)
        if wantsEnabled { start() }
        if ProcessInfo.processInfo.arguments.contains("--settings") { showSettings() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc func willSleep() { stop() }
    @objc func didWake() { if wantsEnabled { start() } }
    @objc func quitApp() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ownsLifecycle else { return .terminateNow }
        wantsEnabled = false
        guard let error = teardown() else { return .terminateNow }
        // Never trap the user (or a logout/restart) behind a failing restore.
        setStatus(error.localizedDescription)
        let alert = NSAlert()
        alert.messageText = "Caps Lock could not be restored"
        alert.informativeText = error.localizedDescription + "\n\nIf you quit anyway, Caps Lock stays mapped to F18 until HyperCaps restores it on its next launch or the Mac restarts."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit Anyway")
        NSApp.activateFromBackground()
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        // applicationShouldTerminate already restored the mapping (or the user chose
        // to quit without it); only clean up a tap that is somehow still active.
        if ownsLifecycle, tap != nil { stop() }
    }
}
