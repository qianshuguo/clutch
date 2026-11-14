import Foundation

// UserDefaults keys. The stored names are unchanged so existing preferences still load.
enum DefaultsKey {
    static let enabled = "Enabled"
    static let shortcuts = "Bindings"
    static let folders = "Folders"
    static let websites = "Websites"
    static let shelf = "Shelf"
    static let windowShortcuts = "WindowShortcuts"
    static let hideStatusBarIcon = "HideStatusBarIcon"
    static let capsMappingRecovery = "CapsMappingRecovery"
    // Off by default: an app that is not running, or a website with no open tab, asks first.
    static let skipLaunchConfirmation = "SkipLaunchConfirmation"
}

enum StoredList {
    // Returns nil when nothing is saved. Data that cannot be decoded is moved to
    // "<key>.unreadable" before any later save could overwrite it, then reported.
    static func load<T: Decodable>(_ type: T.Type, forKey key: String, description: String,
                                   defaults: UserDefaults = .standard) throws -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let backupKey = key + ".unreadable"
            defaults.set(data, forKey: backupKey)
            defaults.removeObject(forKey: key)
            throw ToolError(message: "Saved \(description) could not be read, so Clutch started without them. The original data was kept in its preferences under “\(backupKey)”.")
        }
    }
    static func save<T: Encodable>(_ list: T, forKey key: String, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: key) }
    }
}

// An entry its list finds by path (Folders, the Shelf).
protocol PathEntry {
    var path: String { get }
}

// Reordering by dragging rows.
enum ListOrder {
    // Moves the entries with these paths, in their list order, to `boundary`, an
    // insertion position in the list before the move (a dragged row's drop position).
    // Returns the rows they now take, or nil when a path is not in the list.
    static func move<Entry: PathEntry>(_ entries: inout [Entry], paths: [String], to boundary: Int) -> IndexSet? {
        let requested = Set(paths)
        let sources = entries.indices.filter { requested.contains(entries[$0].path) }
        guard (0...entries.count).contains(boundary), !sources.isEmpty,
              sources.count == requested.count else { return nil }
        let moving = sources.map { entries[$0] }
        let destination = boundary - sources.filter { $0 < boundary }.count
        for index in sources.reversed() { entries.remove(at: index) }
        entries.insert(contentsOf: moving, at: destination)
        return IndexSet(integersIn: destination..<(destination + moving.count))
    }
}
