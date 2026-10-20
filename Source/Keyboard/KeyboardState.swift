import Foundation

// A standalone Caps release requests a system Caps press; a bound chord launches once.
// Two-key shortcuts (Caps + M + W) use the first key as a prefix: pressing it waits
// for the second key for as long as Caps stays held; the prefix itself may be released.
// If no second key follows, releasing Caps runs the prefix's one-key shortcut, if any.
// Pressing the prefix again runs that one-key shortcut for the previous press, so
// repeated taps still cycle windows.
struct KeyboardState {
    struct Result {
        var swallow = false
        var stripCommandModifier = false
        var tap = false
        var showFolders = false
        var openFolderSelection = false
        var folderNumber: Int?
        var launch: UInt16?
        // True when `launch` is the second key of a two-key shortcut.
        var launchCombo = false
        var window: UInt16?
    }
    private(set) var held = false
    private(set) var chord = false
    // First key of a two-key shortcut, waiting for its second key.
    private(set) var pendingPrefix: UInt16?
    // Whether releasing Caps (or pressing the prefix again) runs its one-key shortcut.
    private var pendingSingle = false
    private var otherModifierGesture = false
    private var folderGesture = false
    private var folderSelectionEntered = false
    private var consumed = Set<UInt16>()
    private static let selectionKeys = Set(KeyCode.lettersAndDigits + KeyCode.navigation)
    private static let numberKeys = KeyCode.digits1to9

    // Raw CGEventFlags device-independent masks, kept numeric so this file
    // stays free of CoreGraphics and remains part of the pure keyboard tests.
    private static let modifierMasks: [UInt16: UInt64] = [
        56: 0x20000, 60: 0x20000,     // Shift
        59: 0x40000, 62: 0x40000,     // Control
        58: 0x80000, 61: 0x80000,     // Option
        55: 0x100000, 54: 0x100000,   // Command
        63: 0x800000                  // Fn
    ]
    // A flagsChanged event is a release when its key's modifier flag is clear.
    // Unknown modifier keys count as presses, keeping the cautious behavior.
    static func modifierPressed(key: UInt16, flags: UInt64) -> Bool {
        guard let mask = modifierMasks[key] else { return true }
        return flags & mask != 0
    }

    mutating func beginChord() { if held { chord = true } }
    // Releasing a modifier that was already down before Caps (for example,
    // Shift from the previous word) must not cancel a standalone Caps press.
    @discardableResult
    mutating func modifierChanged(otherModifier: Bool, commandModifier: Bool = false, folderSelectionActive: Bool = false, shortcutsEnabled: Bool = true, pressed: Bool = true) -> Result {
        guard held, pressed else { return Result() }
        if otherModifier || commandModifier { otherModifierGesture = true }
        chord = true
        return Result()
    }
    // `bound`: the key has a one-key shortcut. `prefix`: the key starts a two-key
    // shortcut. `comboBound`: `pendingPrefix` followed by this key is a two-key shortcut.
    mutating func route(key: UInt16, down: Bool, repeated: Bool, bound: Bool, prefix: Bool = false, comboBound: Bool = false, windowKey: Bool = false, otherModifier: Bool = false, commandModifier: Bool = false, folderSelectionActive: Bool = false, folderCount: Int = 0, shortcutsEnabled: Bool = true) -> Result {
        if key == KeyCode.hyper {
            if down {
                // An autorepeat without a tracked press belongs to a gesture that was
                // cancelled (or whose press was missed); it must not start a new
                // standalone gesture, or releasing Caps would toggle Caps Lock.
                if !held && !repeated {
                    held = true; chord = false; otherModifierGesture = otherModifier || commandModifier; folderGesture = false
                    folderSelectionEntered = false
                }
                return Result(swallow: true)
            }
            let openSelection = held && folderSelectionActive && folderSelectionEntered
            let tap = held && !chord && !otherModifierGesture
            // A prefix still waiting when Caps is released runs its one-key shortcut.
            let single = held && pendingPrefix != nil && pendingSingle && shortcutsEnabled && !otherModifierGesture
            let launch = single ? pendingPrefix : nil
            pendingPrefix = nil; pendingSingle = false
            held = false
            folderSelectionEntered = false
            return Result(swallow: true, tap: tap, openFolderSelection: openSelection, launch: launch)
        }
        // Only a new key press makes a chord. A release of a key that was still
        // down when Caps was pressed (fast typing) keeps the standalone Caps.
        let chordBefore = chord
        if down { beginChord() }
        let stripCommand = held && folderSelectionActive && commandModifier && !otherModifier
        if !down { return Result(swallow: consumed.remove(key) != nil, stripCommandModifier: stripCommand) }
        if consumed.contains(key) { return Result(swallow: true) }
        let actionAllowed = shortcutsEnabled && held && !folderSelectionActive && !repeated
            && !otherModifierGesture && !otherModifier && !folderGesture && !commandModifier
        // The key after a prefix completes a two-key shortcut. Pressing the prefix again
        // runs its one-key shortcut and keeps waiting. Any other key cancels the prefix
        // (its one-key shortcut no longer runs) and is handled normally.
        if let waiting = pendingPrefix {
            if key == waiting && actionAllowed {
                consumed.insert(key)
                return Result(swallow: true, launch: pendingSingle ? key : nil)
            }
            pendingPrefix = nil; pendingSingle = false
            if actionAllowed && comboBound {
                consumed.insert(key)
                return Result(swallow: true, launch: key, launchCombo: true)
            }
        }
        // Caps + Space opens Folders. Space must be the first key of the chord;
        // its repeats and release stay consumed. When blocked, Space types normally.
        if shortcutsEnabled && held && !folderSelectionActive && key == KeyCode.space && !repeated && !chordBefore
            && !otherModifierGesture && !otherModifier && !commandModifier && !folderGesture {
            consumed.insert(key)
            folderGesture = true
            return Result(swallow: true, showFolders: true)
        }
        // Invalid numbers must not confirm the previously selected folder.
        if held && folderSelectionActive && !otherModifier,
           let number = Self.numberKeys.firstIndex(of: key) {
            consumed.insert(key)
            guard !repeated else { return Result(swallow: true) }
            folderSelectionEntered = number < folderCount
            return Result(swallow: true, folderNumber: folderSelectionEntered ? number : nil)
        }
        // Only deliberate list navigation arms confirmation on Caps release.
        if held && folderSelectionActive && !otherModifier && Self.selectionKeys.contains(key) {
            folderSelectionEntered = folderCount > 0
        }
        // Window layout keys (arrows, −, =) take precedence over App List bindings.
        if shortcutsEnabled && held && !folderSelectionActive && windowKey && !repeated && !otherModifierGesture && !otherModifier && !folderGesture && !commandModifier {
            consumed.insert(key)
            return Result(swallow: true, window: key)
        }
        // Start a two-key shortcut; the decision waits for the next key or the release.
        if actionAllowed && prefix && !windowKey {
            consumed.insert(key)
            pendingPrefix = key
            pendingSingle = bound
            return Result(swallow: true)
        }
        if shortcutsEnabled && held && !folderSelectionActive && bound && !windowKey && !repeated && !otherModifierGesture && !otherModifier && !folderGesture && !commandModifier {
            consumed.insert(key)
            return Result(swallow: true, launch: key)
        }
        return Result(stripCommandModifier: stripCommand)
    }
    // Focus changes cancel chord actions, but preserve standalone Caps and
    // ownership of swallowed shortcut releases.
    mutating func cancelGesture() {
        let standalone = held && !chord && !otherModifierGesture
        let pendingReleases = consumed
        reset()
        held = standalone
        consumed = pendingReleases
    }
    // Secure Event Input (password fields, Terminal's Secure Keyboard Entry) hides key
    // releases from event taps. Stop owning consumed keys the hardware reports as up,
    // or each one would be swallowed on every later press. `current` is the key of the
    // event being handled, whose state the event itself describes.
    mutating func dropMissedReleases(except current: UInt16, isDown: (UInt16) -> Bool) {
        guard !consumed.isEmpty else { return }
        consumed = consumed.filter { $0 == current || isDown($0) }
    }
    // The tap saw input while Caps was believed held, but the hardware reports it up:
    // its release was hidden from the tap. End the gesture without a Caps replay, so
    // ordinary typing can never launch applications. Pending key releases stay owned.
    mutating func capsReleaseMissed() {
        let pendingReleases = consumed
        reset()
        consumed = pendingReleases
    }
    mutating func reset() { self = KeyboardState() }
}
