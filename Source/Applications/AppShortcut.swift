import Foundation

// One App List entry: Caps + key (or Caps + key + secondKey) activates the application at `path`.
// Named to avoid shadowing SwiftUI.Binding; the stored JSON keys are unchanged.
// `secondKey` is optional, so lists saved before two-key shortcuts still load.
struct AppShortcut: Codable {
    var key: UInt16
    var name: String
    var path: String
    var bundleID: String?
    var secondKey: UInt16? = nil

    var hasShortcut: Bool { key != unassignedKey }
    func matches(_ first: UInt16, _ second: UInt16?) -> Bool {
        hasShortcut && key == first && secondKey == second
    }
    mutating func clearShortcut() { key = unassignedKey; secondKey = nil }
}

// Field title: "Caps + M", "Caps + M + W", or "Click to set".
func shortcutTitle(_ key: UInt16, _ secondKey: UInt16?) -> String {
    shortcutName(key, secondKey).map { "Caps + \($0)" } ?? "Click to set"
}

// "M" or "M + W"; nil when no key is assigned.
func shortcutName(_ key: UInt16, _ secondKey: UInt16?) -> String? {
    guard let first = keyName(key) else { return nil }
    guard let second = secondKey else { return first }
    return "\(first) + \(keyName(second) ?? "?")"
}
