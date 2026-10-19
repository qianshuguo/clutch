import Cocoa

func isWindowCloseShortcut(_ event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
    return (event.keyCode == KeyCode.escape && modifiers.isEmpty) || (event.keyCode == KeyCode.w && modifiers == .command)
}

// Focus changes requested by this background (accessory) utility in response to
// global shortcuts. macOS 14 deprecates "ignoring other apps"; the long-standing
// calls are kept here unchanged until NSApp.activate()/yieldActivation are verified
// to bring HyperCaps panels forward reliably from the background.
extension NSApplication {
    func activateFromBackground() { activate(ignoringOtherApps: true) }
}
extension NSRunningApplication {
    func bringForward(allWindows: Bool = false) {
        activate(options: allWindows ? [.activateAllWindows, .activateIgnoringOtherApps] : [.activateIgnoringOtherApps])
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
