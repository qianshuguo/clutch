import Cocoa

extension AppDelegate: NSWindowDelegate {
    @objc func closeSettings() { (NSApp.modalWindow ?? NSApp.keyWindow)?.performClose(nil) }
    func hideDockIfIdle() {
        guard window?.isVisible != true, window?.isMiniaturized != true,
              folderWindow?.isVisible != true, !showingLaunchConfirmation else { return }
        if NSApp.activationPolicy() != .accessory { NSApp.setActivationPolicy(.accessory) }
    }
    func closePreferencesForAction(keepingApplicationActive: Bool = false) {
        guard let window = window, window.isVisible || window.isMiniaturized else { return }
        // Keep held Caps and consumed key releases intact as the action takes focus.
        closingPreferencesForAction = true
        defer { closingPreferencesForAction = false }
        window.close()
        // Changing activation policy can deactivate the app. Keep the current
        // policy when another local panel is about to take over, or its resignKey
        // handler would immediately dismiss it. External targets still receive
        // focus only after the Dock transition.
        if !keepingApplicationActive { hideDockIfIdle() }
    }
    @objc func showSettings() {
        // A visible Preferences window participates in the Dock and Command-Tab.
        NSApp.setActivationPolicy(.regular)
        if window == nil { createWindow() }
        syncPreferences()
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil); NSApp.activateFromBackground()
    }
    func windowDidResignKey(_ notification: Notification) {
        (window?.firstResponder as? KeyRecorder)?.cancelRecording()
        if !closingPreferencesForAction { state.cancelGesture() }
    }
    func windowWillClose(_ notification: Notification) {
        if let closed = notification.object as? NSWindow, closed === folderWindow {
            folderWindow = nil; folderList = nil
            hideDockIfIdle()
            return
        }
        guard let closed = notification.object as? NSWindow, closed === window else { return }
        // Drop the settings view tree while the menu-bar utility runs in the background.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.window === closed,
                  !closed.isVisible, !closed.isMiniaturized else { return }
            self.hideDockIfIdle()
            self.window = nil; self.applicationList = nil; self.preferencesFolderList = nil
            self.toggleButton = nil; self.loginCheckbox = nil; self.hideCheckbox = nil
            self.accessibilityNoticeRow = nil; self.windowShortcutList = nil; self.pages = []
        }
    }
}
