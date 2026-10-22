import Foundation

// A standalone Caps release requests a system Caps press. Shortcuts run when Caps
// is released: hold Caps, press one key (Caps + F) or two keys in order
// (Caps + M + W), release Caps. The keys may be released before Caps. Releasing
// Caps decides what was meant, so a key can open an app by itself and also start
// two-key shortcuts. Caps + Space (Folders) opens on press, even after other keys. Window keys preview
// while Caps is held: each press updates the preview, releasing Caps applies it.
struct KeyboardState {
    struct Result {
        var swallow = false
        var stripCommandModifier = false
        // Caps was pressed and released alone (macOS gets it as the Caps key).
        var tap = false
        var showFolders = false
        var openFolderSelection = false
        var folderNumber: Int?
        var folderJump: UInt16?
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
    // The first two keys pressed during this Caps hold, for the on-screen key hint.
    private(set) var pressedKeys: [UInt16] = []
    // Escape while Caps is held: this hold does nothing more, and shows nothing.
    private(set) var escaped = false
    // Show the keys pressed so far ("⇪ M W"): not for Caps + Space (Folders), gestures
    // with Control/Option/Command, which run no Caps shortcut, or after Escape.
    var showsKeyHint: Bool { held && !pressedKeys.isEmpty && !folderGesture && !otherModifierGesture && !escaped }
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
    // This Caps hold started with a window action key; it stays a window gesture (the
    // preview is the feedback, no Caps HUD) until Caps is released.
    var windowGesture: Bool { held && sequenceWindow }
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
    // Shift, Control, Option, Command or Fn; other flags changes (Caps Lock) are not
    // modifier presses.
    static func isModifierKey(_ key: UInt16) -> Bool { modifierMasks[key] != nil }
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
    mutating func modifierChanged(key: UInt16? = nil, otherModifier: Bool, commandModifier: Bool = false, folderSelectionActive: Bool = false, shortcutsEnabled: Bool = true, pressed: Bool = true) -> Result {
        if !pressed {
            return Result(swallow: key.map { consumed.remove($0) != nil } ?? false)
        }
        guard held else { return Result() }
        let swallow = shortcutsEnabled && !folderSelectionActive
        if swallow, let key = key { consumed.insert(key) }
        if otherModifier || commandModifier { otherModifierGesture = true }
        chord = true
        return Result(swallow: swallow)
    }
    // `bound`: the key opens an app by itself. `prefix`: two-key shortcuts start with
    // the key. `comboBound`: `pendingKey` followed by this key is a two-key shortcut.
    mutating func route(key: UInt16, down: Bool, repeated: Bool, bound: Bool, prefix: Bool = false, comboBound: Bool = false, windowKey: Bool = false, otherModifier: Bool = false, commandModifier: Bool = false, folderSelectionActive: Bool = false, folderCount: Int = 0, shortcutsEnabled: Bool = true) -> Result {
        if key == KeyCode.hyper {
            if down {
                // An autorepeat without a tracked press belongs to a gesture that was
                // cancelled (or whose press was missed); it must not start a new
                // standalone gesture, or releasing Caps would send a Caps press.
                if !held && !repeated {
                    held = true; chord = false; otherModifierGesture = otherModifier || commandModifier; folderGesture = false
                    folderSelectionEntered = false
                    pressedKeys = []
                    escaped = false
                    clearSequence()
                }
                return Result(swallow: true)
            }
            let openSelection = held && folderSelectionActive && folderSelectionEntered
            let standalone = held && !chord && !otherModifierGesture
            var result = Result(swallow: true, tap: standalone, openFolderSelection: openSelection)
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
            pressedKeys = []
            folderSelectionEntered = false
            return result
        }
        // Only a new key press makes a chord. A release of a key that was still
        // down when Caps was pressed (fast typing) keeps the standalone Caps.
        if down { beginChord() }
        if down && held && !repeated && pressedKeys.count < 2 && key != KeyCode.escape { pressedKeys.append(key) }
        let stripCommand = held && folderSelectionActive && commandModifier && !otherModifier
        if !down { return Result(swallow: consumed.remove(key) != nil, stripCommandModifier: stripCommand) }
        if consumed.contains(key) { return Result(swallow: true) }
        // Own all new keyboard input destined for the original app during Caps,
        // including invalid shortcuts, repeats and modified/cancelled gestures.
        // Clutch's own focused editors and Folders still receive their input.
        // The shortcut branches below all require this, so they need not insert again.
        let takeOver = held && shortcutsEnabled && !folderSelectionActive
        if takeOver { consumed.insert(key) }
        // Caps + Space opens Folders, whenever Space comes during the hold: it takes over
        // from any shortcut or window preview started before it, so nothing else runs on
        // release. Its repeats and release stay consumed. When blocked (Control, Option or
        // Command, or after Escape), Space is consumed without an action.
        if shortcutsEnabled && held && !folderSelectionActive && key == KeyCode.space && !repeated
            && !otherModifierGesture && !otherModifier && !commandModifier && !folderGesture && !escaped {
            folderGesture = true
            sequenceValid = false
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
        // While Caps stays held, letters select an existing row rather than
        // reaching the search field or its input method. Own their releases too.
        if held && folderSelectionActive && !otherModifier && KeyCode.lettersAndDigits.contains(key) {
            consumed.insert(key)
            return Result(swallow: true, folderJump: repeated ? nil : key)
        }
        // Escape cancels the whole Caps gesture: nothing runs on release (a window
        // preview is dropped) and the key does not reach the app.
        if key == KeyCode.escape && held && shortcutsEnabled && !folderSelectionActive && !repeated {
            escaped = true
            sequenceValid = false
            return Result(swallow: true)
        }
        let actionAllowed = shortcutsEnabled && held && !folderSelectionActive && !repeated && !escaped
            && !otherModifierGesture && !otherModifier && !folderGesture && !commandModifier
        guard actionAllowed else { return Result(swallow: takeOver, stripCommandModifier: stripCommand) }
        if sequence.isEmpty {
            // Window layout keys (arrows, −, =) take precedence over App List bindings.
            // Keep even an unbound first key in the sequence. It invalidates this
            // whole hold instead of letting a later bound key start a new shortcut.
            sequence = [key]
            sequenceWindow = windowKey
            sequenceBound = !windowKey && bound
            sequenceValid = windowKey || bound || prefix
            return Result(swallow: true, windowPreview: windowKey ? key : nil)
        }
        // The keys must match a shortcut exactly. A second key completes a two-key
        // shortcut, including the same key again (Caps + M + M). Any other key, the
        // first key again without Caps + M + M, or a third key means no shortcut runs.
        // Window keys keep updating the preview (← again: 2/3, ↑ again: full, …);
        // any other key, Escape included, cancels it.
        if sequenceWindow {
            guard windowKey && sequenceValid else { sequenceValid = false; return Result(swallow: true) }
            return Result(swallow: true, windowPreview: key)
        }
        if pendingKey != nil && comboBound {
            sequence.append(key)
        } else {
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
