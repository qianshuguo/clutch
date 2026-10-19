import Foundation

// One App List entry: Caps + key activates the application at `path`.
// Named to avoid shadowing SwiftUI.Binding; the stored JSON keys are unchanged.
struct AppShortcut: Codable {
    var key: UInt16
    var name: String
    var path: String
    var bundleID: String?
}
