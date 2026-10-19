import Foundation
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
expect(launch.swallow && launch.launch == 3, "bound chord consumed and launches")
expect(state.route(key: 3, down: true, repeated: true, bound: true).launch == nil, "no repeated launches")
expect(!releaseCaps().tap, "chord never switches input")
expect(state.route(key: 3, down: false, repeated: false, bound: true).swallow, "consume keyup after Caps released first")
expect(!state.route(key: 3, down: true, repeated: false, bound: true).swallow, "typing returns to normal")
state.reset()
capsDown()
_ = state.route(key: 3, down: true, repeated: false, bound: true)
expect(state.route(key: 3, down: false, repeated: false, bound: true).swallow, "consume keyup when letter released first")
expect(!releaseCaps().tap, "letter release does not turn chord into tap")
capsDown()
expect(!state.route(key: 11, down: true, repeated: false, bound: false).swallow, "unbound key passes normally")
expect(!releaseCaps().tap, "unbound chord does not switch input")
capsDown()
state.beginChord()
expect(!releaseCaps().tap, "modifier after Caps cancels standalone action")
capsDown()
state.reset()
expect(!releaseCaps().tap, "pause cancels pending standalone action")
print("PASS: standalone Caps, repeats, bound/unbound chords, both release orders, modifier cancellation, pause")

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
state.reset()
print("PASS: earlier key/modifier releases keep standalone Caps; new presses still cancel")
// Default app keys plus custom letter, number, and Return mappings.
for key: UInt16 in [1, 3, 17, 8, 9, 0, 18, 36] {
    state.reset()
    capsDown()
    for _ in 0..<4 {
        expect(state.route(key: key, down: true, repeated: false, bound: true).launch == key, "each deliberate mapped press requests activation/window cycling")
        expect(state.route(key: key, down: true, repeated: true, bound: true).launch == nil, "holding a mapped key does not cycle automatically")
        expect(state.route(key: key, down: false, repeated: false, bound: true).swallow, "each mapped release is consumed")
    }
    expect(!releaseCaps().tap, "window cycling never replays standalone Caps")
    for _ in 0..<3 {
        capsDown()
        expect(state.route(key: key, down: true, repeated: false, bound: true).launch == key, "repeating any mapped chord requests window cycling")
        _ = state.route(key: key, down: false, repeated: false, bound: true)
        expect(!releaseCaps().tap, "repeated chords do not toggle Caps")
    }
}
state.reset()
print("PASS: repeated app shortcuts across default and custom mappings")
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
    expect(!extra.swallow && extra.launch == nil, "\(modifier) Caps with extra key passes through")
    expect(!releaseCaps().tap, "extra key does not switch input")
}
print("PASS: Control/Option Caps have no action, both press/release orders, extra keys pass through")

state.reset()
expect(!state.route(key: 49, down: true, repeated: false, bound: false).swallow, "Space without Caps types normally")
for capsReleasedFirst in [false, true] {
    state.reset()
    capsDown()
    let opening = state.route(key: 49, down: true, repeated: false, bound: true)
    expect(opening.swallow && opening.showFolders && opening.launch == nil, "Caps Space opens Folders")
    let spaceRepeat = state.route(key: 49, down: true, repeated: true, bound: false, folderSelectionActive: true, folderCount: 9)
    expect(spaceRepeat.swallow && !spaceRepeat.showFolders, "Space repeats are consumed and never reopen")
    expect(!state.route(key: 79, down: true, repeated: true, bound: false).showFolders, "Caps repeats never reopen")
    if !capsReleasedFirst {
        expect(state.route(key: 49, down: false, repeated: false, bound: false, folderSelectionActive: true, folderCount: 9).swallow, "Space release is consumed")
    }
    let release = state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true, folderCount: 9)
    expect(!release.tap && !release.openFolderSelection && !release.showFolders, "release without navigation leaves panel open")
    if capsReleasedFirst {
        expect(state.route(key: 49, down: false, repeated: false, bound: false, folderSelectionActive: true, folderCount: 9).swallow, "Space release after Caps is consumed")
    }
}
state.reset()
capsDown()
let heldSpace = state.route(key: 49, down: true, repeated: true, bound: false)
expect(!heldSpace.showFolders && !heldSpace.swallow, "Space already held before Caps does not open Folders")
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
    expect(!enter.showFolders && !enter.swallow, "unassigned Caps Enter passes through")
    expect(!releaseCaps().tap, "Caps Enter does not switch input")
    state.reset()
    capsDown()
    expect(state.route(key: key, down: true, repeated: false, bound: true).launch == key, "Caps Enter can use its app assignment")
}
for key in [UInt16(18), 0, 125, 126, 123, 124] {
    state.reset()
    capsDown()
    _ = state.route(key: 49, down: true, repeated: false, bound: false)
    _ = state.route(key: 49, down: false, repeated: false, bound: false, folderSelectionActive: true, folderCount: 9)
    _ = state.route(key: key, down: true, repeated: false, bound: true, folderSelectionActive: true, folderCount: 9)
    _ = state.route(key: key, down: false, repeated: false, bound: true, folderSelectionActive: true, folderCount: 9)
    let release = state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true, folderCount: 9)
    expect(release.openFolderSelection && !release.tap, "number, letter, or arrow input arms opening on Caps release")
    capsDown()
    expect(!state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true, folderCount: 9).openFolderSelection, "selection intent does not carry into another Caps hold")
}
for key in [UInt16(0), 125] {
    state.reset()
    capsDown()
    _ = state.route(key: key, down: false, repeated: false, bound: false, folderSelectionActive: true, folderCount: 9)
    state.modifierChanged(otherModifier: false, commandModifier: true)
    expect(!state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true, folderCount: 9).openFolderSelection, "key releases and modifiers do not count as selection input")
}
state.reset()
capsDown()
_ = state.route(key: 125, down: true, repeated: false, bound: false, otherModifier: true, folderSelectionActive: true, folderCount: 9)
expect(!state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true, folderCount: 9).openFolderSelection, "Control/Option navigation does not arm selection")
state.reset()
print("PASS: idle folder panel stays open, navigation arms Caps release, intent resets between holds")
state.reset()
capsDown()
_ = state.route(key: 11, down: true, repeated: false, bound: false)
let lateSpace = state.route(key: 49, down: true, repeated: false, bound: false)
expect(!lateSpace.showFolders && !lateSpace.swallow, "ordinary key before Space cancels folder gesture")
expect(!releaseCaps().tap, "cancelled gesture cannot switch input")
for modifierFirst in [false, true] {
    state.reset()
    _ = state.route(key: 79, down: true, repeated: false, bound: false, otherModifier: modifierFirst)
    if !modifierFirst { state.modifierChanged(otherModifier: true) }
    let blocked = state.route(key: 49, down: true, repeated: false, bound: false, otherModifier: true)
    expect(!blocked.showFolders && !blocked.swallow, "Control/Option blocks Caps Space")
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
_ = state.route(key: 79, down: true, repeated: false, bound: false, folderSelectionActive: true, folderCount: 9)
let panelSpace = state.route(key: 49, down: true, repeated: false, bound: false, folderSelectionActive: true, folderCount: 9)
expect(!panelSpace.showFolders && !panelSpace.swallow, "existing selection panel never reopens; Space reaches the list")
print("PASS: Caps Space, both release orders, repeats, cancellation, Enter passthrough, Command no longer opens")
state.reset()
capsDown()
expect(state.route(key: 49, down: true, repeated: false, bound: false).showFolders, "open panel while Caps held")
let arrow = state.route(key: 125, down: true, repeated: false, bound: true, folderSelectionActive: true, folderCount: 9)
expect(!arrow.swallow && arrow.launch == nil, "held Caps lets panel selection keys through even if bound")
let folderRelease = state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true, folderCount: 9)
expect(folderRelease.openFolderSelection && !folderRelease.tap && !folderRelease.showFolders, "Caps release confirms folder selection after navigation")
expect(!state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true, folderCount: 9).openFolderSelection, "orphan release cannot confirm again")
capsDown()
let panelTap = state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true, folderCount: 9)
expect(!panelTap.openFolderSelection && panelTap.tap, "standalone Caps in the list replays without opening a folder")
capsDown()
let closedPanelRelease = releaseCaps()
expect(!closedPanelRelease.openFolderSelection && closedPanelRelease.tap, "outside panel Caps retains input switching")
print("PASS: Caps release opens folder selection, navigation passthrough, no input switch, no duplicate confirmation")

for (number, key) in [UInt16(18), 19, 20, 21, 23, 22, 26, 28, 25].enumerated() {
    state.reset()
    capsDown()
    let shortcut = state.route(key: key, down: true, repeated: false, bound: true, folderSelectionActive: true, folderCount: 9)
    expect(shortcut.swallow && shortcut.folderNumber == number && shortcut.launch == nil && !shortcut.openFolderSelection, "Caps number selects folder instead of launching a bound app")
    let repeated = state.route(key: key, down: true, repeated: true, bound: true, folderSelectionActive: true, folderCount: 9)
    expect(repeated.swallow && repeated.folderNumber == nil, "folder shortcut repeats are consumed")
    let release = state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true, folderCount: 9)
    expect(release.openFolderSelection && !release.tap, "Caps release opens the numbered selection")
    expect(!state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true, folderCount: 9).openFolderSelection, "numbered selection opens only once on Caps release")
    expect(state.route(key: key, down: false, repeated: false, bound: true).swallow, "folder shortcut release is consumed even after panel closes")
}
state.reset()
capsDown()
for key in [UInt16(18), 25, 20] {
    let move = state.route(key: key, down: true, repeated: false, bound: true, folderSelectionActive: true, folderCount: 9)
    expect(move.folderNumber != nil && !move.openFolderSelection, "multiple numbers can change selection during one Caps hold")
    let keyUp = state.route(key: key, down: false, repeated: false, bound: true, folderSelectionActive: true, folderCount: 9)
    expect(keyUp.swallow && !keyUp.openFolderSelection, "releasing a number does not open the folder")
}
expect(state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true, folderCount: 9).openFolderSelection, "only Caps release confirms the final selection")
state.reset()
expect(state.route(key: 18, down: true, repeated: false, bound: false, commandModifier: true, folderSelectionActive: true, folderCount: 9).folderNumber == nil, "Command number no longer selects a folder")
capsDown()
let appNumber = state.route(key: 18, down: true, repeated: false, bound: true)
expect(appNumber.launch == 18 && appNumber.folderNumber == nil, "Caps number outside folder panel still launches its assigned app")
state.reset()
print("PASS: Caps folder numbers 1–9, repeat/release consumption, no duplicate opening, app shortcut isolation")

for releaseSpaceFirst in [false, true] {
    state.reset()
    capsDown()
    _ = state.route(key: 49, down: true, repeated: false, bound: false)
    if releaseSpaceFirst { _ = state.route(key: 49, down: false, repeated: false, bound: false, folderSelectionActive: true, folderCount: 9) }
    state.modifierChanged(otherModifier: false, commandModifier: true)
    let letter = state.route(key: 0, down: true, repeated: false, bound: true, commandModifier: true, folderSelectionActive: true, folderCount: 9)
    expect(!letter.swallow && letter.stripCommandModifier && letter.launch == nil, "Command-held Caps letters reach folder type selection as plain typing")
    let letterUp = state.route(key: 0, down: false, repeated: false, bound: true, commandModifier: true, folderSelectionActive: true, folderCount: 9)
    expect(!letterUp.swallow && letterUp.stripCommandModifier, "navigation letter release also removes Command")
    let number = state.route(key: 20, down: true, repeated: false, bound: true, commandModifier: true, folderSelectionActive: true, folderCount: 9)
    expect(number.swallow && number.folderNumber == 2 && !number.openFolderSelection, "Command-held Caps number selects without opening")
    let release = state.route(key: 79, down: false, repeated: false, bound: false, commandModifier: true, folderSelectionActive: true, folderCount: 9)
    expect(release.openFolderSelection && !release.tap, "Caps release confirms even with Command still held")
    let ordinaryCommand = state.route(key: 0, down: true, repeated: false, bound: false, commandModifier: true, folderSelectionActive: true, folderCount: 9)
    expect(!ordinaryCommand.stripCommandModifier, "without Caps normal panel Command shortcuts remain available")
}
state.reset()
capsDown()
expect(!state.route(key: 0, down: true, repeated: false, bound: true, commandModifier: true).stripCommandModifier, "Command is preserved outside folder selection")
state.reset()
print("PASS: Command-held Caps folder letters/numbers, release confirmation, normal Command preservation")

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

for key in [UInt16(36), 3] {
    for capsReleasedFirst in [false, true] {
        state.reset()
        capsDown()
        expect(state.route(key: key, down: true, repeated: false, bound: true).launch == key, "shortcut launches before confirmation")
        state.cancelGesture() // Window resignation can occur before the next keyboard event.
        if capsReleasedFirst {
            expect(state.route(key: 79, down: false, repeated: false, bound: false, shortcutsEnabled: false).swallow, "focused input hides Caps release")
        }
        expect(state.route(key: key, down: true, repeated: false, bound: false, shortcutsEnabled: false).swallow, "confirmation consumes original shortcut repeats")
        expect(!state.route(key: 53, down: true, repeated: false, bound: false, shortcutsEnabled: false).swallow, "fresh Escape can cancel confirmation")
        expect(state.route(key: key, down: true, repeated: true, bound: false).swallow, "shortcut stays consumed even if confirmation closes before release")
        expect(state.route(key: key, down: false, repeated: false, bound: false, shortcutsEnabled: false).swallow, "confirmation consumes original shortcut release")
        expect(!state.route(key: key, down: true, repeated: false, bound: false, shortcutsEnabled: false).swallow, "a fresh press can confirm or type normally")
        expect(!releaseCaps().tap, "focus transition cancels pending Caps gesture")
    }
}
print("PASS: confirmation repeat/release ownership, both release orders, focus changes, fresh input")

for count in [0, 1, 8, 9] {
    for (number, key) in [UInt16(18), 19, 20, 21, 23, 22, 26, 28, 25].enumerated() {
        state.reset()
        capsDown()
        let result = state.route(key: key, down: true, repeated: false, bound: true, folderSelectionActive: true, folderCount: count)
        expect(result.swallow && result.launch == nil, "folder numbers never leak to app shortcuts")
        expect(result.folderNumber == (number < count ? number : nil), "only existing folder numbers select rows")
        let release = state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true, folderCount: count)
        expect(release.openFolderSelection == (number < count), "invalid number cannot open the existing selection")
        expect(state.route(key: key, down: false, repeated: false, bound: false).swallow, "invalid and valid number releases are consumed")
    }
}
state.reset()
capsDown()
_ = state.route(key: 18, down: true, repeated: false, bound: false, folderSelectionActive: true, folderCount: 1)
_ = state.route(key: 18, down: false, repeated: false, bound: false, folderSelectionActive: true, folderCount: 1)
_ = state.route(key: 25, down: true, repeated: false, bound: false, folderSelectionActive: true, folderCount: 1)
expect(!state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true, folderCount: 1).openFolderSelection, "invalid number cancels earlier valid selection intent")
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
for shortcuts in [false, true] {
    for list in [false, true] {
        state.reset()
        _ = state.route(key: 79, down: true, repeated: false, bound: false,
                        folderSelectionActive: list, shortcutsEnabled: shortcuts)
        _ = state.route(key: 79, down: true, repeated: true, bound: false,
                        folderSelectionActive: list, shortcutsEnabled: shortcuts)
        let release = state.route(key: 79, down: false, repeated: false, bound: false,
                                   folderSelectionActive: list, shortcutsEnabled: shortcuts)
        expect(release.tap && !release.openFolderSelection, "standalone Caps replays in every context")
        expect(!releaseCaps().tap, "standalone Caps replays once")
    }
}
state.reset()
_ = state.route(key: 79, down: true, repeated: false, bound: false, shortcutsEnabled: false)
let focusedSpace = state.route(key: 49, down: true, repeated: false, bound: false, shortcutsEnabled: false)
expect(!focusedSpace.showFolders && !focusedSpace.swallow, "focused input suppresses Caps Space action and receives Space")
expect(!releaseCaps().tap, "Caps Space in focused input never replays")
state.reset()
capsDown()
let typed = state.route(key: 3, down: true, repeated: false, bound: true, shortcutsEnabled: false)
expect(!typed.swallow && typed.launch == nil, "focused input receives assigned letters without launching")
expect(!releaseCaps().tap, "typing a chord in focused input does not replay Caps")
state.reset()
capsDown()
let changedContext = state.route(key: 79, down: false, repeated: false, bound: false,
                                 shortcutsEnabled: false)
expect(changedContext.tap, "context alone cannot swallow a standalone Caps gesture")
state.reset()
capsDown()
_ = state.route(key: 3, down: true, repeated: false, bound: true)
expect(state.route(key: 3, down: false, repeated: false, bound: false,
                   shortcutsEnabled: false).swallow,
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

let suite = "local.maxvoid.HyperCaps.tests"
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
expect(leftKey.swallow && leftKey.window == 123 && leftKey.launch == nil, "window keys win over App List bindings")
expect(state.route(key: 123, down: true, repeated: true, bound: false, windowKey: true).window == nil, "holding an arrow does not repeat the layout")
expect(state.route(key: 123, down: false, repeated: false, bound: false, windowKey: true).swallow, "window key release is consumed")
expect(state.route(key: 126, down: true, repeated: false, bound: false, windowKey: true).window == 126, "a second window key in the same hold acts")
_ = state.route(key: 126, down: false, repeated: false, bound: false, windowKey: true)
expect(state.route(key: 126, down: true, repeated: false, bound: false, windowKey: true).window == 126, "tapping ↑ twice while holding Caps acts twice")
_ = state.route(key: 126, down: false, repeated: false, bound: false, windowKey: true)
expect(!releaseCaps().tap, "window chords never toggle Caps Lock")
expect(!state.route(key: 123, down: true, repeated: false, bound: false, windowKey: true).swallow, "arrows pass through without Caps")
_ = state.route(key: 123, down: false, repeated: false, bound: false, windowKey: true)
capsDown()
expect(state.route(key: 123, down: true, repeated: false, bound: false, windowKey: true, folderSelectionActive: true, folderCount: 9).window == nil, "arrows navigate the folder list instead")
_ = releaseCaps()
state.reset()
capsDown()
expect(state.route(key: 123, down: true, repeated: false, bound: false, windowKey: true, otherModifier: true).window == nil, "Control/Option + Caps + arrow does nothing")
_ = releaseCaps()
state.reset()
capsDown()
expect(state.route(key: 24, down: true, repeated: false, bound: false, windowKey: true, shortcutsEnabled: false).window == nil, "no layout while recording or confirming")
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
// ← cycles 1/2 → 2/3 → 1/3 while the window stays where HyperCaps put it.
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
expect(windowKeys.key(for: .right) == 123 && windowKeys.key(for: .left) == unassignedKey, "taking another action's key leaves it unassigned")
windowKeys.clear(123)
expect(windowKeys.command(for: 123) == nil && windowKeys.key(for: .right) == unassignedKey, "clearing a key unassigns its action")
let windowKeysSuite = "local.maxvoid.HyperCaps.window-tests"
let windowKeysDefaults = UserDefaults(suiteName: windowKeysSuite)!
windowKeysDefaults.removePersistentDomain(forName: windowKeysSuite)
expect(WindowShortcuts.load(from: windowKeysDefaults) == .defaults, "nothing saved loads the defaults")
windowKeys.save(to: windowKeysDefaults)
expect(WindowShortcuts.load(from: windowKeysDefaults) == windowKeys, "window shortcuts round-trip, including unassigned actions")
windowKeysDefaults.set(Data(#"{"center":40,"left":40}"#.utf8), forKey: WindowShortcuts.defaultsKey)
let partialKeys = WindowShortcuts.load(from: windowKeysDefaults)
expect(partialKeys.key(for: .left) == 40 && partialKeys.key(for: .center) == unassignedKey && partialKeys.key(for: .up) == 126,
       "missing actions keep defaults and a repeated key stays with one action")
windowKeysDefaults.set(Data("junk".utf8), forKey: WindowShortcuts.defaultsKey)
expect(WindowShortcuts.load(from: windowKeysDefaults) == .defaults, "unreadable window shortcuts load the defaults")
windowKeysDefaults.removePersistentDomain(forName: windowKeysSuite)
print("PASS: window layout routing, halves, height/maximize, restore, resize, displays")
