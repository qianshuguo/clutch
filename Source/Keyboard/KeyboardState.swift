import Foundation

// A standalone Caps release requests a system Caps press. Shortcuts run when Caps
// is released: hold Caps, press one key (Caps + F) or two keys in order
// (Caps + M + W), release Caps. The keys may be released before Caps. Releasing
// Caps decides what was meant, so a key can open an app by itself and also start
// two-key shortcuts. Caps + Space (Folders) still opens on press. Window keys preview
// while Caps is held: each press updates the preview, releasing Caps applies it.
struct KeyboardState {
    struct Result {
        var swallow = false
        var stripCommandModifier = false
        var tap = false
        var showFolders = false
        var openFolderSelection = false
        var folderNumber: Int?
        // App shortcut to run: Caps + launch, or Caps + launch + launchSecond.
        var launch: UInt16?
        var launchSecond: UInt16?
        // Releasing Caps applies the window preview (the first window key pressed).
        var window: UInt16?
        // A window key pressed while Caps is held: update the preview.
        var windowPreview: UInt16?
    }
    private(set) var held = false
    private(set) var chord = false
    // Shortcut keys pressed during this Caps hold, in order.
    private var sequence: [UInt16] = []
    private var sequenceWindow = false   // the first key is a window action
    private var sequenceBound = false    // the first key opens an app by itself
    private var sequenceValid = false    // false once a key no shortcut uses follows
    // The first key, while a second key could still complete a two-key shortcut.
    var pendingKey: UInt16? { sequence.count == 1 && sequenceValid && !sequenceWindow ? sequence[0] : nil }
    // The app shortcut releasing Caps would run right now (Caps + M, or Caps + M + W),
    // for the on-screen hint. Mirrors the release rules in route(key:).
    var launchCandidate: (first: UInt16, second: UInt16?)? {
        guard held, sequenceValid, !sequenceWindow, !otherModifierGesture, !folderGesture else { return nil }
        if sequence.count == 2 { return (sequence[0], sequence[1]) }
        if sequence.count == 1 && sequenceBound { return (sequence[0], nil) }
        return nil
    }
    // A window preview should stay on screen.
    var windowPreviewActive: Bool { held && sequenceWindow && sequenceValid }
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
    // `bound`: the key opens an app by itself. `prefix`: two-key shortcuts start with
    // the key. `comboBound`: `pendingKey` followed by this key is a two-key shortcut.
    mutating func route(key: UInt16, down: Bool, repeated: Bool, bound: Bool, prefix: Bool = false, comboBound: Bool = false, windowKey: Bool = false, otherModifier: Bool = false, commandModifier: Bool = false, folderSelectionActive: Bool = false, folderCount: Int = 0, shortcutsEnabled: Bool = true) -> Result {
        if key == KeyCode.hyper {
            if down {
                // An autorepeat without a tracked press belongs to a gesture that was
                // cancelled (or whose press was missed); it must not start a new
                // standalone gesture, or releasing Caps would toggle Caps Lock.
                if !held && !repeated {
                    held = true; chord = false; otherModifierGesture = otherModifier || commandModifier; folderGesture = false
                    folderSelectionEntered = false
                    clearSequence()
                }
                return Result(swallow: true)
            }
            let openSelection = held && folderSelectionActive && folderSelectionEntered
            let tap = held && !chord && !otherModifierGesture
            var result = Result(swallow: true, tap: tap, openFolderSelection: openSelection)
            // Releasing Caps runs the shortcut that was pressed.
            if held && sequenceValid && !sequence.isEmpty && shortcutsEnabled && !otherModifierGesture && !folderGesture {
                if sequence.count == 2 {
                    result.launch = sequence[0]; result.launchSecond = sequence[1]
                } else if sequenceWindow {
                    result.window = sequence[0]
                } else if sequenceBound {
                    result.launch = sequence[0]
                }
            }
            clearSequence()
            held = false
            folderSelectionEntered = false
            return result
        }
        // Only a new key press makes a chord. A release of a key that was still
        // down when Caps was pressed (fast typing) keeps the standalone Caps.
        let chordBefore = chord
        if down { beginChord() }
        let stripCommand = held && folderSelectionActive && commandModifier && !otherModifier
        if !down { return Result(swallow: consumed.remove(key) != nil, stripCommandModifier: stripCommand) }
        if consumed.contains(key) { return Result(swallow: true) }
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
        let actionAllowed = shortcutsEnabled && held && !folderSelectionActive && !repeated
            && !otherModifierGesture && !otherModifier && !folderGesture && !commandModifier
        guard actionAllowed else { return Result(stripCommandModifier: stripCommand) }
        if sequence.isEmpty {
            // Window layout keys (arrows, −, =) take precedence over App List bindings.
            // Keys no shortcut uses pass through.
            guard windowKey || bound || prefix else { return Result(stripCommandModifier: stripCommand) }
            consumed.insert(key)
            sequence = [key]
            sequenceWindow = windowKey
            sequenceBound = !windowKey && bound
            sequenceValid = true
            return Result(swallow: true, windowPreview: windowKey ? key : nil)
        }
        // A second key completes a two-key shortcut, including the same key again
        // (Caps + M + M). Pressing the first key again otherwise changes nothing.
        // Any other key means no shortcut runs on release.
        consumed.insert(key)
        // Window keys keep updating the preview (← again: 2/3, ↑ again: full, …);
        // any other key, Escape included, cancels it.
        if sequenceWindow {
            guard windowKey && sequenceValid else { sequenceValid = false; return Result(swallow: true) }
            return Result(swallow: true, windowPreview: key)
        }
        if pendingKey != nil && comboBound {
            sequence.append(key)
        } else if !(sequence.count == 1 && key == sequence[0]) {
            sequenceValid = false
        }
        return Result(swallow: true)
    }
    private mutating func clearSequence() {
        sequence = []; sequenceWindow = false; sequenceBound = false; sequenceValid = false
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
