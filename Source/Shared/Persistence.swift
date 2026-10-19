import Foundation

// UserDefaults keys. The stored names are unchanged so existing preferences still load.
enum DefaultsKey {
    static let enabled = "Enabled"
    static let shortcuts = "Bindings"
    static let folders = "Folders"
    static let hideStatusBarIcon = "HideStatusBarIcon"
    static let capsMappingRecovery = "CapsMappingRecovery"
    static let migratedHyperKeyPreferences = "MigratedHyperKeyPreferences"
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
            throw ToolError(message: "Saved \(description) could not be read, so HyperCaps started without them. The original data was kept in its preferences under “\(backupKey)”.")
        }
    }
}
