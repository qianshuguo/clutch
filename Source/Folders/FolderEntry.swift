import Foundation

struct FolderEntry: Codable {
    var name: String
    var path: String
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
