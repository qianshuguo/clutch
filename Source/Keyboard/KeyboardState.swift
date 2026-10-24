import Foundation

// A standalone Caps release requests a system Caps press. Shortcuts run when Caps
// is released: hold Caps, press one key (Caps + F) or up to three keys in order
// (Caps + M + W, Caps + M + W + E), release Caps, or press Return to run it at once.
// Keys after the third are ignored. The keys may be released before Caps. Releasing Caps decides what was meant, so keys can open an app by themselves
// and also start longer shortcuts. Caps + Space (Folders) opens on press, even after other keys. Window keys preview
// while Caps is held: each press updates the preview, releasing Caps applies it.
struct KeyboardState {
    // Keys one app shortcut may use after Caps.
    static let maxShortcutKeys = 3
    // Who gets keys pressed while Caps is held.
    enum Input {
        // Caps shortcuts (App List, Folders, window actions, Caps + Space).
        case shortcuts
        // The focused Folders picker: numbers, letters and navigation select a folder.
        case folderPicker
        // Clutch's own focused input (a shortcut being recorded, the launch
        // confirmation, renaming): keys pass through and run no shortcut.
        case inactive
    }
    struct Result {
        var swallow = false
        var stripCommandModifier = false
        // Caps was pressed and released alone (macOS gets it as the Caps key).
        var tap = false
        var showFolders = false
        var openFolderSelection = false
        var folderNumber: Int?
        var folderJump: UInt16?
        // The keys of the App List or Folders shortcut to run, in order.
        var launchKeys: [UInt16]?
        // Releasing Caps applies the window preview (the first window key pressed).
        var window: UInt16?
        // A window key pressed while Caps is held: update the preview.
        var windowPreview: UInt16?
    }
    private(set) var held = false
    private(set) var chord = false
    // The first keys pressed during this Caps hold (up to maxShortcutKeys), for the on-screen key hint.
    private(set) var pressedKeys: [UInt16] = []
    // Escape while Caps is held: this hold does nothing more, and shows nothing.
    private(set) var escaped = false
    // Show the keys pressed so far ("⇪ M W"): not for Caps + Space (Folders), gestures
    // with Control/Option/Command, which run no Caps shortcut, or after Escape.
    var showsKeyHint: Bool { held && !pressedKeys.isEmpty && !folderGesture && !otherModifierGesture && !escaped }
    // Shortcut keys pressed during this Caps hold, in order.
    private var sequence: [UInt16] = []
    private var sequenceWindow = false   // the first key is a window action
    private var sequenceBound = false    // the keys so far open an app by themselves
    private var sequenceValid = false    // false once a key no shortcut uses follows
    // The app keys pressed so far, while another key could still extend them.
    var pendingKeys: [UInt16]? {
        guard sequenceValid, !sequenceWindow, !sequence.isEmpty, sequence.count < Self.maxShortcutKeys else { return nil }
        return sequence
    }
    // The app shortcut releasing Caps would run right now (Caps + M, Caps + M + W, …),
    // for the on-screen hint. Mirrors the release rules in route(key:).
    var launchCandidate: [UInt16]? {
        guard held, sequenceValid, sequenceBound, !sequenceWindow, !otherModifierGesture, !folderGesture else { return nil }
        return sequence
    }
    // This Caps hold started with a window action key; it stays a window gesture (the
    // preview is the feedback, no Caps HUD) until Caps is released.
    var windowGesture: Bool { held && sequenceWindow }
    // A window preview should stay on screen.
    var windowPreviewActive: Bool { held && sequenceWindow && sequenceValid }
    // What this hold looked like before each shortcut key, so Delete (still holding
    // Caps) can take the last key back: Caps + M + W, Delete → Caps + M.
    private struct Step {
        var sequence: [UInt16]
        var window: Bool
        var bound: Bool
        var valid: Bool
        var pressedKeys: [UInt16]
    }
    private var steps: [Step] = []
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
    mutating func modifierChanged(key: UInt16? = nil, otherModifier: Bool, commandModifier: Bool = false, input: Input = .shortcuts, pressed: Bool = true) -> Result {
        if !pressed {
            return Result(swallow: key.map { consumed.remove($0) != nil } ?? false)
        }
        guard held else { return Result() }
        let swallow = input == .shortcuts
        if swallow, let key = key { consumed.insert(key) }
        if otherModifier || commandModifier { otherModifierGesture = true }
        chord = true
        return Result(swallow: swallow)
    }
    // `bound`: `pendingKeys` (none for the first key) followed by this key are exactly an
    // app shortcut. `prefix`: a longer app shortcut starts with those keys.
    mutating func route(key: UInt16, down: Bool, repeated: Bool, bound: Bool, prefix: Bool = false, windowKey: Bool = false, otherModifier: Bool = false, commandModifier: Bool = false, input: Input = .shortcuts, folderCount: Int = 0) -> Result {
        let shortcuts = input == .shortcuts, picker = input == .folderPicker
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
            let openSelection = held && picker && folderSelectionEntered
            let standalone = held && !chord && !otherModifierGesture
            var result = Result(swallow: true, tap: standalone, openFolderSelection: openSelection)
            // Releasing Caps runs the shortcut that was pressed.
            if shortcuts { addShortcutActions(to: &result) }
            clearSequence()
            held = false
            pressedKeys = []
            folderSelectionEntered = false
            return result
        }
        // Only a new key press makes a chord. A release of a key that was still
        // down when Caps was pressed (fast typing) keeps the standalone Caps.
        if down { beginChord() }
        let pressedBefore = pressedKeys
        if down && held && !repeated && pressedKeys.count < Self.maxShortcutKeys
            && key != KeyCode.escape && key != KeyCode.delete && !KeyCode.isReturn(key) { pressedKeys.append(key) }
        let stripCommand = held && picker && commandModifier && !otherModifier
        if !down { return Result(swallow: consumed.remove(key) != nil, stripCommandModifier: stripCommand) }
        if consumed.contains(key) { return Result(swallow: true) }
        // Own all new keyboard input destined for the original app during Caps,
        // including invalid shortcuts, repeats and modified/cancelled gestures.
        // Clutch's own focused editors and Folders still receive their input.
        // The shortcut branches below all require this, so they need not insert again.
        let takeOver = held && shortcuts
        if takeOver { consumed.insert(key) }
        // Caps + Space opens Folders, whenever Space comes during the hold: it takes over
        // from any shortcut or window preview started before it, so nothing else runs on
        // release. Its repeats and release stay consumed. When blocked (Control, Option or
        // Command, or after Escape), Space is consumed without an action.
        if shortcuts && held && key == KeyCode.space && !repeated
            && !otherModifierGesture && !otherModifier && !commandModifier && !folderGesture && !escaped {
            folderGesture = true
            sequenceValid = false
            return Result(swallow: true, showFolders: true)
        }
        // Invalid numbers must not confirm the previously selected folder.
        if held && picker && !otherModifier,
           let number = Self.numberKeys.firstIndex(of: key) {
            consumed.insert(key)
            guard !repeated else { return Result(swallow: true) }
            folderSelectionEntered = number < folderCount
            return Result(swallow: true, folderNumber: folderSelectionEntered ? number : nil)
        }
        // Only deliberate list navigation arms confirmation on Caps release.
        if held && picker && !otherModifier && Self.selectionKeys.contains(key) {
            folderSelectionEntered = folderCount > 0
        }
        // While Caps stays held, letters select an existing row rather than
        // reaching the search field or its input method. Own their releases too.
        if held && picker && !otherModifier && KeyCode.lettersAndDigits.contains(key) {
            consumed.insert(key)
            return Result(swallow: true, folderJump: repeated ? nil : key)
        }
        // Escape cancels the whole Caps gesture: nothing runs on release (a window
        // preview is dropped) and the key does not reach the app.
        if key == KeyCode.escape && held && shortcuts && !repeated {
            escaped = true
            sequenceValid = false
            return Result(swallow: true)
        }
        // Return while Caps is held confirms: it runs now what releasing Caps would run,
        // then the hold ends like after Escape (nothing more runs, nothing is shown).
        // Return is never part of a shortcut.
        if KeyCode.isReturn(key) && held && shortcuts && !repeated {
            var result = Result(swallow: true)
            if !escaped { addShortcutActions(to: &result) }
            escaped = true
            sequenceValid = false
            return result
        }
        let actionAllowed = shortcuts && held && !repeated && !escaped
            && !otherModifierGesture && !otherModifier && !folderGesture && !commandModifier
        guard actionAllowed else { return Result(swallow: takeOver, stripCommandModifier: stripCommand) }
        // Delete takes back the last app key, valid or not; with none it does nothing.
        // In a window gesture it is an ordinary key (it cancels the preview).
        if key == KeyCode.delete && !sequenceWindow {
            if let step = steps.popLast() {
                sequence = step.sequence; sequenceWindow = step.window
                sequenceBound = step.bound; sequenceValid = step.valid
                pressedKeys = step.pressedKeys
            }
            return Result(swallow: true)
        }
        // An app shortcut takes at most three keys: once three are in, later keys are
        // ignored (consumed, without changing what releasing Caps runs).
        if !sequenceWindow && pressedBefore.count >= Self.maxShortcutKeys {
            return Result(swallow: true)
        }
        steps.append(Step(sequence: sequence, window: sequenceWindow, bound: sequenceBound,
                          valid: sequenceValid, pressedKeys: pressedBefore))
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
        // The keys must match a shortcut exactly. Each further key must complete or
        // continue a shortcut, including the same key again (Caps + M + M). Any other
        // key, or a repeated key no shortcut uses, means no shortcut runs. Keys after
        // the third were already ignored above.
        // Window keys keep updating the preview (← again: 2/3, ↑ again: full, …);
        // any other key, Escape included, cancels it.
        if sequenceWindow {
            guard windowKey && sequenceValid else { sequenceValid = false; return Result(swallow: true) }
            return Result(swallow: true, windowPreview: key)
        }
        if pendingKeys != nil && (bound || prefix) {
            sequence.append(key)
            sequenceBound = bound
        } else {
            sequenceValid = false
        }
        return Result(swallow: true)
    }
    // A recording field saved on Caps + Return: the rest of this hold runs nothing.
    mutating func endHold() {
        guard held else { return }
        escaped = true
        sequenceValid = false
    }
    // What ending this hold (Caps release, or Return) runs: the window action or the
    // app shortcut pressed, if any.
    private func addShortcutActions(to result: inout Result) {
        guard held && sequenceValid && !sequence.isEmpty && !otherModifierGesture && !folderGesture else { return }
        if sequenceWindow {
            result.window = sequence[0]
        } else if sequenceBound {
            result.launchKeys = sequence
        }
    }
    private mutating func clearSequence() {
        sequence = []; sequenceWindow = false; sequenceBound = false; sequenceValid = false; steps = []
    }
    // Focus changes cancel chord actions, but preserve standalone Caps and
    // ownership of swallowed shortcut releases.
    mutating func cancelGesture() {
        let standalone = held && !chord && !otherModifierGesture
        capsReleaseMissed()
        held = standalone
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
