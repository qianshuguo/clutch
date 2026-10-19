import Foundation

// OpenStep plist numbers may deserialize as strings; JSON numbers as NSNumber.
enum MappingCodec {
    static func decode(_ data: Data) throws -> [[String: UInt64]] {
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text == "(null)" || text == "null" { return [] }
        guard let array = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]] else {
            throw NSError(domain: "HyperCaps", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read existing keyboard mappings. Caps Lock was not modified."])
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
                    throw NSError(domain: "HyperCaps", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid keyboard mapping: \(key)"])
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
