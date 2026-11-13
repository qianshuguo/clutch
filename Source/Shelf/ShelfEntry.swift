import Foundation

// A file kept on the Shelf: files you need for a while (an attachment to send, a
// download to read), opened from Caps + Space without a shortcut of their own. Files
// stay until they are removed, or until they are moved or deleted.
// Foundation-only, so the pure tests can compile it.
struct ShelfEntry: Codable, Equatable {
    var path: String
    var added: Date
    // When it was added or last opened from the Shelf; the list is newest first.
    var used: Date

    init(path: String, at date: Date) {
        self.path = path
        added = date
        used = date
    }
    var name: String { FileManager.default.displayName(atPath: path) }
}

enum Shelf {
    // Adds `paths` at the top in the given order; a file already on the Shelf moves up.
    // Returns the paths in the order they now head the list.
    @discardableResult
    static func add(_ paths: [String], to entries: inout [ShelfEntry], at date: Date) -> [String] {
        var seen = Set<String>()
        let unique = paths.map { ($0 as NSString).standardizingPath }.filter { seen.insert($0).inserted }
        guard !unique.isEmpty else { return [] }
        let kept = Dictionary(entries.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        entries.removeAll { seen.contains($0.path) }
        let added = unique.map { path -> ShelfEntry in
            var entry = kept[path] ?? ShelfEntry(path: path, at: date)
            entry.used = date
            return entry
        }
        entries.insert(contentsOf: added, at: 0)
        return unique
    }
    // Opening a file moves it to the top.
    static func markUsed(_ paths: [String], in entries: inout [ShelfEntry], at date: Date) {
        let opened = paths.filter { path in entries.contains { $0.path == path } }
        add(opened, to: &entries, at: date)
    }
    // Drops files that were moved or deleted; nothing leaves for its age.
    // Returns whether anything was dropped.
    @discardableResult
    static func prune(_ entries: inout [ShelfEntry],
                      exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Bool {
        let before = entries.count
        entries.removeAll { !exists($0.path) }
        return entries.count != before
    }

    // MARK: Search

    // How well `name` matches the search, best first, ignoring case, accents and
    // width; nil when it does not match. 0: a word of the name starts with it ("rep" →
    // "Q3 Report.pdf"). 1: it spells the initials of words, in order ("qr"). 2: the name
    // contains it. Chinese characters also match by toneless pinyin, one word per
    // character ("报告": "bao", "baogao", "gao", initials "bg"); the input method's
    // spaces and apostrophes are ignored ("bao'gao").
    static func rank(_ name: String, query: String) -> Int? {
        let search = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !search.isEmpty else { return 0 }
        let spelled = words(name, pinyin: false)
        var best = rank(spelled, search: search)
        if name.unicodeScalars.contains(where: { $0.properties.isIdeographic }) {
            let compact = search.filter { $0 != " " && $0 != "'" }
            if !compact.isEmpty, let byPinyin = rank(words(name, pinyin: true), search: compact) {
                best = min(best ?? byPinyin, byPinyin)
            }
        }
        return best
    }
    // Indexes of the names that match, best match first; equal matches keep list order.
    static func ordered(_ names: [String], query: String) -> [Int] {
        names.indices.compactMap { index in rank(names[index], query: query).map { (index, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }
            .map { $0.0 }
    }
    // The name folded to single characters, and where each word starts: after a space
    // or punctuation, at camel-case humps ("MyReport"), and at each Chinese character
    // (spelled in pinyin when `pinyin` is set).
    private static func words(_ name: String, pinyin: Bool) -> (letters: [Character], starts: [Int]) {
        var letters: [Character] = [], starts: [Int] = []
        var previous: Character?
        for character in name {
            defer { previous = character }
            if pinyin && character.unicodeScalars.allSatisfy({ $0.properties.isIdeographic }) {
                let syllable = NSMutableString(string: String(character))
                CFStringTransform(syllable, nil, kCFStringTransformMandarinLatin, false)
                let spelled = fold(syllable as String).filter { $0.isLetter }
                if !spelled.isEmpty { starts.append(letters.count); letters += spelled }
                continue
            }
            let folded = fold(String(character))
            guard character.isLetter || character.isNumber else { letters += folded; continue }
            let startsWord: Bool
            if let previous = previous {
                startsWord = !(previous.isLetter || previous.isNumber)
                    || (character.isUppercase && previous.isLowercase)
                    || character.unicodeScalars.contains { $0.properties.isIdeographic }
                    || previous.unicodeScalars.contains { $0.properties.isIdeographic }
            } else {
                startsWord = true
            }
            if startsWord { starts.append(letters.count) }
            letters += folded
        }
        return (letters, starts)
    }
    private static func rank(_ words: (letters: [Character], starts: [Int]), search: String) -> Int? {
        let text = String(words.letters)
        let target = Array(search)
        if words.starts.contains(where: { words.letters[$0...].starts(with: target) }) { return 0 }
        let initials = target.filter { $0 != " " }
        if initials.count > 1 {
            var remaining = initials[...]
            for start in words.starts {
                guard let next = remaining.first else { break }
                if words.letters[start] == next { remaining = remaining.dropFirst() }
            }
            if remaining.isEmpty { return 1 }
        }
        return text.contains(search) ? 2 : nil
    }
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}
