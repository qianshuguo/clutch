import Foundation

// Caps + key for each window command, edited on the Windows page of Preferences.
// Saved as JSON {command: key code} under DefaultsKey.windowShortcuts, with
// `unassignedKey` for a command without a key. Foundation only, so the pure
// keyboard tests can compile it.
struct WindowShortcuts: Equatable {
    // Commands without a key are absent.
    private var keys: [WindowCommand: UInt16]
    static let defaults = WindowShortcuts(keys: Dictionary(uniqueKeysWithValues: WindowCommand.allCases.map { ($0, $0.defaultKey) }))

    private init(keys: [WindowCommand: UInt16]) { self.keys = keys }

    func key(for command: WindowCommand) -> UInt16? { keys[command] }
    func command(for key: UInt16) -> WindowCommand? {
        WindowCommand.allCases.first { keys[$0] == key }
    }
    // One key belongs to one command: assigning it clears any other command using it.
    mutating func assign(_ key: UInt16, to command: WindowCommand) {
        clear(key)
        keys[command] = key
    }
    mutating func clear(_ key: UInt16) {
        for command in WindowCommand.allCases where keys[command] == key { keys[command] = nil }
    }

    // Commands missing from a save keep their defaults; unreadable data loads the defaults.
    static func load(from defaults: UserDefaults = .standard) -> WindowShortcuts {
        var result = Self.defaults
        guard let data = defaults.data(forKey: DefaultsKey.windowShortcuts),
              let stored = try? JSONDecoder().decode([String: UInt16].self, from: data) else { return result }
        for command in WindowCommand.allCases {
            if let key = stored[command.rawValue] { result.keys[command] = key == unassignedKey ? nil : key }
        }
        // A hand-edited save could repeat a key; keep the first command that claims it.
        var seen = Set<UInt16>()
        for command in WindowCommand.allCases {
            if let key = result.keys[command], !seen.insert(key).inserted { result.keys[command] = nil }
        }
        return result
    }
    func save(to defaults: UserDefaults = .standard) {
        let stored = Dictionary(uniqueKeysWithValues: WindowCommand.allCases.map { ($0.rawValue, keys[$0] ?? unassignedKey) })
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: DefaultsKey.windowShortcuts) }
    }
}
