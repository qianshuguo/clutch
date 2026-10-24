import Foundation
import CoreGraphics
func expect(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
var state = KeyboardState()
func capsDown() { _ = state.route(key: 79, down: true, repeated: false, bound: false) }
func releaseCaps() -> KeyboardState.Result { state.route(key: 79, down: false, repeated: false, bound: false) }
expect(!state.route(key: 3, down: true, repeated: false, bound: true).swallow, "normal typing passes")
expect(!releaseCaps().tap, "orphan release is ignored")
capsDown()
expect(releaseCaps().tap, "standalone release requests system Caps replay")
capsDown()
_ = state.route(key: 79, down: true, repeated: true, bound: false)
expect(releaseCaps().tap && !releaseCaps().tap, "holding/repeating Caps requests system replay only once on release")
capsDown()
let launch = state.route(key: 3, down: true, repeated: false, bound: true)
expect(launch.swallow && launch.launchKeys == nil, "bound chord is consumed and waits for Caps release")
expect(state.route(key: 3, down: true, repeated: true, bound: true).launchKeys == nil, "no repeated launches")
let launchRelease = releaseCaps()
expect(!launchRelease.tap && launchRelease.launchKeys == [3], "Caps release runs the shortcut and never switches input")
expect(state.route(key: 3, down: false, repeated: false, bound: true).swallow, "consume keyup after Caps released first")
expect(!state.route(key: 3, down: true, repeated: false, bound: true).swallow, "typing returns to normal")
state.reset()
capsDown()
_ = state.route(key: 3, down: true, repeated: false, bound: true)
expect(state.route(key: 3, down: false, repeated: false, bound: true).swallow, "consume keyup when letter released first")
expect(!releaseCaps().tap, "letter release does not turn chord into tap")
capsDown()
expect(state.route(key: 11, down: true, repeated: false, bound: false).swallow, "unbound Caps key is consumed")
expect(!releaseCaps().tap, "unbound chord does not switch input")
capsDown()
state.beginChord()
expect(!releaseCaps().tap, "modifier after Caps cancels standalone action")
capsDown()
state.reset()
expect(!releaseCaps().tap, "pause cancels pending standalone action")
print("PASS: standalone Caps, repeats, bound/unbound chords, both release orders, modifier cancellation, pause")

// Caps held alone stays a standalone press however long (macOS times it, mirrored);
// anything joining makes it a chord.
// The times only document the scenario; the state machine does not time holds.
func capsDown(at _: TimeInterval) { capsDown() }
func releaseCaps(at _: TimeInterval) -> KeyboardState.Result { releaseCaps() }
let longHold: TimeInterval = 1
state.reset()
capsDown(at: 100)
let shortPress = releaseCaps(at: 100 + longHold - 0.01)
expect(shortPress.tap, "a short press is a standalone Caps press")
capsDown(at: 200)
_ = state.route(key: 79, down: true, repeated: true, bound: false)
let longPress = releaseCaps(at: 200 + longHold)
expect(longPress.tap, "a long press alone is still a standalone Caps press")
capsDown(at: 300)
_ = state.route(key: 3, down: true, repeated: false, bound: true)
let longChord = releaseCaps(at: 300 + longHold * 4)
expect(!longChord.tap && longChord.launchKeys == [3], "a long Caps + key hold runs the shortcut, not a Caps press")
_ = state.route(key: 3, down: false, repeated: false, bound: true)
capsDown(at: 400)
_ = state.modifierChanged(otherModifier: true)
expect(!releaseCaps(at: 400 + longHold * 2).tap, "Caps + modifier held long is not a Caps press")
capsDown(at: 500)
state.cancelGesture()
expect(state.held, "a focus change keeps the standalone hold")
expect(releaseCaps(at: 500 + longHold).tap, "a hold across a focus change stays a Caps press")
capsDown(at: 600)
state.capsReleaseMissed()
expect(!releaseCaps(at: 600 + longHold).tap, "a missed release never becomes a Caps press later")
// Key hint: every key pressed during the hold, in order.
capsDown(at: 700)
_ = state.route(key: 46, down: true, repeated: false, bound: false, prefix: true)
_ = state.route(key: 13, down: true, repeated: false, bound: true)
_ = state.route(key: 13, down: true, repeated: true, bound: false)
expect(state.pressedKeys == [46, 13] && state.showsKeyHint, "the key hint lists M then W, without repeats")
_ = state.route(key: 3, down: true, repeated: false, bound: true)
expect(state.pressedKeys == [46, 13, 3], "the key hint lists up to three keys")
_ = state.route(key: 7, down: true, repeated: false, bound: false)
expect(state.pressedKeys == [46, 13, 3], "the key hint keeps only the first three keys")
_ = releaseCaps(at: 701)
expect(state.pressedKeys.isEmpty && !state.showsKeyHint, "releasing Caps clears the key hint")
state.reset()
capsDown(at: 800)
_ = state.route(key: KeyCode.space, down: true, repeated: false, bound: false)
expect(!state.showsKeyHint, "Caps + Space (Folders) shows no key hint")
state.reset()
// Escape while Caps is held ends the gesture: nothing runs, nothing more is shown.
capsDown(at: 900)
_ = state.route(key: 3, down: true, repeated: false, bound: true)
let escaped = state.route(key: 53, down: true, repeated: false, bound: false)
expect(escaped.swallow && !state.showsKeyHint && state.launchCandidate == nil, "Escape is consumed and hides the key hint")
expect(state.route(key: 46, down: true, repeated: false, bound: true).swallow, "keys after Escape stay consumed until Caps release")
let afterEscape = releaseCaps(at: 900 + longHold)
expect(afterEscape.launchKeys == nil && !afterEscape.tap, "releasing Caps after Escape does nothing")
expect(state.route(key: 53, down: false, repeated: false, bound: false).swallow, "the Escape release is consumed")
_ = state.route(key: 3, down: false, repeated: false, bound: true)
_ = state.route(key: 46, down: false, repeated: false, bound: true)
state.reset()
print("PASS: standalone Caps holds, Escape, key hint")

state.reset()
capsDown()
expect(!state.route(key: 0, down: false, repeated: false, bound: true).swallow, "earlier key release passes through")
expect(releaseCaps().tap, "releasing a key pressed before Caps keeps standalone Caps")
capsDown()
_ = state.modifierChanged(otherModifier: false, pressed: false)
expect(releaseCaps().tap, "releasing a modifier pressed before Caps keeps standalone Caps")
capsDown()
_ = state.modifierChanged(otherModifier: false)
expect(!releaseCaps().tap, "pressing a modifier while holding Caps still cancels standalone Caps")
capsDown()
_ = state.route(key: 0, down: false, repeated: false, bound: false)
_ = state.route(key: 11, down: true, repeated: false, bound: false)
expect(!releaseCaps().tap, "a new key press after an earlier release still makes a chord")
let modifierFlags: [(UInt16, UInt64)] = [(56, 0x20000), (60, 0x20000), (59, 0x40000), (62, 0x40000),
                                         (58, 0x80000), (61, 0x80000), (55, 0x100000), (54, 0x100000), (63, 0x800000)]
for (key, mask) in modifierFlags {
    expect(KeyboardState.modifierPressed(key: key, flags: mask), "modifier flag set means press")
    expect(!KeyboardState.modifierPressed(key: key, flags: 0), "modifier flag clear means release")
}
expect(KeyboardState.modifierPressed(key: 200, flags: 0), "unknown modifier keys stay cautious")
expect(KeyboardState.isModifierKey(56) && KeyboardState.isModifierKey(55) && !KeyboardState.isModifierKey(57) && !KeyboardState.isModifierKey(0),
       "a Caps Lock flags change is not a modifier press")
state.reset()
print("PASS: earlier key/modifier releases keep standalone Caps; new presses still cancel")
// Default app keys plus custom letter and number mappings (Return is reserved).
for key: UInt16 in [1, 3, 17, 8, 9, 0, 18] {
    state.reset()
    capsDown()
    for _ in 0..<4 {
        expect(state.route(key: key, down: true, repeated: false, bound: true).launchKeys == nil, "a mapped press waits for Caps release")
        expect(state.route(key: key, down: true, repeated: true, bound: true).launchKeys == nil, "holding a mapped key does nothing more")
        expect(state.route(key: key, down: false, repeated: false, bound: true).swallow, "each mapped release is consumed")
    }
    let repeatedTaps = releaseCaps()
    expect(repeatedTaps.launchKeys != [key] && !repeatedTaps.tap, "tapping a key several times in one Caps hold matches no one-key shortcut")
    for _ in 0..<3 {
        capsDown()
        _ = state.route(key: key, down: true, repeated: false, bound: true)
        _ = state.route(key: key, down: false, repeated: false, bound: true)
        let again = releaseCaps()
        expect(again.launchKeys == [key] && !again.tap, "each Caps + key requests activation/window cycling")
    }
}
state.reset()
print("PASS: repeated app shortcuts across default and custom mappings")
// Two-key shortcuts: Caps + M + W (M = 46, W = 13). Caps release decides, so M may
// also open an app by itself. `bound`: the keys so far plus this one are a shortcut;
// `prefix`: a longer shortcut starts with them.
func comboRoute(_ key: UInt16, down: Bool = true, repeated: Bool = false, bound: Bool = false,
                prefix: Bool = false) -> KeyboardState.Result {
    state.route(key: key, down: down, repeated: repeated, bound: bound, prefix: prefix)
}
for mWasReleasedFirst in [false, true] {
    state.reset()
    capsDown()
    let first = comboRoute(46, bound: true, prefix: true)
    expect(first.swallow && first.launchKeys == nil && state.pendingKeys == [46], "the first key waits for Caps release or a second key")
    expect(comboRoute(46, repeated: true, bound: true, prefix: true).swallow, "first key repeats are consumed")
    if mWasReleasedFirst {
        expect(comboRoute(46, down: false).swallow && state.pendingKeys == [46], "releasing the first key keeps waiting while Caps is held")
    }
    let second = comboRoute(13, bound: true)
    expect(second.swallow && second.launchKeys == nil && state.pendingKeys == [46, 13], "the second key is consumed and could still start a longer shortcut")
    expect(comboRoute(13, repeated: true, bound: true).swallow, "second key repeats are consumed")
    if !mWasReleasedFirst { expect(comboRoute(46, down: false).swallow, "the first key release is consumed") }
    expect(comboRoute(13, down: false).swallow, "the second key release is consumed")
    let capsUp = releaseCaps()
    expect(capsUp.launchKeys == [46, 13] && !capsUp.tap, "Caps release runs Caps + M + W, not Caps + M")
}
// The on-screen hint follows what releasing Caps would run.
state.reset()
capsDown()
expect(state.launchCandidate == nil, "Caps alone shows no app")
_ = comboRoute(46, prefix: true)
expect(state.launchCandidate == nil, "a key that only starts two-key shortcuts shows no app yet")
_ = comboRoute(13, bound: true)
expect(state.launchCandidate == [46, 13], "Caps + M + W shows its app")
_ = releaseCaps()
expect(state.launchCandidate == nil, "releasing Caps hides the hint")
_ = comboRoute(46, down: false); _ = comboRoute(13, down: false)
capsDown()
_ = comboRoute(46, bound: true, prefix: true)
expect(state.launchCandidate == [46], "Caps + M shows its own app")
_ = comboRoute(11)
expect(state.launchCandidate == nil, "an unmatched key hides the hint")
_ = releaseCaps(); _ = comboRoute(46, down: false); _ = comboRoute(11, down: false)
capsDown()
_ = comboRoute(46, bound: true, prefix: true)
_ = state.modifierChanged(otherModifier: true)
expect(state.launchCandidate == nil, "a modifier during the hold hides the hint")
_ = releaseCaps(); _ = comboRoute(46, down: false)
print("PASS: launch hint follows the pending shortcut")
state.reset()
capsDown()
_ = comboRoute(46, bound: true, prefix: true)
let alone = releaseCaps()
expect(alone.launchKeys == [46] && !alone.tap, "Caps + M alone still opens its own app")
_ = comboRoute(46, down: false)
capsDown()
_ = comboRoute(46, prefix: true)
expect(releaseCaps().launchKeys == nil, "a key that only starts two-key shortcuts runs nothing alone")
_ = comboRoute(46, down: false)
capsDown()
_ = comboRoute(46, bound: true, prefix: true)
_ = comboRoute(46, down: false)
_ = comboRoute(46, bound: true)
let doubled = releaseCaps()
expect(doubled.launchKeys == [46, 46], "Caps + M + M uses the same key twice")
_ = comboRoute(46, down: false)
capsDown()
_ = comboRoute(46, bound: true, prefix: true)
_ = comboRoute(46, down: false)
_ = comboRoute(46)
_ = comboRoute(46, down: false)
let tappedTwice = releaseCaps()
expect(tappedTwice.launchKeys == nil, "without Caps + M + M, tapping M twice runs nothing")
// Caps + C C C C L is not Caps + C + L: the keys must match exactly.
capsDown()
_ = comboRoute(8, bound: true, prefix: true)
_ = comboRoute(8, down: false)
for _ in 0..<3 {
    _ = comboRoute(8)
    _ = comboRoute(8, down: false)
}
_ = comboRoute(37, bound: true)
_ = comboRoute(37, down: false)
let extraPresses = releaseCaps()
expect(extraPresses.launchKeys == nil, "extra presses before the second key run nothing")
capsDown()
_ = comboRoute(46, bound: true, prefix: true)
let unmatched = comboRoute(11)
expect(unmatched.swallow && unmatched.launchKeys == nil, "a key that completes no shortcut is consumed")
expect(releaseCaps().launchKeys == nil, "an unmatched second key means nothing runs")
_ = comboRoute(46, down: false); _ = comboRoute(11, down: false)
capsDown()
_ = comboRoute(46, prefix: true)
_ = comboRoute(13, bound: true)
_ = comboRoute(7)
expect(releaseCaps().launchKeys == nil, "a third key that completes no shortcut means nothing runs")
_ = comboRoute(46, down: false); _ = comboRoute(13, down: false); _ = comboRoute(7, down: false)
capsDown()
expect(comboRoute(11).swallow && state.pendingKeys == nil, "keys no shortcut uses are consumed")
_ = comboRoute(11, down: false)
_ = releaseCaps()
capsDown()
_ = comboRoute(46, bound: true, prefix: true)
_ = state.modifierChanged(otherModifier: true)
expect(releaseCaps().launchKeys == nil, "a modifier during the hold cancels the shortcut")
state.reset()
capsDown()
_ = comboRoute(46, bound: true, prefix: true)
state.cancelGesture()
expect(state.pendingKeys == nil && releaseCaps().launchKeys == nil, "focus changes cancel the shortcut")
state.reset()
capsDown()
_ = comboRoute(46, bound: true, prefix: true)
state.capsReleaseMissed()
expect(state.pendingKeys == nil && !state.held && releaseCaps().launchKeys == nil, "a hidden Caps release runs nothing")
state.reset()
expect(!comboRoute(46, bound: true, prefix: true).swallow && state.pendingKeys == nil, "without Caps the key types normally")
capsDown()
_ = state.route(key: 123, down: true, repeated: false, bound: true, prefix: true, windowKey: true)
expect(state.pendingKeys == nil, "a window key never starts a two-key shortcut")
let windowFirst = releaseCaps()
expect(windowFirst.window == 123 && windowFirst.launchKeys == nil, "window keys keep precedence over app shortcuts")
state.reset()
print("PASS: two-key shortcuts on Caps release, the same key twice, one-key and two-key shortcuts on one key, cancellation, precedence")
// Three-key shortcuts: Caps + M + W + E (E = 14).
state.reset()
capsDown()
_ = comboRoute(46, prefix: true)
_ = comboRoute(13, prefix: true)
expect(state.pendingKeys == [46, 13] && state.launchCandidate == nil, "M W that only starts M W E waits for a third key")
_ = comboRoute(14, bound: true)
expect(state.pendingKeys == nil && state.launchCandidate == [46, 13, 14], "Caps + M + W + E shows its app")
let threeKeys = releaseCaps()
expect(threeKeys.launchKeys == [46, 13, 14] && !threeKeys.tap, "Caps release runs Caps + M + W + E")
state.reset()
capsDown()
_ = comboRoute(46, prefix: true)
_ = comboRoute(13, bound: true, prefix: true)
expect(state.launchCandidate == [46, 13], "M W can open its own app and also start M W E")
expect(releaseCaps().launchKeys == [46, 13], "releasing Caps after M W runs Caps + M + W")
state.reset()
capsDown()
_ = comboRoute(46, prefix: true)
_ = comboRoute(13, prefix: true)
expect(releaseCaps().launchKeys == nil, "keys that only start a longer shortcut run nothing")
state.reset()
capsDown()
_ = comboRoute(46, prefix: true)
_ = comboRoute(13, prefix: true)
_ = comboRoute(14, bound: true)
expect(comboRoute(7, bound: true).swallow, "a fourth key is consumed")
expect(comboRoute(8, bound: true, prefix: true).swallow, "a fifth key is consumed")
expect(state.launchCandidate == [46, 13, 14] && state.pressedKeys == [46, 13, 14],
       "keys after the third are ignored")
expect(releaseCaps().launchKeys == [46, 13, 14], "releasing Caps still runs the three-key shortcut")
state.reset()
capsDown()
_ = comboRoute(46, prefix: true)
_ = comboRoute(13, prefix: true)
_ = comboRoute(11)
_ = comboRoute(14, bound: true)
expect(releaseCaps().launchKeys == nil, "an unmatched key among the first three still means nothing runs")
state.reset()
capsDown()
_ = comboRoute(46, prefix: true)
_ = comboRoute(13, prefix: true)
_ = comboRoute(14, bound: true)
_ = comboRoute(7, bound: true)
_ = comboRoute(KeyCode.delete)
expect(state.launchCandidate == [46, 13], "Delete after an ignored fourth key takes back the third")
state.reset()
// Return while Caps is held confirms: it runs the shortcut now and ends the hold.
capsDown()
_ = comboRoute(46, prefix: true)
_ = comboRoute(13, bound: true)
let confirmed = comboRoute(KeyCode.returnKey, bound: true)
expect(confirmed.swallow && confirmed.launchKeys == [46, 13], "Caps + M + W + Return runs Caps + M + W at once")
expect(!state.showsKeyHint && state.launchCandidate == nil, "Return hides the key hint")
expect(comboRoute(14, bound: true).launchKeys == nil, "keys after Return do nothing")
let afterReturn = releaseCaps()
expect(afterReturn.launchKeys == nil && !afterReturn.tap, "releasing Caps after Return runs nothing more")
expect(comboRoute(KeyCode.returnKey, down: false).swallow, "the Return release is consumed")
state.reset()
capsDown()
_ = comboRoute(46, prefix: true)
_ = comboRoute(KeyCode.returnKey)
expect(state.pressedKeys == [46], "Return never counts as a shortcut key")
expect(releaseCaps().launchKeys == nil, "Return after keys that only start a shortcut runs nothing")
state.reset()
capsDown()
let enterConfirmed = state.route(key: KeyCode.keypadEnter, down: true, repeated: false, bound: false)
expect(enterConfirmed.swallow && enterConfirmed.launchKeys == nil && !releaseCaps().tap,
       "Caps + Enter alone runs nothing and is not a Caps press")
state.reset()
capsDown()
_ = state.route(key: 123, down: true, repeated: false, bound: false, windowKey: true)
expect(comboRoute(KeyCode.returnKey).window == 123, "Return applies the window preview at once")
expect(releaseCaps().window == nil, "releasing Caps after Return applies nothing more")
state.reset()
capsDown()
_ = comboRoute(46, prefix: true)
_ = comboRoute(13, prefix: true)
_ = comboRoute(11)
expect(releaseCaps().launchKeys == nil, "a third key that continues no shortcut means nothing runs")
state.reset()
print("PASS: three-key shortcuts")
// Delete while Caps is held takes back the last key.
state.reset()
capsDown()
_ = comboRoute(46, bound: true, prefix: true)
_ = comboRoute(13, bound: true)
expect(comboRoute(KeyCode.delete).swallow, "Delete is consumed")
expect(state.launchCandidate == [46] && state.pressedKeys == [46], "Caps + M + W, Delete is Caps + M again")
expect(releaseCaps().launchKeys == [46], "releasing Caps then runs Caps + M")
state.reset()
capsDown()
_ = comboRoute(46, bound: true, prefix: true)
_ = comboRoute(11)
expect(state.launchCandidate == nil, "an unmatched key leaves nothing to run")
_ = comboRoute(KeyCode.delete)
expect(state.launchCandidate == [46], "Delete takes back the unmatched key too")
_ = comboRoute(13, bound: true)
expect(releaseCaps().launchKeys == [46, 13], "after Delete the shortcut can be finished")
state.reset()
capsDown()
_ = comboRoute(KeyCode.delete)
_ = comboRoute(46, bound: true, prefix: true)
expect(state.launchCandidate == [46], "Delete with no keys yet does nothing")
_ = comboRoute(KeyCode.delete)
expect(state.launchCandidate == nil && !state.showsKeyHint, "deleting every key leaves nothing")
let afterDeletingAll = releaseCaps()
expect(afterDeletingAll.launchKeys == nil && !afterDeletingAll.tap, "then Caps release runs nothing and is not a Caps press")
state.reset()
capsDown()
_ = state.route(key: 123, down: true, repeated: false, bound: false, windowKey: true)
_ = comboRoute(KeyCode.delete)
expect(!state.windowPreviewActive && releaseCaps().window == nil, "in a window gesture Delete cancels the preview")
state.reset()
print("PASS: Delete takes back keys while Caps is held")
// An unbound prefix must never be discarded (Caps A C is not Caps C).
for releaseFirst in [false, true] {
    state.reset()
    capsDown()
    expect(comboRoute(0).swallow, "unbound A press is owned")
    expect(comboRoute(0, repeated: true).swallow, "unbound A repeats are owned")
    if releaseFirst { expect(comboRoute(0, down: false).swallow, "unbound A release is owned") }
    expect(comboRoute(8, bound: true).swallow, "C after unbound A is owned")
    expect(state.launchCandidate == nil && state.pendingKeys == nil, "A C cannot hint Chrome")
    let invalid = releaseCaps()
    expect(invalid.launchKeys == nil && !invalid.tap, "A C cannot launch Chrome or switch input")
    if !releaseFirst { expect(comboRoute(0, down: false).swallow, "A release after Caps stays owned") }
    expect(comboRoute(8, down: false).swallow, "C release after Caps stays owned")
    capsDown()
    _ = comboRoute(8, bound: true)
    expect(releaseCaps().launchKeys == [8], "a fresh exact Caps C still launches Chrome")
}
for (key, _) in modifierFlags {
    for releaseFirst in [false, true] {
        state.reset()
        capsDown()
        expect(state.modifierChanged(key: key, otherModifier: true).swallow, "modifier press during Caps is owned")
        if releaseFirst {
            expect(state.modifierChanged(key: key, otherModifier: false, pressed: false).swallow, "modifier release before Caps is owned")
        }
        expect(comboRoute(0).swallow, "modified input during Caps stays owned")
        expect(releaseCaps().launchKeys == nil, "modified gesture launches nothing")
        if !releaseFirst {
            expect(state.modifierChanged(key: key, otherModifier: false, pressed: false).swallow, "modifier release after Caps stays owned")
        }
        expect(!state.modifierChanged(key: key, otherModifier: true).swallow, "fresh modifier after Caps passes")
    }
}
state.reset()
print("PASS: full Caps input ownership, strict unbound-prefix matching, modifier release ownership")
let src = MappingPolicy.src, dst = MappingPolicy.dst
let other: [String: UInt64] = [src: 0x700000004, dst: 0x700000005]
let oldCaps: [String: UInt64] = [src: MappingPolicy.caps, dst: 0x7000000E0]
let legacy: [String: UInt64] = [src: MappingPolicy.caps, dst: MappingPolicy.f18]
expect(MappingPolicy.restore([other, legacy], previous: [oldCaps]) == [other, oldCaps], "upgrade restores previous Caps mapping")
expect(MappingPolicy.restore([other, oldCaps], previous: []) == [other, oldCaps], "upgrade preserves external mappings")
let parsed = try MappingCodec.decode("( { HIDKeyboardModifierMappingSrc = 30064771129; HIDKeyboardModifierMappingDst = 30064771181; } )".data(using: .utf8)!)
expect(parsed == [legacy], "legacy hidutil output decodes")
expect(try MappingCodec.decode("(null)".data(using: .utf8)!).isEmpty, "empty mapping decodes")
print("PASS: one-time legacy mapping recovery")

for modifier in ["Control", "Option"] {
    state.reset()
    _ = state.route(key: 79, down: true, repeated: false, bound: false, otherModifier: true)
    let modifierFirst = releaseCaps()
    expect(!modifierFirst.tap && !modifierFirst.showFolders, "\(modifier) then Caps has no action")
    capsDown()
    state.modifierChanged(otherModifier: true)
    state.modifierChanged(otherModifier: false)
    let capsFirst = releaseCaps()
    expect(!capsFirst.tap && !capsFirst.showFolders, "Caps then \(modifier), released first, has no action")
    _ = state.route(key: 79, down: true, repeated: false, bound: false, otherModifier: true)
    let extra = state.route(key: 3, down: true, repeated: false, bound: true, otherModifier: true)
    expect(extra.swallow && extra.launchKeys == nil, "\(modifier) Caps with extra key is consumed")
    expect(!releaseCaps().tap, "extra key does not switch input")
}
print("PASS: Control/Option Caps have no action, both press/release orders, extra keys consumed")

state.reset()
expect(!state.route(key: 49, down: true, repeated: false, bound: false).swallow, "Space without Caps types normally")
for capsReleasedFirst in [false, true] {
    state.reset()
    capsDown()
    let opening = state.route(key: 49, down: true, repeated: false, bound: true)
    expect(opening.swallow && opening.showFolders && opening.launchKeys == nil, "Caps Space opens Folders")
    let spaceRepeat = state.route(key: 49, down: true, repeated: true, bound: false, input: .folderPicker, folderCount: 9)
    expect(spaceRepeat.swallow && !spaceRepeat.showFolders, "Space repeats are consumed and never reopen")
    expect(!state.route(key: 79, down: true, repeated: true, bound: false).showFolders, "Caps repeats never reopen")
    if !capsReleasedFirst {
        expect(state.route(key: 49, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 9).swallow, "Space release is consumed")
    }
    let release = state.route(key: 79, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 9)
    expect(!release.tap && !release.openFolderSelection && !release.showFolders, "release without navigation leaves panel open")
    if capsReleasedFirst {
        expect(state.route(key: 49, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 9).swallow, "Space release after Caps is consumed")
    }
}
state.reset()
capsDown()
let heldSpace = state.route(key: 49, down: true, repeated: true, bound: false)
expect(!heldSpace.showFolders && heldSpace.swallow, "Space already held before Caps does not open Folders")
state.reset()
capsDown()
expect(!state.modifierChanged(otherModifier: false, commandModifier: true).showFolders, "Caps Command no longer opens Folders")
expect(!releaseCaps().tap, "Caps Command is still a chord")
state.reset()
expect(!state.route(key: 79, down: true, repeated: false, bound: false, commandModifier: true).showFolders, "Command Caps no longer opens Folders")
expect(!state.route(key: 49, down: true, repeated: false, bound: false, commandModifier: true).showFolders, "Command blocks Caps Space")
state.reset()
for key in [UInt16(36), 76] {
    state.reset()
    capsDown()
    let enter = state.route(key: key, down: true, repeated: false, bound: false)
    expect(!enter.showFolders && enter.swallow, "unassigned Caps Enter is consumed")
    expect(!releaseCaps().tap, "Caps Enter does not switch input")
    state.reset()
    capsDown()
    _ = state.route(key: 46, down: true, repeated: false, bound: true)
    expect(state.route(key: key, down: true, repeated: false, bound: true).launchKeys == [46],
           "Caps + M + Enter runs Caps + M at once; Enter is never a shortcut key")
    expect(releaseCaps().launchKeys == nil, "releasing Caps after Enter runs nothing more")
}
for key in [UInt16(18), 0, 125, 126, 123, 124] {
    state.reset()
    capsDown()
    _ = state.route(key: 49, down: true, repeated: false, bound: false)
    _ = state.route(key: 49, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 9)
    _ = state.route(key: key, down: true, repeated: false, bound: true, input: .folderPicker, folderCount: 9)
    _ = state.route(key: key, down: false, repeated: false, bound: true, input: .folderPicker, folderCount: 9)
    let release = state.route(key: 79, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 9)
    expect(release.openFolderSelection && !release.tap, "number, letter, or arrow input arms opening on Caps release")
    capsDown()
    expect(!state.route(key: 79, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 9).openFolderSelection, "selection intent does not carry into another Caps hold")
}
for key in [UInt16(0), 125] {
    state.reset()
    capsDown()
    _ = state.route(key: key, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 9)
    state.modifierChanged(otherModifier: false, commandModifier: true)
    expect(!state.route(key: 79, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 9).openFolderSelection, "key releases and modifiers do not count as selection input")
}
state.reset()
capsDown()
_ = state.route(key: 125, down: true, repeated: false, bound: false, otherModifier: true, input: .folderPicker, folderCount: 9)
expect(!state.route(key: 79, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 9).openFolderSelection, "Control/Option navigation does not arm selection")
state.reset()
print("PASS: idle folder panel stays open, navigation arms Caps release, intent resets between holds")
state.reset()
capsDown()
_ = state.route(key: 11, down: true, repeated: false, bound: false)
let lateSpace = state.route(key: 49, down: true, repeated: false, bound: false)
expect(lateSpace.showFolders && lateSpace.swallow, "Space after another key still opens Folders")
expect(!releaseCaps().tap, "the gesture cannot switch input")
_ = state.route(key: 11, down: false, repeated: false, bound: false)
_ = state.route(key: 49, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 9)
state.reset()
capsDown()
_ = state.route(key: 3, down: true, repeated: false, bound: true)
expect(state.route(key: 49, down: true, repeated: false, bound: false).showFolders, "Space after an app key opens Folders")
expect(state.launchCandidate == nil && releaseCaps().launchKeys == nil, "the app shortcut before Space does not run")
state.reset()
capsDown()
_ = state.route(key: 123, down: true, repeated: false, bound: false, windowKey: true)
expect(state.route(key: 49, down: true, repeated: false, bound: false).showFolders && !state.windowPreviewActive,
       "Space after a window key opens Folders and drops the preview")
expect(releaseCaps().window == nil, "the window action before Space is not applied")
for modifierFirst in [false, true] {
    state.reset()
    _ = state.route(key: 79, down: true, repeated: false, bound: false, otherModifier: modifierFirst)
    if !modifierFirst { state.modifierChanged(otherModifier: true) }
    let blocked = state.route(key: 49, down: true, repeated: false, bound: false, otherModifier: true)
    expect(!blocked.showFolders && blocked.swallow, "Control/Option blocks Caps Space and consumes it")
    _ = state.route(key: 49, down: false, repeated: false, bound: false, otherModifier: true)
    expect(!state.route(key: 49, down: true, repeated: false, bound: false).showFolders, "cancelled modifier gesture stays cancelled")
    expect(!releaseCaps().tap, "modified gesture never switches input")
}
state.reset()
capsDown()
state.reset()
expect(!state.route(key: 49, down: true, repeated: false, bound: false).showFolders, "pause clears pending Caps Space")
expect(!releaseCaps().tap, "pause clears release action")
state.reset()
_ = state.route(key: 79, down: true, repeated: false, bound: false, input: .folderPicker, folderCount: 9)
let panelSpace = state.route(key: 49, down: true, repeated: false, bound: false, input: .folderPicker, folderCount: 9)
expect(!panelSpace.showFolders && !panelSpace.swallow, "existing selection panel never reopens; Space reaches the list")
print("PASS: Caps Space, both release orders, repeats, cancellation, Enter consumption, Command no longer opens")
state.reset()
capsDown()
expect(state.route(key: 49, down: true, repeated: false, bound: false).showFolders, "open panel while Caps held")
let arrow = state.route(key: 125, down: true, repeated: false, bound: true, input: .folderPicker, folderCount: 9)
expect(!arrow.swallow && arrow.launchKeys == nil, "held Caps lets panel selection keys through even if bound")
let folderRelease = state.route(key: 79, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 9)
expect(folderRelease.openFolderSelection && !folderRelease.tap && !folderRelease.showFolders, "Caps release confirms folder selection after navigation")
expect(!state.route(key: 79, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 9).openFolderSelection, "orphan release cannot confirm again")
capsDown()
let panelTap = state.route(key: 79, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 9)
expect(!panelTap.openFolderSelection && panelTap.tap, "standalone Caps in the list replays without opening a folder")
capsDown()
let closedPanelRelease = releaseCaps()
expect(!closedPanelRelease.openFolderSelection && closedPanelRelease.tap, "outside panel Caps retains input switching")
// Caps-held letters go directly to selection; their events never enter search.
for releaseLetterFirst in [false, true] {
    state.reset()
    capsDown()
    _ = state.route(key: KeyCode.space, down: true, repeated: false, bound: false)
    let jump = state.route(key: 2, down: true, repeated: false, bound: true, input: .folderPicker, folderCount: 4)
    expect(jump.swallow && jump.folderJump == 2 && jump.launchKeys == nil, "Caps D jumps in the picker without typing D")
    let repeating = state.route(key: 2, down: true, repeated: true, bound: false, input: .folderPicker, folderCount: 4)
    expect(repeating.swallow && repeating.folderJump == nil, "held letter repeats do not edit search or jump again")
    if releaseLetterFirst {
        expect(state.route(key: 2, down: false, repeated: false, bound: false, input: .folderPicker).swallow, "letter release before Caps is consumed")
    }
    let release = state.route(key: KeyCode.hyper, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 4)
    expect(release.openFolderSelection && !release.tap, "Caps release opens the jumped-to folder")
    if !releaseLetterFirst {
        expect(state.route(key: 2, down: false, repeated: false, bound: false, input: .folderPicker).swallow, "letter release after Caps is consumed")
    }
    let typing = state.route(key: 2, down: true, repeated: false, bound: false, input: .folderPicker)
    expect(!typing.swallow && typing.folderJump == nil, "after Caps release ordinary typing reaches search")
}
state.reset()
print("PASS: Caps release opens folder selection, navigation passthrough, no input switch, no duplicate confirmation")

for (number, key) in [UInt16(18), 19, 20, 21, 23, 22, 26, 28, 25].enumerated() {
    state.reset()
    capsDown()
    let shortcut = state.route(key: key, down: true, repeated: false, bound: true, input: .folderPicker, folderCount: 9)
    expect(shortcut.swallow && shortcut.folderNumber == number && shortcut.launchKeys == nil && !shortcut.openFolderSelection, "Caps number selects folder instead of launching a bound app")
    let repeated = state.route(key: key, down: true, repeated: true, bound: true, input: .folderPicker, folderCount: 9)
    expect(repeated.swallow && repeated.folderNumber == nil, "folder shortcut repeats are consumed")
    let release = state.route(key: 79, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 9)
    expect(release.openFolderSelection && !release.tap, "Caps release opens the numbered selection")
    expect(!state.route(key: 79, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 9).openFolderSelection, "numbered selection opens only once on Caps release")
    expect(state.route(key: key, down: false, repeated: false, bound: true).swallow, "folder shortcut release is consumed even after panel closes")
}
state.reset()
capsDown()
for key in [UInt16(18), 25, 20] {
    let move = state.route(key: key, down: true, repeated: false, bound: true, input: .folderPicker, folderCount: 9)
    expect(move.folderNumber != nil && !move.openFolderSelection, "multiple numbers can change selection during one Caps hold")
    let keyUp = state.route(key: key, down: false, repeated: false, bound: true, input: .folderPicker, folderCount: 9)
    expect(keyUp.swallow && !keyUp.openFolderSelection, "releasing a number does not open the folder")
}
expect(state.route(key: 79, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 9).openFolderSelection, "only Caps release confirms the final selection")
state.reset()
expect(state.route(key: 18, down: true, repeated: false, bound: false, commandModifier: true, input: .folderPicker, folderCount: 9).folderNumber == nil, "Command number no longer selects a folder")
capsDown()
let appNumber = state.route(key: 18, down: true, repeated: false, bound: true)
expect(appNumber.folderNumber == nil && releaseCaps().launchKeys == [18], "Caps number outside folder panel still launches its assigned app")
state.reset()
print("PASS: Caps folder numbers 1–9, repeat/release consumption, no duplicate opening, app shortcut isolation")

for releaseSpaceFirst in [false, true] {
    state.reset()
    capsDown()
    _ = state.route(key: 49, down: true, repeated: false, bound: false)
    if releaseSpaceFirst { _ = state.route(key: 49, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 9) }
    state.modifierChanged(otherModifier: false, commandModifier: true)
    let letter = state.route(key: 0, down: true, repeated: false, bound: true, commandModifier: true, input: .folderPicker, folderCount: 9)
    expect(letter.swallow && letter.folderJump == 0 && letter.launchKeys == nil, "Command-held Caps letters jump without editing search")
    let letterUp = state.route(key: 0, down: false, repeated: false, bound: true, commandModifier: true, input: .folderPicker, folderCount: 9)
    expect(letterUp.swallow, "Caps navigation letter release is consumed")
    let number = state.route(key: 20, down: true, repeated: false, bound: true, commandModifier: true, input: .folderPicker, folderCount: 9)
    expect(number.swallow && number.folderNumber == 2 && !number.openFolderSelection, "Command-held Caps number selects without opening")
    let release = state.route(key: 79, down: false, repeated: false, bound: false, commandModifier: true, input: .folderPicker, folderCount: 9)
    expect(release.openFolderSelection && !release.tap, "Caps release confirms even with Command still held")
    let ordinaryCommand = state.route(key: 0, down: true, repeated: false, bound: false, commandModifier: true, input: .folderPicker, folderCount: 9)
    expect(!ordinaryCommand.stripCommandModifier, "without Caps normal panel Command shortcuts remain available")
}
state.reset()
capsDown()
expect(!state.route(key: 0, down: true, repeated: false, bound: true, commandModifier: true).stripCommandModifier, "Command is preserved outside folder selection")
state.reset()
print("PASS: Command-held Caps folder letters/numbers, release confirmation, normal Command preservation")

expect(FolderEntry(name: "projects", path: "/tmp/projects").originalName == "projects"
       && !FolderEntry(name: "projects", path: "/tmp/projects").isRenamed
       && FolderEntry(name: "Work", path: "/tmp/projects").isRenamed, "a folder entry knows whether it was renamed")
let folders = [FolderEntry(name: "Work Projects", path: "/tmp/projects"),
               FolderEntry(name: "中文文件夹", path: "/tmp/中文")]
let restoredFolders = try JSONDecoder().decode([FolderEntry].self, from: JSONEncoder().encode(folders))
expect(restoredFolders.map { $0.name } == folders.map { $0.name }, "custom folder names persist")
expect(restoredFolders.map { $0.path } == folders.map { $0.path }, "renaming list entries preserves folder paths")
print("PASS: folder persistence")


var ordered = (0..<4).map { FolderEntry(name: "Folder \($0)", path: "/tmp/\($0)") }
expect(FolderOrder.move(&ordered, paths: ["/tmp/0"], to: 4) == IndexSet(integer: 3), "drag first folder to end")
expect(ordered.map { $0.path } == ["/tmp/1", "/tmp/2", "/tmp/3", "/tmp/0"], "downward drop adjusts insertion boundary")
expect(FolderOrder.move(&ordered, paths: ["/tmp/0"], to: 0) == IndexSet(integer: 0), "drag last folder to beginning")
expect(ordered.map { $0.path } == ["/tmp/0", "/tmp/1", "/tmp/2", "/tmp/3"], "upward drop preserves other rows")
expect(FolderOrder.move(&ordered, paths: ["/tmp/1"], to: 2) == IndexSet(integer: 1), "drop beside same row keeps order")
expect(FolderOrder.move(&ordered, paths: ["/missing"], to: 0) == nil, "unknown dragged folder is rejected")
expect(FolderOrder.move(&ordered, paths: ["/tmp/0"], to: 5) == nil, "invalid drop boundary is rejected")
let savedOrder = try JSONDecoder().decode([FolderEntry].self, from: JSONEncoder().encode(ordered))
expect(savedOrder.map { $0.path } == ordered.map { $0.path }, "custom order persists")
print("PASS: single folder drag order, boundary validation, persisted order")

var groupOrder = (0..<6).map { FolderEntry(name: "Folder \($0)", path: "/tmp/\($0)") }
expect(FolderOrder.move(&groupOrder, paths: ["/tmp/3", "/tmp/1"], to: 6) == IndexSet(integersIn: 4..<6), "multi-row drop selects moved block")
expect(groupOrder.map { $0.path } == ["/tmp/0", "/tmp/2", "/tmp/4", "/tmp/5", "/tmp/1", "/tmp/3"], "group drag preserves original relative order")
expect(FolderOrder.move(&groupOrder, paths: ["/tmp/1", "/tmp/3"], to: 0) == IndexSet(integersIn: 0..<2), "multi-row drag upward")
expect(groupOrder.map { $0.path } == ["/tmp/1", "/tmp/3", "/tmp/0", "/tmp/2", "/tmp/4", "/tmp/5"], "group moves to start")
let beforeInvalidDrop = groupOrder.map { $0.path }
expect(FolderOrder.move(&groupOrder, paths: ["/tmp/1", "/missing"], to: 2) == nil, "partly invalid group is rejected")
expect(FolderOrder.move(&groupOrder, paths: [], to: 0) == nil, "empty group is rejected")
expect(groupOrder.map { $0.path } == beforeInvalidDrop, "invalid group drop leaves list unchanged")
print("PASS: multiple folder drag, stable ordering, selection, invalid group rejection")

for key in [UInt16(46), 3] {
    for keyStillHeld in [false, true] {
        state.reset()
        capsDown()
        expect(state.route(key: key, down: true, repeated: false, bound: true).swallow, "the shortcut key is consumed")
        if !keyStillHeld {
            expect(state.route(key: key, down: false, repeated: false, bound: true).swallow, "its release before Caps is consumed")
        }
        expect(releaseCaps().launchKeys == [key], "Caps release runs the shortcut before confirmation")
        state.cancelGesture() // Window resignation can occur before the next keyboard event.
        if keyStillHeld {
            expect(state.route(key: key, down: true, repeated: true, bound: false, input: .inactive).swallow, "confirmation consumes original shortcut repeats")
            expect(!state.route(key: 53, down: true, repeated: false, bound: false, input: .inactive).swallow, "fresh Escape can cancel confirmation")
            expect(state.route(key: key, down: false, repeated: false, bound: false, input: .inactive).swallow, "confirmation consumes original shortcut release")
        }
        expect(!state.route(key: key, down: true, repeated: false, bound: false, input: .inactive).swallow, "a fresh press can confirm or type normally")
        _ = state.route(key: key, down: false, repeated: false, bound: false, input: .inactive)
    }
}
print("PASS: confirmation repeat/release ownership, both release orders, focus changes, fresh input")

for count in [0, 1, 8, 9] {
    for (number, key) in [UInt16(18), 19, 20, 21, 23, 22, 26, 28, 25].enumerated() {
        state.reset()
        capsDown()
        let result = state.route(key: key, down: true, repeated: false, bound: true, input: .folderPicker, folderCount: count)
        expect(result.swallow && result.launchKeys == nil, "folder numbers never leak to app shortcuts")
        expect(result.folderNumber == (number < count ? number : nil), "only existing folder numbers select rows")
        let release = state.route(key: 79, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: count)
        expect(release.openFolderSelection == (number < count), "invalid number cannot open the existing selection")
        expect(state.route(key: key, down: false, repeated: false, bound: false).swallow, "invalid and valid number releases are consumed")
    }
}
state.reset()
capsDown()
_ = state.route(key: 18, down: true, repeated: false, bound: false, input: .folderPicker, folderCount: 1)
_ = state.route(key: 18, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 1)
_ = state.route(key: 25, down: true, repeated: false, bound: false, input: .folderPicker, folderCount: 1)
expect(!state.route(key: 79, down: false, repeated: false, bound: false, input: .folderPicker, folderCount: 1).openFolderSelection, "invalid number cancels earlier valid selection intent")
print("PASS: folder number bounds, empty lists, invalid number after valid selection")


let batchFolders = (0..<4).map { FolderEntry(name: "Folder \($0)", path: "/batch/\($0)") }
for missingMask in 0..<16 {
    for failedMask in 0..<16 {
        var attempted: [String] = []
        let result = FolderBatchOpen.run(batchFolders, isDirectory: { path in
            let index = batchFolders.firstIndex { $0.path == path }!
            return missingMask & (1 << index) == 0
        }, open: { folder in
            attempted.append(folder.path)
            let index = batchFolders.firstIndex { $0.path == folder.path }!
            return failedMask & (1 << index) == 0
        })
        let valid = batchFolders.indices.filter { missingMask & (1 << $0) == 0 }
        let successful = valid.filter { failedMask & (1 << $0) == 0 }
        expect(attempted == valid.map { batchFolders[$0].path }, "batch attempts every valid folder in selection order despite failures")
        expect(result.openedCount == successful.count, "batch counts successful opens")
        expect(result.failures.count == batchFolders.count - successful.count, "batch collects every failure once")
        for index in batchFolders.indices where !successful.contains(index) {
            expect(result.failures.contains { $0.contains(batchFolders[index].path) }, "failure identifies the folder path")
        }
    }
}
let emptyBatch = FolderBatchOpen.run([], isDirectory: { _ in fatalError("empty selection must not access disk") }, open: { _ in fatalError("empty selection must not open anything") })
expect(emptyBatch.openedCount == 0 && emptyBatch.failures.isEmpty, "empty batch is a no-op")
print("PASS: 256 batch-open failure combinations, selection order, aggregated errors, empty selection")

// The same standalone rule applies to normal apps, focused input (recording,
// confirmation, editors), and folder lists. Only chord actions depend on context.
for input in [KeyboardState.Input.shortcuts, .folderPicker, .inactive] {
    state.reset()
    _ = state.route(key: 79, down: true, repeated: false, bound: false, input: input)
    _ = state.route(key: 79, down: true, repeated: true, bound: false, input: input)
    let release = state.route(key: 79, down: false, repeated: false, bound: false, input: input)
    expect(release.tap && !release.openFolderSelection, "standalone Caps replays in every context")
    expect(!releaseCaps().tap, "standalone Caps replays once")
}
state.reset()
_ = state.route(key: 79, down: true, repeated: false, bound: false, input: .inactive)
let focusedSpace = state.route(key: 49, down: true, repeated: false, bound: false, input: .inactive)
expect(!focusedSpace.showFolders && !focusedSpace.swallow, "focused input suppresses Caps Space action and receives Space")
expect(!releaseCaps().tap, "Caps Space in focused input never replays")
state.reset()
capsDown()
let typed = state.route(key: 3, down: true, repeated: false, bound: true, input: .inactive)
expect(!typed.swallow && typed.launchKeys == nil, "focused input receives assigned letters without launching")
expect(!releaseCaps().tap, "typing a chord in focused input does not replay Caps")
state.reset()
capsDown()
let changedContext = state.route(key: 79, down: false, repeated: false, bound: false,
                                 input: .inactive)
expect(changedContext.tap, "context alone cannot swallow a standalone Caps gesture")
state.reset()
capsDown()
_ = state.route(key: 3, down: true, repeated: false, bound: true)
expect(state.route(key: 3, down: false, repeated: false, bound: false,
                   input: .inactive).swallow,
       "context changes preserve ownership of swallowed shortcut releases")
expect(!releaseCaps().tap, "a handled chord cannot become standalone after context changes")
print("PASS: unified standalone Caps, context-specific chords, repeat and release ownership")

// Secure Event Input can hide releases from the tap; the hardware state recovers them.
state.reset()
capsDown()
_ = state.route(key: 17, down: true, repeated: false, bound: true)
_ = releaseCaps()
state.dropMissedReleases(except: 0, isDown: { _ in true })
expect(state.route(key: 17, down: true, repeated: true, bound: true).swallow,
       "a consumed key that is still down keeps its repeats consumed")
state.dropMissedReleases(except: 0, isDown: { _ in false })
expect(!state.route(key: 17, down: true, repeated: false, bound: true).swallow,
       "a consumed key whose release was hidden types normally again")
state.reset()
capsDown()
_ = state.route(key: 17, down: true, repeated: false, bound: true)
state.dropMissedReleases(except: 17, isDown: { _ in false })
expect(state.route(key: 17, down: false, repeated: false, bound: true).swallow,
       "the key of the current event is never dropped")
state.reset()
capsDown()
state.capsReleaseMissed()
expect(!state.held, "a hidden Caps release ends the gesture")
expect(!state.route(key: 1, down: true, repeated: false, bound: true).swallow,
       "ordinary typing never launches after a hidden Caps release")
expect(!releaseCaps().tap, "a hidden Caps release never replays Caps")
state.reset()
capsDown()
_ = state.route(key: 1, down: true, repeated: false, bound: true)
state.capsReleaseMissed()
expect(state.route(key: 1, down: false, repeated: false, bound: true).swallow,
       "pending shortcut releases stay owned after a hidden Caps release")
state.reset()
_ = state.route(key: 79, down: true, repeated: true, bound: false)
expect(!state.held, "a Caps autorepeat cannot start a gesture")
expect(!releaseCaps().tap, "releasing after an orphan autorepeat does not toggle Caps Lock")
capsDown()
_ = state.route(key: 3, down: true, repeated: false, bound: false)
state.cancelGesture()
_ = state.route(key: 79, down: true, repeated: true, bound: false)
expect(!releaseCaps().tap, "a cancelled chord stays cancelled while Caps keeps repeating")
expect(KeyCode.digits1to9 == [18, 19, 20, 21, 23, 22, 26, 28, 25], "number row matches virtual key codes")
expect(KeyCode.lettersAndDigits.count == 36 && KeyCode.isReturn(36) && KeyCode.isReturn(76),
       "derived key tables cover letters, digits, and both Return keys")
print("PASS: hidden releases, orphan Caps autorepeats, derived key tables")

let suite = "local.maxvoid.Clutch.tests"
let testDefaults = UserDefaults(suiteName: suite)!
testDefaults.removePersistentDomain(forName: suite)
let missingList = try StoredList.load([FolderEntry].self, forKey: "Folders", description: "folders", defaults: testDefaults)
expect(missingList == nil, "missing data loads as nothing")
let encodedFolders = try JSONEncoder().encode(folders)
testDefaults.set(encodedFolders, forKey: "Folders")
let savedList = try StoredList.load([FolderEntry].self, forKey: "Folders", description: "folders", defaults: testDefaults)
expect(savedList?.map { $0.path } == folders.map { $0.path }, "saved data round-trips")
let unreadable = Data("not json".utf8)
testDefaults.set(unreadable, forKey: "Folders")
var reported = false
do { _ = try StoredList.load([FolderEntry].self, forKey: "Folders", description: "folders", defaults: testDefaults) }
catch { reported = true }
expect(reported, "unreadable data is reported")
expect(testDefaults.data(forKey: "Folders.unreadable") == unreadable, "unreadable data is preserved before it can be overwritten")
expect(testDefaults.data(forKey: "Folders") == nil, "unreadable data is reported only once")
testDefaults.removePersistentDomain(forName: suite)
print("PASS: saved lists load, round-trip, and preserve unreadable data")

// Window layout: Caps + ← → ↑ ↓ − =.
state.reset()
capsDown()
let leftKey = state.route(key: 123, down: true, repeated: false, bound: true, windowKey: true)
expect(leftKey.swallow && leftKey.windowPreview == 123 && leftKey.window == nil && leftKey.launchKeys == nil, "a window key shows its preview and waits for Caps release")
expect(state.windowPreviewActive, "the preview stays while Caps is held")
expect(state.route(key: 123, down: true, repeated: true, bound: false, windowKey: true).swallow, "holding an arrow does not repeat the layout")
expect(state.route(key: 123, down: false, repeated: false, bound: false, windowKey: true).swallow, "window key release is consumed")
let leftRelease = releaseCaps()
expect(leftRelease.window == 123 && leftRelease.launchKeys == nil && !leftRelease.tap, "window keys win over App List bindings and never toggle Caps Lock")
capsDown()
for _ in 0..<2 {
    expect(state.route(key: 126, down: true, repeated: false, bound: false, windowKey: true).windowPreview == 126, "each ↑ press steps the preview")
    _ = state.route(key: 126, down: false, repeated: false, bound: false, windowKey: true)
}
expect(releaseCaps().window == 126 && !state.windowPreviewActive, "Caps release applies the previewed layout")
capsDown()
_ = state.route(key: 126, down: true, repeated: false, bound: false, windowKey: true)
expect(state.route(key: 123, down: true, repeated: false, bound: false, windowKey: true).windowPreview == 123, "another window key changes the preview")
expect(releaseCaps().window != nil, "mixed window keys apply the final preview")
_ = state.route(key: 126, down: false, repeated: false, bound: false, windowKey: true)
_ = state.route(key: 123, down: false, repeated: false, bound: false, windowKey: true)
capsDown()
_ = state.route(key: 123, down: true, repeated: false, bound: false, windowKey: true)
let escape = state.route(key: 53, down: true, repeated: false, bound: false)
expect(escape.swallow && !state.windowPreviewActive, "Escape while Caps is held cancels the preview")
expect(state.windowGesture, "a hold that started with a window key stays a window gesture")
expect(releaseCaps().window == nil, "a cancelled preview is not applied")
_ = state.route(key: 123, down: false, repeated: false, bound: false, windowKey: true)
_ = state.route(key: 53, down: false, repeated: false, bound: false)
capsDown()
_ = state.route(key: 123, down: true, repeated: false, bound: false, windowKey: true)
expect(state.route(key: 3, down: true, repeated: false, bound: true).windowPreview == nil && !state.windowPreviewActive, "an app key cancels the preview")
expect(releaseCaps().window == nil && releaseCaps().launchKeys == nil, "nothing runs after a mixed window and app gesture")
_ = state.route(key: 123, down: false, repeated: false, bound: false, windowKey: true)
_ = state.route(key: 3, down: false, repeated: false, bound: true)
_ = state.route(key: 126, down: false, repeated: false, bound: false, windowKey: true)
_ = state.route(key: 123, down: false, repeated: false, bound: false, windowKey: true)
expect(!state.route(key: 123, down: true, repeated: false, bound: false, windowKey: true).swallow, "arrows pass through without Caps")
_ = state.route(key: 123, down: false, repeated: false, bound: false, windowKey: true)
capsDown()
expect(state.route(key: 123, down: true, repeated: false, bound: false, windowKey: true, input: .folderPicker, folderCount: 9).window == nil, "arrows navigate the folder list instead")
_ = releaseCaps()
state.reset()
capsDown()
expect(state.route(key: 123, down: true, repeated: false, bound: false, windowKey: true, otherModifier: true).window == nil, "Control/Option + Caps + arrow does nothing")
_ = releaseCaps()
state.reset()
capsDown()
expect(state.route(key: 24, down: true, repeated: false, bound: false, windowKey: true, input: .inactive).window == nil, "no layout while recording or confirming")
_ = releaseCaps()
state.reset()
let defaultWindowKeys = WindowShortcuts.defaults
expect(defaultWindowKeys.command(for: 123) == .left && defaultWindowKeys.command(for: 124) == .right && defaultWindowKeys.command(for: 126) == .up &&
       defaultWindowKeys.command(for: 125) == .down && defaultWindowKeys.command(for: 27) == .smaller && defaultWindowKeys.command(for: 24) == .larger &&
       defaultWindowKeys.command(for: 44) == .center && defaultWindowKeys.command(for: 0) == nil && defaultWindowKeys.command(for: unassignedKey) == nil,
       "default window key table")

let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
let start = CGRect(x: 200, y: 100, width: 800, height: 500)
func same(_ a: CGRect?, _ b: CGRect) -> Bool { a.map { WindowLayout.same($0, b) } ?? false }
// ← cycles 1/2 → 2/3 → 1/3 while the window stays where Clutch put it.
var memory: WindowMemory? = nil
var frame = start
for (fraction, step) in [(CGFloat(1) / 2, 0), (CGFloat(2) / 3, 1), (CGFloat(1) / 3, 2), (CGFloat(1) / 2, 0)] {
    let action = WindowLayout.action(for: .left, current: frame, screen: screen, memory: memory)!
    expect(action == .leftHalf(step: step), "left half step \(step)")
    let target = WindowLayout.frame(for: action, window: frame, screen: screen, restore: memory?.restoreFrame)!
    expect(same(target, CGRect(x: 0, y: 25, width: (1440 * fraction).rounded(), height: 875)), "left half fraction \(fraction)")
    memory = WindowLayout.remember(action, before: frame, after: target, memory: memory)
    frame = target
}
expect(memory?.restoreFrame == start, "repeats keep the original restore point")
expect(same(WindowLayout.frame(for: .rightHalf(step: 0), window: start, screen: screen, restore: nil), CGRect(x: 720, y: 25, width: 720, height: 875)), "right half")
expect(WindowLayout.action(for: .right, current: frame, screen: screen, memory: memory) == .rightHalf(step: 0), "switching sides starts at 1/2")
// ↓ restores, then has nothing left to restore.
let restore = WindowLayout.action(for: .down, current: frame, screen: screen, memory: memory)!
expect(restore == .restore && same(WindowLayout.frame(for: restore, window: frame, screen: screen, restore: memory?.restoreFrame), start), "↓ restores the frame before the first layout")
expect(WindowLayout.remember(restore, before: frame, after: start, memory: memory) == nil, "restore clears the memory")
expect(WindowLayout.action(for: .down, current: start, screen: screen, memory: nil) == nil, "↓ without history does nothing")
// ↑ fills the height, ↑ again maximizes.
let upOnce = WindowLayout.action(for: .up, current: start, screen: screen, memory: nil)!
let tall = WindowLayout.frame(for: upOnce, window: start, screen: screen, restore: nil)!
expect(upOnce == .maximizeHeight && same(tall, CGRect(x: 200, y: 25, width: 800, height: 875)), "↑ keeps x/width and fills the height")
memory = WindowLayout.remember(upOnce, before: start, after: tall, memory: nil)
let upTwice = WindowLayout.action(for: .up, current: tall, screen: screen, memory: memory)!
expect(upTwice == .maximize && same(WindowLayout.frame(for: upTwice, window: tall, screen: screen, restore: nil), screen), "↑↑ maximizes")
expect(WindowLayout.action(for: .up, current: start, screen: screen, memory: memory) == .maximizeHeight, "a window moved by hand starts over")
let maximizedMemory = WindowLayout.remember(upTwice, before: tall, after: screen, memory: memory)
expect(maximizedMemory?.unmaximizedFrame == tall, "maximize remembers the frame it left")
let upThrice = WindowLayout.action(for: .up, current: screen, screen: screen, memory: maximizedMemory)!
expect(upThrice == .maximizeHeight && same(WindowLayout.frame(for: upThrice, window: screen, screen: screen, restore: start, unmaximized: tall)!, tall),
       "↑ on a window Clutch maximized returns to full height at its previous width")
let halfMaximized = WindowLayout.remember(.maximize, before: CGRect(x: 0, y: 25, width: 720, height: 875), after: screen, memory: nil)
expect(same(WindowLayout.frame(for: .maximizeHeight, window: screen, screen: screen, restore: halfMaximized?.restoreFrame,
                               unmaximized: halfMaximized?.unmaximizedFrame)!, CGRect(x: 0, y: 25, width: 720, height: 875)),
       "a half-screen window maximized by ↑ returns to its half")
expect(WindowLayout.remember(.maximizeHeight, before: start, after: tall, memory: memory)?.restoreFrame == start, "moved window gets a new restore point")
// − / = resize by 30 points, keep the center or attached edges, and stay on screen.
expect(same(WindowLayout.resized(start, in: screen, by: -30), CGRect(x: 215, y: 115, width: 770, height: 470)), "smaller keeps the center")
expect(same(WindowLayout.resized(start, in: screen, by: 30), CGRect(x: 185, y: 85, width: 830, height: 530)), "larger keeps the center")
let leftHalf = CGRect(x: 0, y: 25, width: 720, height: 875)
expect(same(WindowLayout.resized(leftHalf, in: screen, by: 30), CGRect(x: 0, y: 25, width: 750, height: 875)), "larger keeps the left edge attached")
expect(same(WindowLayout.resized(leftHalf, in: screen, by: -30), CGRect(x: 0, y: 40, width: 690, height: 845)), "smaller keeps the left edge attached")
let corner = CGRect(x: 1200, y: 600, width: 230, height: 290)
expect(same(WindowLayout.resized(corner, in: screen, by: 30), CGRect(x: 1180, y: 580, width: 260, height: 320)), "growth shifts back onto the screen")
expect(WindowLayout.resized(screen, in: screen, by: 30) == nil, "a maximized window cannot grow")
let tiny = CGRect(x: 600, y: 400, width: 360, height: 219)
expect(WindowLayout.resized(tiny, in: screen, by: -30) == nil, "shrinking stops at a quarter of the screen")
// Multiple displays: pick the display holding most of the window.
let displays = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: -200, width: 1920, height: 1080)]
expect(WindowLayout.screenIndex(for: CGRect(x: 1300, y: 100, width: 800, height: 500), screens: displays) == 1, "largest overlap wins")
expect(WindowLayout.screenIndex(for: CGRect(x: -5000, y: 0, width: 100, height: 100), screens: displays) == 0, "off-screen falls back to the first display")
expect(WindowLayout.action(for: .up, current: leftHalf, screen: screen, memory: nil) == .maximize, "↑ on a half-screen window (already full height) maximizes")
expect(WindowLayout.action(for: .up, current: CGRect(x: 300, y: 25, width: 600, height: 875), screen: screen, memory: nil) == .maximize, "↑ on a window stretched to full height by hand maximizes")
expect(WindowLayout.action(for: .up, current: CGRect(x: 300, y: 25, width: 600, height: 860), screen: screen, memory: nil) == .maximizeHeight, "↑ on a window short of the bottom fills the height first")
// Caps + / centers, keeping the window's size.
expect(WindowLayout.action(for: .center, current: start, screen: screen, memory: nil) == .center, "/ centers")
expect(same(WindowLayout.frame(for: .center, window: start, screen: screen, restore: nil), CGRect(x: 320, y: 213, width: 800, height: 500)), "center keeps the size")
expect(same(WindowLayout.frame(for: .center, window: CGRect(x: 0, y: 0, width: 3000, height: 3000), screen: screen, restore: nil), screen), "an oversized window is fitted to the screen")
// Accessibility writes: only what changes, in an order that stays on screen.
let visibles = [screen]
let rightHalf = CGRect(x: 720, y: 25, width: 720, height: 875)
expect(WindowLayout.writes(from: leftHalf, to: leftHalf, screens: visibles).isEmpty, "an unchanged frame writes nothing")
expect(WindowLayout.writes(from: start, to: CGRect(x: 320, y: 213, width: 800, height: 500), screens: visibles) == [.position], "center only moves")
expect(WindowLayout.writes(from: leftHalf, to: CGRect(x: 0, y: 25, width: 960, height: 875), screens: visibles) == [.size], "left 1/2 → 2/3 only resizes")
expect(WindowLayout.writes(from: CGRect(x: 0, y: 25, width: 960, height: 875), to: CGRect(x: 960, y: 25, width: 480, height: 875), screens: visibles) == [.size, .position], "shrinking resizes in place first")
expect(WindowLayout.writes(from: rightHalf, to: CGRect(x: 480, y: 25, width: 960, height: 875), screens: visibles) == [.position, .size], "growing past the edge moves first")
expect(WindowLayout.writes(from: start, to: leftHalf, screens: visibles) == [.position, .size], "a centered window moves to the corner before filling the height")
expect(WindowLayout.writes(from: start, to: CGRect(x: 185, y: 85, width: 830, height: 530), screens: visibles) == [.size, .position], "growing with room resizes first")
expect(WindowLayout.writes(from: CGRect(x: 1300, y: 800, width: 300, height: 300), to: CGRect(x: 1400, y: 900, width: 2000, height: 1000), screens: visibles) == [.size, .position, .size], "no on-screen order falls back to size, position, size")
expect(WindowLayout.writes(from: CGRect(x: 0, y: 25, width: 718, height: 875), to: leftHalf, screens: visibles).isEmpty, "a near-match within tolerance writes nothing")
expect(WindowLayout.corrections(from: leftHalf, to: leftHalf).isEmpty, "a landed frame needs no correction")
expect(WindowLayout.corrections(from: CGRect(x: 0, y: 25, width: 720, height: 600), to: leftHalf) == [.size], "a clamped size is written again")
expect(WindowLayout.corrections(from: CGRect(x: 40, y: 25, width: 600, height: 875), to: leftHalf) == [.size, .position], "size before position when both missed")
// Window shortcuts edited on Preferences > Windows.
var windowKeys = WindowShortcuts.defaults
windowKeys.assign(40, to: .center)
expect(windowKeys.key(for: .center) == 40 && windowKeys.command(for: 40) == .center && windowKeys.command(for: 44) == nil, "reassigning frees the old key")
windowKeys.assign(123, to: .right)
expect(windowKeys.key(for: .right) == 123 && windowKeys.key(for: .left) == nil, "taking another action's key leaves it unassigned")
windowKeys.clear(123)
expect(windowKeys.command(for: 123) == nil && windowKeys.key(for: .right) == nil, "clearing a key unassigns its action")
let windowKeysSuite = "local.maxvoid.Clutch.window-tests"
let windowKeysDefaults = UserDefaults(suiteName: windowKeysSuite)!
windowKeysDefaults.removePersistentDomain(forName: windowKeysSuite)
expect(WindowShortcuts.load(from: windowKeysDefaults) == .defaults, "nothing saved loads the defaults")
windowKeys.save(to: windowKeysDefaults)
expect(WindowShortcuts.load(from: windowKeysDefaults) == windowKeys, "window shortcuts round-trip, including unassigned actions")
windowKeysDefaults.set(Data(#"{"center":40,"left":40}"#.utf8), forKey: DefaultsKey.windowShortcuts)
let partialKeys = WindowShortcuts.load(from: windowKeysDefaults)
expect(partialKeys.key(for: .left) == 40 && partialKeys.key(for: .center) == nil && partialKeys.key(for: .up) == 126,
       "missing actions keep defaults and a repeated key stays with one action")
windowKeysDefaults.set(Data("junk".utf8), forKey: DefaultsKey.windowShortcuts)
expect(WindowShortcuts.load(from: windowKeysDefaults) == .defaults, "unreadable window shortcuts load the defaults")
windowKeysDefaults.removePersistentDomain(forName: windowKeysSuite)
// Preview plans: the window actions of one Caps hold, applied on release.
let planScreen = CGRect(x: 0, y: 25, width: 1440, height: 875)
let planStart = CGRect(x: 320, y: 213, width: 800, height: 500)
var plan = WindowPlan(start: planStart, screen: planScreen, memory: nil)
expect(!plan.applied && plan.frame == planStart, "a new plan shows nothing yet")
plan.apply(.left)
expect(plan.frame == CGRect(x: 0, y: 25, width: 720, height: 875), "← previews the left half")
plan.apply(.left)
expect(plan.frame.width == 960, "← again previews 2/3")
plan.apply(.left)
expect(plan.frame.width == 480, "← a third time previews 1/3")
plan.apply(.left)
expect(plan.frame.width == 720, "← wraps back to 1/2")
plan.apply(.right)
expect(plan.frame == CGRect(x: 720, y: 25, width: 720, height: 875), "→ switches the preview to the right half")
plan.apply(.down)
expect(!plan.applied && plan.frame == planStart, "↓ after other keys previews what ↓ alone would: nothing without a restore point")
var leftThenUp = WindowPlan(start: planStart, screen: planScreen, memory: nil)
leftThenUp.apply(.left)
leftThenUp.apply(.up)
expect(leftThenUp.frame == CGRect(x: 320, y: 25, width: 800, height: 875), "← then ↑ previews ↑ alone (fill height), not maximize")
var restorePlan = WindowPlan(start: CGRect(x: 0, y: 25, width: 720, height: 875), screen: planScreen,
                             memory: WindowMemory(restoreFrame: planStart, lastAction: .leftHalf(step: 0), lastFrame: CGRect(x: 0, y: 25, width: 720, height: 875)))
restorePlan.apply(.down)
expect(restorePlan.applied && restorePlan.frame == planStart && restorePlan.memory == nil, "↓ previews the frame before the first layout")
var heightPlan = WindowPlan(start: planStart, screen: planScreen, memory: nil)
heightPlan.apply(.up)
expect(heightPlan.frame == CGRect(x: 320, y: 25, width: 800, height: 875), "↑ previews fill height")
heightPlan.apply(.up)
expect(heightPlan.frame == planScreen, "↑ again previews maximize")
heightPlan.apply(.up)
expect(heightPlan.frame == CGRect(x: 320, y: 25, width: 800, height: 875), "↑ a third time goes back to fill height")
heightPlan.apply(.up)
expect(heightPlan.frame == planScreen, "↑ keeps toggling fill height ⇄ maximize")
expect(heightPlan.memory?.restoreFrame == planStart, "the plan keeps the original restore point")
var sizePlan = WindowPlan(start: planStart, screen: planScreen, memory: nil)
sizePlan.apply(.larger)
sizePlan.apply(.larger)
expect(sizePlan.frame == CGRect(x: 290, y: 183, width: 860, height: 560), "= twice previews two steps larger, applied at once")
sizePlan.apply(.smaller)
expect(sizePlan.frame == CGRect(x: 305, y: 198, width: 830, height: 530), "− steps the preview back")
var nothing = WindowPlan(start: planStart, screen: planScreen, memory: nil)
nothing.apply(.down)
expect(!nothing.applied, "↓ without a restore point previews and applies nothing")
let remembered = WindowMemory(restoreFrame: planStart, lastAction: .leftHalf(step: 0), lastFrame: CGRect(x: 0, y: 25, width: 720, height: 875))
var continued = WindowPlan(start: remembered.lastFrame, screen: planScreen, memory: remembered)
continued.apply(.left)
expect(continued.frame.width == 960, "a window Clutch left at 1/2 continues with 2/3")
print("PASS: window preview plans: halves cycle, height/maximize, restore, resize steps, continuation")
print("PASS: window layout routing, halves, height/maximize, restore, resize, displays")

// Websites: the address saved for what was typed, what it matches, and which open tab Caps goes to.
expect(WebsiteAddress.normalize("github.com") == "https://github.com", "a bare domain gets https")
expect(WebsiteAddress.normalize("  HTTPS://GitHub.com/ ") == "https://github.com", "scheme and host are lowercased, a lone / dropped")
expect(WebsiteAddress.normalize("github.com/qianshuguo/clutch/") == "https://github.com/qianshuguo/clutch", "trailing slashes are dropped")
expect(WebsiteAddress.normalize("mail.google.com/mail/u/0/#inbox") == "https://mail.google.com/mail/u/0/#inbox",
       "a fragment is kept for opening")
expect(WebsiteAddress.normalize("localhost:3000") == "http://localhost:3000"
       && WebsiteAddress.normalize("127.0.0.1:8080/app") == "http://127.0.0.1:8080/app", "local servers get http")
expect(WebsiteAddress.normalize("https://localhost:3000") == "https://localhost:3000", "a typed scheme is kept")
expect(["", "  ", "github", "not a url", "ftp://example.com", "chrome://newtab", "github.com."].allSatisfy {
    WebsiteAddress.normalize($0) == nil }, "text that is not a web address is refused")
let wholeSite = WebsiteAddress("https://github.com")!
expect(wholeSite.matches(WebsiteAddress("http://www.github.com/x/y?tab=1#top")!), "a domain matches every page of the site, with or without www")
expect(!wholeSite.matches(WebsiteAddress("https://gist.github.com")!), "without Include subdomains, subdomains are other sites")
let ctrip = WebsiteScope(WebsiteAddress("https://ctrip.com")!, includesSubdomains: true)
expect(ctrip.matches(WebsiteAddress("https://flight.ctrip.com/x")!) && ctrip.matches(WebsiteAddress("https://a.b.ctrip.com")!)
       && ctrip.matches(WebsiteAddress("https://www.ctrip.com")!), "with Include subdomains, a domain matches its subdomains")
expect(!ctrip.matches(WebsiteAddress("https://notctrip.com")!) && !ctrip.matches(WebsiteAddress("https://ctrip.com.evil.io")!),
       "other domains ending in the same letters are not subdomains")
expect(!WebsiteScope(WebsiteAddress("http://localhost:3000")!, includesSubdomains: true).includesSubdomains
       && !WebsiteScope(WebsiteAddress("http://127.0.0.1")!, includesSubdomains: true).matches(WebsiteAddress("http://9.127.0.0.1")!),
       "localhost and IP addresses have no subdomains")
expect(WebsiteScope(WebsiteAddress("https://ctrip.com/abc")!, includesSubdomains: true).matches(WebsiteAddress("https://flight.ctrip.com/abc/1")!)
       && !WebsiteScope(WebsiteAddress("https://ctrip.com/abc")!, includesSubdomains: true).matches(WebsiteAddress("https://flight.ctrip.com/")!),
       "Include subdomains changes only the domain; a path still applies")
expect(!wholeSite.matches(WebsiteAddress("https://github.com:8443")!), "another port is another site")
let repoPage = WebsiteAddress("https://github.com/qianshuguo/clutch")!
expect(repoPage.matches(WebsiteAddress("https://github.com/qianshuguo/clutch")!)
       && repoPage.matches(WebsiteAddress("https://github.com/QianShuGuo/Clutch/issues/3")!), "a path matches that page and below, ignoring case")
expect(!repoPage.matches(WebsiteAddress("https://github.com/qianshuguo/clutchy")!)
       && !repoPage.matches(WebsiteAddress("https://github.com/qianshuguo")!), "a path does not match siblings or parents")
expect(WebsiteAddress("about:blank") == nil && WebsiteAddress("") == nil && WebsiteAddress("file:///tmp") == nil,
       "non-web tabs never match")
expect(WebsiteEntry(url: "https://www.github.com/QianShuGuo/").name == "github.com/qianshuguo"
       && WebsiteEntry(url: "http://localhost:3000").name == "localhost:3000", "names show exactly what matches")
let oldSite = try! JSONDecoder().decode([WebsiteEntry].self, from: Data(#"[{"url":"https://github.com"}]"#.utf8))
expect(oldSite[0].keys.isEmpty, "a website saved without a shortcut loads")
expect(oldSite[0].includesSubdomains, "a website saved before Include subdomains existed includes them")
let exactSite = WebsiteEntry(url: "https://github.com", includesSubdomains: false)
expect(String(decoding: try! JSONEncoder().encode(exactSite), as: UTF8.self).contains(#""subdomains":false"#)
       && (try! JSONDecoder().decode(WebsiteEntry.self, from: JSONEncoder().encode(exactSite))) == exactSite
       && !String(decoding: try! JSONEncoder().encode(oldSite[0]), as: UTF8.self).contains("subdomains"),
       "Include subdomains is saved only when off, and round-trips")
let savedSite = WebsiteEntry(url: "https://github.com", keys: [5])
expect(String(decoding: try! JSONEncoder().encode(savedSite), as: UTF8.self).contains(#""shortcut":[5]"#)
       && (try! JSONDecoder().decode(WebsiteEntry.self, from: JSONEncoder().encode(savedSite))) == savedSite,
       "website shortcuts are saved under \"shortcut\" and round-trip")
let namedSite = WebsiteEntry(url: "https://github.com/qianshuguo/clutch", title: "Clutch repo", keys: [5])
expect(namedSite.name == "Clutch repo" && namedSite.address == "github.com/qianshuguo/clutch",
       "a named website shows its name instead of what it matches")
expect(WebsiteEntry(url: "https://github.com", title: "  ").name == "github.com", "without a name, the address is the name")
expect(String(data: try! JSONEncoder().encode(namedSite), encoding: .utf8)!.contains(#""title":"Clutch repo""#)
       && (try! JSONDecoder().decode(WebsiteEntry.self, from: JSONEncoder().encode(namedSite))) == namedSite
       && !String(data: try! JSONEncoder().encode(savedSite), encoding: .utf8)!.contains("title"),
       "a website's name is saved under \"title\", and left out when empty")
// Window 7 is in front with Hacker News selected; window 3 behind it shows a GitHub page.
let browserTabs = [BrowserTab(window: 7, windowIndex: 1, index: 1, url: "https://news.ycombinator.com", active: true),
                   BrowserTab(window: 7, windowIndex: 1, index: 2, url: "https://github.com/a", active: false),
                   BrowserTab(window: 3, windowIndex: 2, index: 1, url: "https://github.com/b", active: true),
                   BrowserTab(window: 3, windowIndex: 2, index: 2, url: "", active: false)]
expect(WebsiteTabChoice.choose(WebsiteScope(wholeSite), tabs: browserTabs, browserFrontmost: false) == browserTabs[1],
       "from another app, the front window's match is chosen")
expect(WebsiteTabChoice.choose(WebsiteScope(wholeSite), tabs: browserTabs, browserFrontmost: true) == browserTabs[1],
       "in the browser on another site, the front window's match is chosen")
let onFirst = [BrowserTab(window: 7, windowIndex: 1, index: 1, url: "https://news.ycombinator.com", active: false),
               BrowserTab(window: 7, windowIndex: 1, index: 2, url: "https://github.com/a", active: true),
               BrowserTab(window: 3, windowIndex: 2, index: 1, url: "https://github.com/b", active: true)]
expect(WebsiteTabChoice.choose(WebsiteScope(wholeSite), tabs: onFirst, browserFrontmost: true) == onFirst[2],
       "pressing again on a match goes to the next match")
let onSecond = [BrowserTab(window: 3, windowIndex: 1, index: 1, url: "https://github.com/b", active: true),
                BrowserTab(window: 7, windowIndex: 2, index: 1, url: "https://news.ycombinator.com", active: false),
                BrowserTab(window: 7, windowIndex: 2, index: 2, url: "https://github.com/a", active: true)]
expect(WebsiteTabChoice.choose(WebsiteScope(wholeSite), tabs: onSecond, browserFrontmost: true) == onSecond[2],
       "the next press wraps around, even though that window came to the front")
expect(WebsiteTabChoice.choose(WebsiteScope(wholeSite), tabs: onFirst, browserFrontmost: false) == onFirst[1],
       "from another app, the match already in front is shown, not skipped")
expect(WebsiteTabChoice.choose(WebsiteScope(WebsiteAddress("https://example.com")!), tabs: browserTabs, browserFrontmost: true) == nil,
       "no match opens a new tab")
expect(WebsiteTabChoice.choose(WebsiteScope(repoPage), tabs: [BrowserTab(window: 1, windowIndex: 1, index: 1,
                                                           url: "https://github.com/qianshuguo/clutch", active: true)],
                               browserFrontmost: true)?.window == 1, "a single match stays selected")
// ctrip.com includes subdomains; flight.ctrip.com has its own shortcut.
let flight = WebsiteScope(WebsiteAddress("https://flight.ctrip.com")!, includesSubdomains: true)
let onlyFlight = [BrowserTab(window: 1, windowIndex: 1, index: 1, url: "https://flight.ctrip.com/list", active: true)]
expect(WebsiteTabChoice.choose(ctrip, tabs: onlyFlight, browserFrontmost: false) == onlyFlight[0],
       "a domain that includes subdomains goes to a subdomain's tab")
expect(WebsiteTabChoice.choose(ctrip, tabs: onlyFlight, browserFrontmost: false, others: [flight]) == nil
       && WebsiteTabChoice.choose(flight, tabs: onlyFlight, browserFrontmost: false, others: [ctrip]) == onlyFlight[0],
       "a tab another website inside it matches belongs to that website")
let hotelsAndHome = [BrowserTab(window: 1, windowIndex: 1, index: 1, url: "https://hotels.ctrip.com", active: true),
                     BrowserTab(window: 2, windowIndex: 2, index: 1, url: "https://www.ctrip.com/", active: true)]
expect(WebsiteTabChoice.choose(ctrip, tabs: hotelsAndHome, browserFrontmost: false, others: [flight]) == hotelsAndHome[1],
       "the site's own domain comes before its subdomains, even in a window behind")
expect(WebsiteTabChoice.choose(ctrip, tabs: [hotelsAndHome[0]], browserFrontmost: false, others: [flight]) == hotelsAndHome[0],
       "a subdomain no other website owns is still the domain's")
let repoTab = [BrowserTab(window: 1, windowIndex: 1, index: 1, url: "https://github.com/qianshuguo/clutch/issues", active: true)]
expect(WebsiteTabChoice.choose(WebsiteScope(wholeSite), tabs: repoTab, browserFrontmost: false, others: [WebsiteScope(repoPage)]) == nil,
       "a page saved with its own path belongs to that website, not the whole site")
let onHome = [BrowserTab(window: 5, windowIndex: 1, index: 1, url: "https://www.ctrip.com", active: true),
              BrowserTab(window: 5, windowIndex: 1, index: 2, url: "https://flight.ctrip.com", active: false),
              BrowserTab(window: 9, windowIndex: 2, index: 1, url: "https://hotels.ctrip.com", active: true)]
expect(WebsiteTabChoice.choose(ctrip, tabs: onHome, browserFrontmost: true, others: [flight]) == onHome[2],
       "pressing again on the domain's tab goes on to its subdomains, skipping tabs other websites own")
print("PASS: website addresses, matching, saved shortcuts, tab choice and cycling")
