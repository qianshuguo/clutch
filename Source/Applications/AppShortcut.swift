import Foundation

// One App List entry: Caps + up to three keys in order (Caps + M, Caps + M + W,
// Caps + M + W + E) activates the application at `path`.
struct AppShortcut: Codable, Equatable, KeyShortcut {
    var keys: [UInt16]
    var name: String
    var path: String
    var bundleID: String?

    // Keys one shortcut may use after Caps.
    static let maxKeys = KeyboardState.maxShortcutKeys

    init(keys: [UInt16] = [], name: String, path: String, bundleID: String?) {
        self.keys = keys; self.name = name; self.path = path; self.bundleID = bundleID
    }

    // Saved as "key" (`unassignedKey` for none) plus optional "secondKey" / "thirdKey".
    private enum CodingKeys: String, CodingKey { case key, secondKey, thirdKey, name, path, bundleID }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let first = try container.decode(UInt16.self, forKey: .key)
        let second = try container.decodeIfPresent(UInt16.self, forKey: .secondKey)
        let third = try container.decodeIfPresent(UInt16.self, forKey: .thirdKey)
        keys = first == unassignedKey ? [] : [first] + [second, third].compactMap { $0 }
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keys.first ?? unassignedKey, forKey: .key)
        try container.encodeIfPresent(keys.count > 1 ? keys[1] : nil, forKey: .secondKey)
        try container.encodeIfPresent(keys.count > 2 ? keys[2] : nil, forKey: .thirdKey)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(bundleID, forKey: .bundleID)
    }
}

// Caps Lock as shown in shortcut fields and messages, like ⌘ or ⌥ in macOS menus.
let capsSymbol = "⇪"

// "M", "M W", "M W E"; nil when no key is assigned.
func shortcutName(_ keys: [UInt16]) -> String? {
    guard let first = keys.first, keyName(first) != nil else { return nil }
    return keys.map { keyName($0) ?? "?" }.joined(separator: " ")
}

// "⇪M", "⇪M W", "⇪M W E"; "⇪?" when no key is assigned.
func shortcutLabel(_ keys: [UInt16]) -> String {
    capsSymbol + (shortcutName(keys) ?? "?")
}

// Field title: "⇪M", "⇪M W", "⇪M W E", or the empty-field placeholder.
func shortcutTitle(_ keys: [UInt16]) -> String {
    shortcutName(keys).map { capsSymbol + $0 } ?? KeyRecorder.emptyTitle
}
