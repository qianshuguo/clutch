import Cocoa

final class PreferencesWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        if isKeyWindow, attachedSheet == nil { performClose(sender) }
    }
}
