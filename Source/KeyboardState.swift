import Foundation

// A standalone Caps release switches input source; a bound chord launches once.
struct KeyboardState {
    struct Result {
        var swallow = false
        var stripCommandModifier = false
        var tap = false
        var showFolders = false
        var openFolderSelection = false
        var folderNumber: Int?
        var launch: UInt16?
    }
    private(set) var held = false
    private(set) var chord = false
    private var otherModifierGesture = false
    private var folderGesture = false
    private var folderSelectionEntered = false
    private var consumed = Set<UInt16>()

    mutating func beginChord() { if held { chord = true } }
    @discardableResult
    mutating func modifierChanged(otherModifier: Bool, commandModifier: Bool = false) -> Result {
        guard held else { return Result() }
        if otherModifier || commandModifier { otherModifierGesture = true }
        chord = true
        return Result()
    }
    mutating func route(key: UInt16, down: Bool, repeated: Bool, bound: Bool, otherModifier: Bool = false, commandModifier: Bool = false, folderSelectionActive: Bool = false) -> Result {
        if key == 79 {
            if down {
                if !held {
                    held = true; chord = false; otherModifierGesture = otherModifier || commandModifier; folderGesture = false
                    folderSelectionEntered = false
                    return Result(swallow: true)
                }
                return Result(swallow: true)
            }
            let openSelection = held && folderSelectionActive && folderSelectionEntered
            let tap = held && !folderSelectionActive && !chord && !otherModifierGesture && !folderGesture
            held = false
            folderSelectionEntered = false
            return Result(swallow: true, tap: tap, openFolderSelection: openSelection)
        }
        let canOpenFolders = held && !chord && !folderGesture && !otherModifierGesture
        beginChord()
        let stripCommand = held && folderSelectionActive && commandModifier && !otherModifier
        if !down { return Result(swallow: consumed.remove(key) != nil, stripCommandModifier: stripCommand) }
        if consumed.contains(key) { return Result(swallow: true) }
        if held && !folderSelectionActive && (key == 36 || key == 76) && down && !repeated && canOpenFolders && !otherModifier && !commandModifier {
            folderGesture = true
            consumed.insert(key)
            return Result(swallow: true, showFolders: true)
        }
        // Only deliberate list navigation arms confirmation on Caps release.
        let selectionKeys: Set<UInt16> = [0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46,
                                         45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6,
                                         29, 18, 19, 20, 21, 23, 22, 26, 28, 25,
                                         123, 124, 125, 126, 115, 119, 116, 121]
        if held && folderSelectionActive && !otherModifier && selectionKeys.contains(key) {
            folderSelectionEntered = true
        }
        // Caps is mapped to F18, so route panel shortcuts here instead of modifier flags.
        let numberKeys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        if held && folderSelectionActive && !repeated && !otherModifier,
           let number = numberKeys.firstIndex(of: key) {
            consumed.insert(key)
            return Result(swallow: true, folderNumber: number)
        }
        if held && !folderSelectionActive && bound && !repeated && !otherModifierGesture && !otherModifier && !folderGesture && !commandModifier {
            consumed.insert(key)
            return Result(swallow: true, launch: key)
        }
        return Result(stripCommandModifier: stripCommand)
    }
    mutating func reset() { self = KeyboardState() }
}

// OpenStep plist numbers may deserialize as strings; JSON numbers as NSNumber.
enum MappingCodec {
    static func decode(_ data: Data) throws -> [[String: UInt64]] {
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text == "(null)" || text == "null" { return [] }
        guard let array = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]] else {
            throw NSError(domain: "HyperKey", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read existing keyboard mappings. Caps Lock was not modified."])
        }
        return try array.map { entry in
            var result: [String: UInt64] = [:]
            for (key, value) in entry {
                let number: UInt64?
                if let value = value as? NSNumber { number = value.uint64Value }
                else if let string = value as? String {
                    number = string.lowercased().hasPrefix("0x") ? UInt64(string.dropFirst(2), radix: 16) : UInt64(string)
                } else { number = nil }
                guard let decoded = number else {
                    throw NSError(domain: "HyperKey", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid keyboard mapping: \(key)"])
                }
                result[key] = decoded
            }
            return result
        }
    }
}


enum MappingPolicy {
    static let src = "HIDKeyboardModifierMappingSrc"
    static let dst = "HIDKeyboardModifierMappingDst"
    static let caps: UInt64 = 0x700000039
    static let f18: UInt64 = 0x70000006D
    static func install(_ current: [[String: UInt64]]) -> [[String: UInt64]] {
        current.filter { $0[src] != caps } + [[src: caps, dst: f18]]
    }
    static func restore(_ current: [[String: UInt64]], previous: [[String: UInt64]]) -> [[String: UInt64]] {
        guard current.contains(where: { $0[src] == caps && $0[dst] == f18 }) else { return current }
        return current.filter { !($0[src] == caps && $0[dst] == f18) } + previous
    }
}


struct FolderEntry: Codable {
    var name: String
    var path: String
}

// Drop positions are insertion boundaries in the original list.
enum FolderOrder {
    static func move(_ folders: inout [FolderEntry], path: String, to boundary: Int) -> Int? {
        move(&folders, paths: [path], to: boundary)?.first
    }

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
