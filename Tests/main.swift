import Foundation
func expect(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
var state = KeyboardState()
func capsDown() { _ = state.route(key: 79, down: true, repeated: false, bound: false) }
func releaseCaps() -> KeyboardState.Result { state.route(key: 79, down: false, repeated: false, bound: false) }
expect(!state.route(key: 3, down: true, repeated: false, bound: true).swallow, "normal typing passes")
expect(!releaseCaps().tap, "orphan release is ignored")
capsDown()
expect(releaseCaps().tap, "standalone release switches input")
capsDown()
_ = state.route(key: 79, down: true, repeated: true, bound: false)
expect(releaseCaps().tap && !releaseCaps().tap, "holding/repeating Caps switches input only once on release")
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

for key in [UInt16(36), 76] {
    for capsReleasedFirst in [false, true] {
        state.reset()
        capsDown()
        let opening = state.route(key: key, down: true, repeated: false, bound: true)
        expect(opening.showFolders && opening.swallow && opening.launch == nil, "Caps Enter opens folders and overrides app assignment")
        let repeated = state.route(key: key, down: true, repeated: true, bound: true, folderSelectionActive: true)
        expect(repeated.swallow && !repeated.showFolders && !repeated.openFolderSelection, "opening Enter repeats cannot open the selection")
        if capsReleasedFirst { expect(!releaseCaps().tap, "Caps released first never switches input") }
        let keyUp = state.route(key: key, down: false, repeated: false, bound: true, folderSelectionActive: true)
        expect(keyUp.swallow && !keyUp.showFolders, "opening Enter release is consumed")
        if !capsReleasedFirst { expect(!releaseCaps().tap, "Enter released first never switches input") }
        expect(!state.route(key: key, down: true, repeated: false, bound: true).swallow, "Enter without Caps remains normal")
    }
}
// Opening the panel never counts as selection input, in either release order.
for key in [UInt16(36), 76] {
    for capsReleasedFirst in [false, true] {
        state.reset()
        capsDown()
        _ = state.route(key: key, down: true, repeated: false, bound: false)
        if !capsReleasedFirst {
            _ = state.route(key: key, down: false, repeated: false, bound: false, folderSelectionActive: true)
        }
        let release = state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true)
        expect(!release.openFolderSelection && !release.tap, "opening then releasing without input leaves the panel open")
        if capsReleasedFirst {
            expect(state.route(key: key, down: false, repeated: false, bound: false, folderSelectionActive: true).swallow, "opening Enter release stays consumed after Caps release")
        }
    }
}
for key in [UInt16(18), 0, 125, 126, 123, 124] {
    state.reset()
    capsDown()
    _ = state.route(key: 36, down: true, repeated: false, bound: false)
    _ = state.route(key: 36, down: false, repeated: false, bound: false, folderSelectionActive: true)
    _ = state.route(key: key, down: true, repeated: false, bound: true, folderSelectionActive: true)
    _ = state.route(key: key, down: false, repeated: false, bound: true, folderSelectionActive: true)
    let release = state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true)
    expect(release.openFolderSelection && !release.tap, "number, letter, or arrow input arms opening on Caps release")
    capsDown()
    expect(!state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true).openFolderSelection, "selection intent does not carry into another Caps hold")
}
for key in [UInt16(0), 125] {
    state.reset()
    capsDown()
    _ = state.route(key: key, down: false, repeated: false, bound: false, folderSelectionActive: true)
    state.modifierChanged(otherModifier: false, commandModifier: true)
    expect(!state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true).openFolderSelection, "key releases and modifiers do not count as selection input")
}
state.reset()
capsDown()
_ = state.route(key: 125, down: true, repeated: false, bound: false, otherModifier: true, folderSelectionActive: true)
expect(!state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true).openFolderSelection, "Control/Option navigation does not arm selection")
state.reset()
print("PASS: idle folder panel stays open, navigation arms Caps release, intent resets between holds")
for commandFirst in [false, true] {
    state.reset()
    _ = state.route(key: 79, down: true, repeated: false, bound: false, commandModifier: commandFirst)
    if !commandFirst {
        expect(!state.modifierChanged(otherModifier: false, commandModifier: true).showFolders, "Caps Command no longer opens folders")
    }
    let release = releaseCaps()
    expect(!release.showFolders && !release.tap, "Command Caps has no folder or input action")
}
state.reset()
capsDown()
_ = state.route(key: 11, down: true, repeated: false, bound: false)
expect(!state.route(key: 36, down: true, repeated: false, bound: false).showFolders, "ordinary key before Enter cancels folder gesture")
expect(!releaseCaps().tap, "cancelled gesture cannot switch input")
for command in [false, true] {
    state.reset()
    _ = state.route(key: 79, down: true, repeated: false, bound: false, otherModifier: !command, commandModifier: command)
    expect(!state.route(key: 36, down: true, repeated: false, bound: false, otherModifier: !command, commandModifier: command).showFolders, "modified Caps Enter cannot open folders")
    expect(!releaseCaps().tap, "modified gesture cannot switch input")
}
state.reset()
capsDown()
state.reset()
expect(!state.route(key: 36, down: true, repeated: false, bound: false).showFolders, "pause clears pending Caps Enter")
expect(!releaseCaps().tap, "pause clears release action")
print("PASS: Caps Enter and keypad Enter, repeats, both release orders, cancellation, removed Caps Command")
state.reset()
capsDown()
expect(state.route(key: 36, down: true, repeated: false, bound: false).showFolders, "open panel while Caps held")
let arrow = state.route(key: 125, down: true, repeated: false, bound: true, folderSelectionActive: true)
expect(!arrow.swallow && arrow.launch == nil, "held Caps lets panel selection keys through even if bound")
let folderRelease = state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true)
expect(folderRelease.openFolderSelection && !folderRelease.tap && !folderRelease.showFolders, "Caps release confirms folder selection after navigation")
expect(!state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true).openFolderSelection, "orphan release cannot confirm again")
capsDown()
let panelTap = state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true)
expect(!panelTap.openFolderSelection && !panelTap.tap, "Caps without selection input leaves the panel open without switching input")
capsDown()
let closedPanelRelease = releaseCaps()
expect(!closedPanelRelease.openFolderSelection && closedPanelRelease.tap, "outside panel Caps retains input switching")
print("PASS: Caps release opens folder selection, navigation passthrough, no input switch, no duplicate confirmation")

for (number, key) in [UInt16(18), 19, 20, 21, 23, 22, 26, 28, 25].enumerated() {
    state.reset()
    capsDown()
    let shortcut = state.route(key: key, down: true, repeated: false, bound: true, folderSelectionActive: true)
    expect(shortcut.swallow && shortcut.folderNumber == number && shortcut.launch == nil && !shortcut.openFolderSelection, "Caps number selects folder instead of launching a bound app")
    let repeated = state.route(key: key, down: true, repeated: true, bound: true, folderSelectionActive: true)
    expect(repeated.swallow && repeated.folderNumber == nil, "folder shortcut repeats are consumed")
    let release = state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true)
    expect(release.openFolderSelection && !release.tap, "Caps release opens the numbered selection")
    expect(!state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true).openFolderSelection, "numbered selection opens only once on Caps release")
    expect(state.route(key: key, down: false, repeated: false, bound: true).swallow, "folder shortcut release is consumed even after panel closes")
}
state.reset()
capsDown()
for key in [UInt16(18), 25, 20] {
    let move = state.route(key: key, down: true, repeated: false, bound: true, folderSelectionActive: true)
    expect(move.folderNumber != nil && !move.openFolderSelection, "multiple numbers can change selection during one Caps hold")
    let keyUp = state.route(key: key, down: false, repeated: false, bound: true, folderSelectionActive: true)
    expect(keyUp.swallow && !keyUp.openFolderSelection, "releasing a number does not open the folder")
}
expect(state.route(key: 79, down: false, repeated: false, bound: false, folderSelectionActive: true).openFolderSelection, "only Caps release confirms the final selection")
state.reset()
expect(state.route(key: 18, down: true, repeated: false, bound: false, commandModifier: true, folderSelectionActive: true).folderNumber == nil, "Command number no longer selects a folder")
capsDown()
let appNumber = state.route(key: 18, down: true, repeated: false, bound: true)
expect(appNumber.launch == 18 && appNumber.folderNumber == nil, "Caps number outside folder panel still launches its assigned app")
state.reset()
print("PASS: Caps folder numbers 1–9, repeat/release consumption, no duplicate opening, app shortcut isolation")

for commandFirst in [false, true] {
    state.reset()
    capsDown()
    _ = state.route(key: 36, down: true, repeated: false, bound: false)
    _ = state.route(key: 36, down: false, repeated: false, bound: false)
    if commandFirst { state.modifierChanged(otherModifier: false, commandModifier: true) }
    let letter = state.route(key: 0, down: true, repeated: false, bound: true, commandModifier: true, folderSelectionActive: true)
    expect(!letter.swallow && letter.stripCommandModifier && letter.launch == nil, "Command-held Caps letters reach folder type selection as plain typing")
    let letterUp = state.route(key: 0, down: false, repeated: false, bound: true, commandModifier: true, folderSelectionActive: true)
    expect(!letterUp.swallow && letterUp.stripCommandModifier, "navigation letter release also removes Command")
    let number = state.route(key: 20, down: true, repeated: false, bound: true, commandModifier: true, folderSelectionActive: true)
    expect(number.swallow && number.folderNumber == 2 && !number.openFolderSelection, "Command-held Caps number selects without opening")
    let release = state.route(key: 79, down: false, repeated: false, bound: false, commandModifier: true, folderSelectionActive: true)
    expect(release.openFolderSelection && !release.tap, "Caps release confirms even with Command still held")
    let ordinaryCommand = state.route(key: 0, down: true, repeated: false, bound: false, commandModifier: true, folderSelectionActive: true)
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
expect(FolderOrder.move(&ordered, path: "/tmp/0", to: 4) == 3, "drag first folder to end")
expect(ordered.map { $0.path } == ["/tmp/1", "/tmp/2", "/tmp/3", "/tmp/0"], "downward drop adjusts insertion boundary")
expect(FolderOrder.move(&ordered, path: "/tmp/0", to: 0) == 0, "drag last folder to beginning")
expect(ordered.map { $0.path } == ["/tmp/0", "/tmp/1", "/tmp/2", "/tmp/3"], "upward drop preserves other rows")
expect(FolderOrder.move(&ordered, path: "/tmp/1", to: 2) == 1, "drop beside same row keeps order")
expect(FolderOrder.move(&ordered, path: "/missing", to: 0) == nil, "unknown dragged folder is rejected")
expect(FolderOrder.move(&ordered, path: "/tmp/0", to: 5) == nil, "invalid drop boundary is rejected")
let savedOrder = try JSONDecoder().decode([FolderEntry].self, from: JSONEncoder().encode(ordered))
expect(savedOrder.map { $0.path } == ordered.map { $0.path }, "custom order persists")
print("PASS: folder drag order, boundary validation, persisted order")

var groupOrder = (0..<6).map { FolderEntry(name: "Folder \($0)", path: "/tmp/\($0)") }
expect(FolderOrder.move(&groupOrder, paths: ["/tmp/3", "/tmp/1"], to: 6) == IndexSet(integersIn: 4..<6), "multi-row drop selects moved block")
expect(groupOrder.map { $0.path } == ["/tmp/0", "/tmp/2", "/tmp/4", "/tmp/5", "/tmp/1", "/tmp/3"], "noncontiguous drag keeps original relative order")
expect(FolderOrder.move(&groupOrder, paths: ["/tmp/1", "/tmp/3"], to: 0) == IndexSet(integersIn: 0..<2), "multi-row drag upward")
expect(groupOrder.map { $0.path } == ["/tmp/1", "/tmp/3", "/tmp/0", "/tmp/2", "/tmp/4", "/tmp/5"], "group moves to start")
expect(FolderOrder.move(&groupOrder, paths: ["/tmp/1", "/tmp/3"], to: 1) == IndexSet(integersIn: 0..<2), "drop inside selected block keeps group in place")
let beforeInvalidDrop = groupOrder.map { $0.path }
expect(FolderOrder.move(&groupOrder, paths: ["/tmp/1", "/missing"], to: 2) == nil, "partly invalid group is rejected")
expect(FolderOrder.move(&groupOrder, paths: [], to: 0) == nil, "empty group is rejected")
expect(groupOrder.map { $0.path } == beforeInvalidDrop, "invalid group drop leaves list unchanged")
print("PASS: multiple folder drag, stable ordering, selection, invalid group rejection")
