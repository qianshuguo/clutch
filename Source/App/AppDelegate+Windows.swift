import Cocoa

extension AppDelegate: NSWindowDelegate {
    @objc func closeSettings() { (NSApp.modalWindow ?? NSApp.keyWindow)?.performClose(nil) }
    func hideDockIfIdle() {
        guard window?.isVisible != true, !showingLaunchConfirmation else { return }
        if NSApp.activationPolicy() != .accessory { NSApp.setActivationPolicy(.accessory) }
    }
    @objc func showSettings() {
        // A visible Preferences window participates in the Dock and Command-Tab.
        NSApp.setActivationPolicy(.regular)
        if window == nil { createWindow() }
        syncPreferences()
        window.makeKeyAndOrderFront(nil); NSApp.activateFromBackground()
    }
    func windowDidResignKey(_ notification: Notification) {
        // Only a recording ends here. A held Caps gesture survives focus moving
        // to another app or panel: its state lives with the event tap, not with
        // any window, and missed releases are caught there from hardware state.
        (window?.firstResponder as? KeyRecorder)?.cancelRecording()
    }
    func windowWillClose(_ notification: Notification) {
        if let closed = notification.object as? NSWindow, closed === shelfPanel {
            // Built again on the next Caps + Space.
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.shelfPanel === closed, !closed.isVisible else { return }
                self.shelfPanel = nil; self.shelfList = nil
            }
            return
        }
        guard let closed = notification.object as? NSWindow, closed === window else { return }
        // Drop the settings view tree while the menu-bar utility runs in the background.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.window === closed, !closed.isVisible else { return }
            self.hideDockIfIdle()
            self.window = nil; self.applicationList = nil; self.folderList = nil
            self.toggleButton = nil; self.loginCheckbox = nil; self.hideCheckbox = nil
            self.askBeforeOpeningCheckbox = nil
            self.accessibilityHint = nil; self.accessibilityNotice = nil; self.windowShortcutList = nil; self.websiteList = nil
            self.pages = []
        }
    }
}

func isWindowCloseShortcut(_ event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
    return (event.keyCode == KeyCode.escape && modifiers.isEmpty) || (event.keyCode == KeyCode.w && modifiers == .command)
}

// Focus changes requested by this background (accessory) utility in response to
// global shortcuts. macOS 14 deprecates "ignoring other apps"; the long-standing
// calls are kept here unchanged until NSApp.activate()/yieldActivation are verified
// to bring Clutch panels forward reliably from the background.
extension NSApplication {
    func activateFromBackground() { activate(ignoringOtherApps: true) }
}
extension NSRunningApplication {
    func bringForward(allWindows: Bool = false) {
        activate(options: allWindows ? [.activateAllWindows, .activateIgnoringOtherApps] : [.activateIgnoringOtherApps])
    }
    // The same for an app that may be hidden (⌘H).
    func unhideAndBringForward(allWindows: Bool = false) {
        unhide()
        bringForward(allWindows: allWindows)
    }
}

// Shared focus snapshot for transient panels; outside clicks do not restore it.
final class PreviousFocus {
    private let application = NSWorkspace.shared.frontmostApplication
    private weak var window: NSWindow? = NSApp.keyWindow

    func restore() {
        if application?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            guard let window = window, window.isVisible else { return }
            NSApp.activateFromBackground()
            window.makeKeyAndOrderFront(nil)
        } else if let application = application, !application.isTerminated {
            application.bringForward()
        }
    }
}
