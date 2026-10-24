import Foundation

struct FolderEntry: Codable, Equatable, KeyShortcut {
    var name: String
    var path: String
    // Caps + these keys, in order, opens the folder from any app (⇪D, ⇪D W, ⇪D W E).
    var keys: [UInt16]

    init(name: String, path: String, keys: [UInt16] = []) {
        self.name = name; self.path = path; self.keys = keys
    }

    // The folder's own name, as Finder shows it now ("Documents", or "文稿" in Chinese).
    // A new entry starts with it; Edit can change `name`, and an empty name in Edit goes
    // back to it. The folder on disk is never renamed.
    var originalName: String { FileManager.default.displayName(atPath: path) }
    var isRenamed: Bool { name != originalName }

    // Saved under "shortcut", left out when there is none.
    private enum CodingKeys: String, CodingKey { case name, path, keys = "shortcut" }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        keys = try container.decodeIfPresent([UInt16].self, forKey: .keys) ?? []
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        if !keys.isEmpty { try container.encode(keys, forKey: .keys) }
    }
}

extension FileManager {
    func isDirectory(atPath path: String) -> Bool {
        var directory: ObjCBool = false
        return fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }
}

// Drop positions are insertion boundaries in the original list.
enum FolderOrder {
    static func move(_ folders: inout [FolderEntry], paths: [String], to boundary: Int) -> IndexSet? {
        let requested = Set(paths)
        let sources = folders.indices.filter { requested.contains(folders[$0].path) }
        guard (0...folders.count).contains(boundary), !sources.isEmpty,
              sources.count == requested.count else { return nil }
        let moving = sources.map { folders[$0] }
        let destination = boundary - sources.filter { $0 < boundary }.count
        for index in sources.reversed() { folders.remove(at: index) }
        folders.insert(contentsOf: moving, at: destination)
        return IndexSet(integersIn: destination..<(destination + moving.count))
    }
}

// Try every selected folder and report failures together after the batch finishes.
enum FolderBatchOpen {
    struct Result {
        var openedCount = 0
        var failures: [String] = []
    }
    static func run(_ folders: [FolderEntry], isDirectory: (String) -> Bool,
                    open: (FolderEntry) -> Bool) -> Result {
        var result = Result()
        for folder in folders {
            guard isDirectory(folder.path) else {
                result.failures.append("Could not find \(folder.name) (\(folder.path)). Add the folder again.")
                continue
            }
            if open(folder) { result.openedCount += 1 }
            else { result.failures.append("Could not open \(folder.name) (\(folder.path)).") }
        }
        return result
    }
}
