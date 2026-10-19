import Cocoa

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
// Keep the host alive for Xcode's injected preview renderer as well as normal runs.
application.run()
