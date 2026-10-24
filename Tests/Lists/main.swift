import Cocoa
import IOKit.hidsystem

func expect(_ value: Bool, _ message: String) {
    if !value { fatalError(message) }
}

// Exercise the same ordering policy used by Accessibility, without moving real windows.
var windowOrder = ApplicationWindowOrder<Int>()
func nextWindow(_ pid: pid_t, _ available: [Int], _ focused: Int?, cycle: Bool = true) -> Int? {
    windowOrder.next(processID: pid, available: available, focused: focused, cycle: cycle, equals: ==)
}
expect(nextWindow(101, [1, 2, 3], 1, cycle: false) == nil, "first activation does not advance")
expect(nextWindow(101, [1, 2, 3], 1) == 2, "advance to second window")
expect(nextWindow(101, [2, 1, 3], 2) == 3, "front-to-back reordering does not bounce between two windows")
expect(nextWindow(101, [3, 2, 1], 3) == 1, "three windows wrap around")
expect(nextWindow(101, [3, 1, 4], 1) == 3, "closed windows are removed")
expect(nextWindow(101, [3, 1, 4], 3) == 4, "new windows join the cycle")
expect(nextWindow(101, [4], 4) == nil, "a single eligible window stays focused")
expect(nextWindow(101, [], nil) == nil, "no eligible windows is harmless")
expect(nextWindow(202, [10, 11, 12], 10, cycle: false) == nil, "another mapped app activates without cycling")
expect(nextWindow(202, [10, 11, 12], 10) == 11, "another mapped app also cycles")
expect(nextWindow(303, [20, 21], 20) == 21, "manually focused app can cycle immediately")
expect(nextWindow(202, [12, 11, 10], 12) == 11, "changing apps resets stale ordering")
expect(nextWindow(202, [10, 12, 11], 10, cycle: false) == nil, "reactivation refreshes ordering")
expect(nextWindow(202, [11, 10, 12], 10) == 12, "refreshed ordering is retained")
expect(nextWindow(202, [10, 11], 99) == nil, "unknown focused window does not select an unrelated one")
expect(nextWindow(202, [10, 11], nil) == nil, "missing focused window is harmless")
// Finder: focus on the desktop (not a listed window) returns to the frontmost window.
var finderOrder = ApplicationWindowOrder<Int>()
func nextFinderWindow(_ available: [Int], _ focused: Int?, cycle: Bool = true) -> Int? {
    finderOrder.next(processID: 404, available: available, focused: focused, cycle: cycle,
                     frontWhenUnfocused: true, equals: ==)
}
expect(nextFinderWindow([30], nil, cycle: false) == nil, "Finder's first activation does not advance")
expect(nextFinderWindow([30], nil) == 30, "from the desktop, the only Finder window is raised")
expect(nextFinderWindow([30], 30) == nil, "a single focused Finder window stays focused, never the desktop")
expect(nextFinderWindow([31, 30], 99) == 31, "from the desktop, the frontmost of several windows is raised")
expect(nextFinderWindow([31, 30], 31) == 30, "Finder windows then cycle as usual")
expect(nextFinderWindow([30, 31], 30) == 31, "and keep their stable order")
expect(nextFinderWindow([], nil) == nil, "no Finder windows is harmless")
print("PASS: app-independent window cycling, stable order, wraparound, window changes, app changes, Finder desktop")

// Construct views without running AppDelegate's startup or touching saved preferences.
_ = NSApplication.shared
let owner = AppDelegate()
// Inspect replay events without posting input or changing system keyboard state.
let replay = try CapsReplay.events()
expect(replay.count == 2, "standalone replay contains a press and release")
for (event, transition) in zip(replay, [NX_KEYDOWN, NX_KEYUP]) {
    let native = NSEvent(cgEvent: event)!
    expect(native.type == .systemDefined && native.subtype.rawValue == NX_SUBTYPE_AUX_CONTROL_BUTTONS,
           "Caps replay uses auxiliary system-key events")
    expect((native.data1 >> 16) == NX_KEYTYPE_CAPS_LOCK, "Caps replay targets the system Caps key")
    expect(((native.data1 >> 8) & 0xff) == transition && native.data1 & 0xff == 0,
           "Caps replay has ordered, non-repeating transitions")
    expect(event.getIntegerValueField(.eventSourceUserData) == CapsReplay.marker,
           "replayed events identify themselves")
}
_ = owner.state.route(key: 79, down: true, repeated: false, bound: false)
let echoedEvent = CGEvent(keyboardEventSource: nil, virtualKey: 57, keyDown: true)!
echoedEvent.setIntegerValueField(.eventSourceUserData, value: CapsReplay.marker)
expect(owner.handle(.keyDown, echoedEvent)?.takeUnretainedValue() === echoedEvent,
       "replayed Caps passes through the event tap")
expect(owner.state.held && !owner.state.chord, "replay cannot cancel a subsequent physical Caps gesture")
owner.state.reset()
print("PASS: Caps system-key replay encoding, matching release, event-tap bypass")
owner.bindings = [AppShortcut(keys: [3], name: "Example", path: "/Applications/Example.app", bundleID: nil)]
owner.folders = [FolderEntry(name: "First", path: "/tmp"), FolderEntry(name: "Second", path: "/")]
let preferences = owner.makeFoldersContent(size: AppDelegate.preferenceSize, presentation: .preferences)
let picker = owner.makeFoldersContent(size: AppDelegate.preferenceSize)
let preferencesTable = preferences.controller.table
let pickerTable = picker.controller.table
preferencesTable.reloadData()
pickerTable.reloadData()
preferencesTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
pickerTable.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
expect(preferencesTable.selectedRow == 0 && pickerTable.selectedRow == 1, "folder views retain independent selections")
expect(preferencesTable.dataSource === preferences.controller, "preferences retains its own table data source")
expect(pickerTable.dataSource === picker.controller, "picker retains its own table data source")
expect(preferences.controller.tableView(preferencesTable, rowViewForRow: 0) is InsetListRowView, "preferences shares the picker selection style")
expect(picker.controller.tableView(pickerTable, rowViewForRow: 0) is InsetListRowView, "picker keeps inset row style")
for (controller, expectedHint) in [(preferences.controller, false), (picker.controller, true)] {
    let table = controller.table
    let cell = controller.tableView(table, viewFor: table.tableColumns[1], row: 0)!
    let labels = cell.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
    expect(labels.contains("⇪1") == expectedHint, "only picker rows show Caps number hints")
    expect(controller.tableView(table, typeSelectStringFor: nil, row: 1) == "Second", "folder type selection uses display names")
}
// Preferences > Folders: App List's shortcut fields; the path shows when pointing at a folder.
expect(preferencesTable.tableColumns.map { $0.title } == ["Name", "Shortcut"], "Folders preferences show shortcut fields, not paths")
let pickerNameCell = picker.controller.tableView(pickerTable, viewFor: pickerTable.tableColumns[0], row: 0)!
expect(pickerNameCell.toolTip == "/tmp", "the picker shows the path only when pointing at a folder")
expect(!picker.controller.tableView(pickerTable, viewFor: pickerTable.tableColumns[1], row: 0)!.subviews
        .contains { ($0 as? NSTextField)?.stringValue.contains("/") == true }, "picker rows show no path")
let folderNameCell = preferences.controller.tableView(preferencesTable, viewFor: preferencesTable.tableColumns[0], row: 0)!
expect(folderNameCell.toolTip == "/tmp", "pointing at a folder shows its path")
func folderRecorder(_ row: Int) -> KeyRecorder {
    preferences.controller.tableView(preferencesTable, viewFor: preferencesTable.tableColumns[1], row: row)!
        .subviews.compactMap { $0 as? KeyRecorder }.first!
}
expect(folderRecorder(0).title == "Record Shortcut" && folderRecorder(0).maxKeys == 3, "folders record up to three keys")
expect(owner.assignShortcut([2, 13], to: .folder(path: owner.folders[0].path), recorder: folderRecorder(0))
       && owner.folders[0].keys == [2, 13], "a folder takes ⇪D W")
expect(folderRecorder(0).title == "⇪D W", "the folder's field shows its shortcut")
expect(owner.shortcutConflicts([2, 13], for: .folder(path: "/")).inUse == ["⇪D W already opens First."], "folder shortcuts conflict like app shortcuts")
expect(owner.shortcutConflicts([2, 13], for: .app(path: "/Applications/Example.app")).owners == [.folder(path: "/tmp")],
       "an app and a folder cannot share a shortcut")
expect(owner.shortcutConflicts([2, 13], for: .folder(path: "/tmp")).owners.isEmpty
       && owner.shortcutConflicts([2], for: .folder(path: "/")).owners.isEmpty, "only the exact keys conflict")
expect(owner.folders[0].extends([2]) && !owner.folders[0].extends([2, 13]) && owner.folders[0].matches([2, 13]),
       "⇪D starts ⇪D W")
expect(owner.shortcutConflicts([2], for: .window(.center)).owners == [.folder(path: "/tmp")],
       "a window action on D would take the folder's shortcut")
folderRecorder(0).onClear?()
expect(owner.folders[0].keys.isEmpty && folderRecorder(0).title == "Record Shortcut", "✕ clears a folder shortcut")
// Edit… changes only the name Clutch shows, never the folder.
func folderNames(_ row: Int) -> [String] {
    preferences.controller.tableView(preferencesTable, viewFor: preferencesTable.tableColumns[0], row: row)!
        .subviews.compactMap { ($0 as? NSTextField)?.stringValue }
}
expect(owner.folders[0].originalName == FileManager.default.displayName(atPath: "/tmp") && owner.folders[0].isRenamed,
       "a folder knows its own name, and that First is a new one")
owner.updateFolder(path: "/tmp", name: "  Scratch ")
expect(owner.folders[0].name == "Scratch" && folderNames(0) == ["Scratch"], "Edit renames a folder in the list")
owner.updateFolder(path: "/tmp", name: "")
expect(owner.folders[0].name == owner.folders[0].originalName && !owner.folders[0].isRenamed,
       "an empty name goes back to the folder's own name")
// While Name is empty, its gray placeholder is the name of the folder Location names.
let namePlaceholder = AppDelegate.folderFields(name: "", location: "")[0].placeholder
expect(namePlaceholder?(["", "/tmp/"]) == FileManager.default.displayName(atPath: "/tmp")
       && namePlaceholder?(["", ""]) == "" && namePlaceholder?(["", "/no/such/folder"]) == "",
       "an empty name shows the folder's own name in gray")
expect(AppDelegate.folderFields(name: "", location: "")[1].placeholder == nil, "Location has no placeholder")
// Edit… can also move an entry to another folder; the shortcut stays, and a folder still
// showing its own name takes the new one's.
let movedFolder = FileManager.default.temporaryDirectory.appendingPathComponent("ClutchMovedFolder").standardizedFileURL.path
try? FileManager.default.createDirectory(atPath: movedFolder, withIntermediateDirectories: true)
owner.folders[0].keys = [2]
owner.updateFolder(path: "/tmp", name: owner.folders[0].name, location: "  \(movedFolder)/ ")
expect(owner.folders[0].path == movedFolder && owner.folders[0].name == "ClutchMovedFolder" && owner.folders[0].keys == [2],
       "Edit changes a folder's location and keeps its shortcut")
owner.updateFolder(path: movedFolder, name: "Moved", location: "/tmp")
expect(owner.folders[0].path == URL(fileURLWithPath: "/tmp").standardizedFileURL.path && owner.folders[0].name == "Moved",
       "a renamed folder keeps its name when it moves")
owner.folders[0].path = "/tmp"; owner.folders[0].keys = []
try? FileManager.default.removeItem(atPath: movedFolder)
// + uses the same Name and Location sheet; a folder already listed is selected instead.
expect(AppDelegate.folderFields(name: "", location: "").map { $0.label } == ["Name", "Location"]
       && AppDelegate.folderFields(name: "", location: "")[1].choosesFolder, "Add and Edit Folder share Name and Location, with Choose…")
let addedFolder = FileManager.default.temporaryDirectory.appendingPathComponent("ClutchAddedFolder").standardizedFileURL.path
try? FileManager.default.createDirectory(atPath: addedFolder, withIntermediateDirectories: true)
owner.addFolder(name: "", location: "/tmp/", to: preferences.controller)
expect(owner.folders.count == 2 && preferencesTable.selectedRowIndexes == IndexSet(integer: 0), "adding a folder already listed selects it")
owner.addFolder(name: "", location: addedFolder, to: preferences.controller)
expect(owner.folders.count == 3 && owner.folders[2].name == "ClutchAddedFolder"
       && preferencesTable.selectedRowIndexes == IndexSet(integer: 2), "an added folder without a name uses its own")
owner.folders.removeLast()
owner.addFolder(name: " Added ", location: addedFolder, to: preferences.controller)
expect(owner.folders.last?.name == "Added" && owner.folders.last?.path == addedFolder, "a folder can be added with a name")
owner.folders.removeLast(); owner.saveFolders()
try? FileManager.default.removeItem(atPath: addedFolder)
expect(!pickerTable.focusesOnRightClick && preferencesTable.focusesOnRightClick,
       "a right-click in the picker leaves focus in its search field")
owner.folders[0].name = "First"; owner.folders[1].name = "Second"
preferencesTable.reloadData(); pickerTable.reloadData()
let oldFolders = try! JSONDecoder().decode([FolderEntry].self, from: Data(#"[{"name":"Old","path":"/old"}]"#.utf8))
expect(oldFolders[0].keys.isEmpty, "a folder saved without a shortcut loads")
let savedFolder = FolderEntry(name: "Saved", path: "/saved", keys: [2, 13])
let savedFolderJSON = String(decoding: try! JSONEncoder().encode([savedFolder, oldFolders[0]]), as: UTF8.self)
expect(savedFolderJSON.contains(#""shortcut":[2,13]"#) && savedFolderJSON.components(separatedBy: "shortcut").count == 2,
       "folder shortcuts are saved under \"shortcut\", and left out when empty")
expect(try! JSONDecoder().decode([FolderEntry].self, from: JSONEncoder().encode([savedFolder])) == [savedFolder],
       "folder shortcuts round-trip")
print("PASS: folder shortcut fields")
// Folders search: the field filters the picker by name or path and selects the best match.
let search = picker.controller
let searchField = NSSearchField()
search.searchField = searchField
let fieldEditor = NSTextView()
func typeSearch(_ text: String) {
    searchField.stringValue = text
    search.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
}
expect(!pickerTable.allowsTypeSelect && preferencesTable.allowsTypeSelect, "only the picker replaces type selection with search")
typeSearch("Se")
expect(search.filter == "Se" && pickerTable.numberOfRows == 1 && search.folderIndex(forRow: 0) == 1,
       "the search keeps folders whose name matches, ignoring case")
expect(pickerTable.selectedRow == 0 && search.selectedFolderIndices == IndexSet(integer: 1), "the first match is selected and maps to its folder")
let firstCell = search.tableView(pickerTable, viewFor: pickerTable.tableColumns[0], row: 0)!
expect(firstCell.subviews.compactMap { ($0 as? NSTextField)?.stringValue }.contains("Second"), "filtered rows show their own folder")
typeSearch("tmp")
expect(pickerTable.numberOfRows == 0, "paths do not match")
typeSearch("nothing here")
expect(pickerTable.numberOfRows == 0 && search.selectedFolderIndices.isEmpty, "no matches selects nothing")
expect(search.control(searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
       && search.filter.isEmpty && searchField.stringValue.isEmpty && pickerTable.numberOfRows == 2,
       "Escape clears the search first")
expect(search.control(searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.moveDown(_:)))
       && pickerTable.selectedRow == 1, "↓ in the field moves the list selection")
expect(search.control(searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.moveDown(_:)))
       && pickerTable.selectedRow == 1, "↓ stops at the last row")
expect(search.control(searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.moveUp(_:)))
       && pickerTable.selectedRow == 0, "↑ in the field moves the list selection")
expect(!search.control(searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.deleteBackward(_:))),
       "editing commands stay with the field")
search.setFilter("Fi")
expect(searchField.stringValue == "Fi", "setting the filter updates the field")
search.setFilter("")
search.jumpToFolder(key: 1, time: 10) // S
expect(pickerTable.selectedRow == 1 && pickerTable.numberOfRows == 2 && search.filter.isEmpty && searchField.stringValue.isEmpty,
       "Caps S jumps to Second without filtering or typing into search")
search.jumpToFolder(key: 14, time: 10.1) // E
expect(pickerTable.selectedRow == 1 && pickerTable.numberOfRows == 2, "nearby Caps letters refine the jump")
search.jumpToFolder(key: 3, time: 12) // F
expect(pickerTable.selectedRow == 0, "a later Caps letter starts a new jump")
search.resetCapsJump()
search.jumpToFolder(key: 1, time: 12.1)
expect(pickerTable.selectedRow == 1 && search.filter.isEmpty, "a new Caps gesture resets the jump text")
typeSearch("Fi")
expect(pickerTable.numberOfRows == 1 && search.filter == "Fi", "ordinary search still filters after Caps navigation")
search.setFilter("")
search.searchField = nil
print("PASS: Folders search field filters by name, maps rows, Escape/arrows")
let ranked = [FolderEntry(name: "Kidocs", path: "/k"), FolderEntry(name: "Project Docs", path: "/p"),
              FolderEntry(name: "Downloads", path: "/d"), FolderEntry(name: "Photo Dump", path: "/docs/x"),
              FolderEntry(name: "Docker", path: "/r")]
expect(FolderListController.ordered(ranked, query: "doc") == [1, 4, 0],
       "word starts first (in list order), then names containing it; paths never match")
expect(FolderListController.ordered(ranked, query: "pd") == [1, 3],
       "initials of separate words match after word starts")
expect(FolderListController.ordered(ranked, query: "d") == [1, 2, 3, 4, 0], "one letter matches word starts first")
expect(FolderListController.ordered([FolderEntry(name: "MyProject", path: "/m"), FolderEntry(name: "Résumé", path: "/r")], query: "proj") == [0],
       "camel-case humps start words")
expect(FolderListController.ordered([FolderEntry(name: "Résumé", path: "/r")], query: "resu") == [0], "accents are ignored")
let chinese = [FolderEntry(name: "下载", path: "/x"), FolderEntry(name: "文件夹", path: "/w"),
               FolderEntry(name: "我的文档", path: "/d")]
expect(FolderListController.ordered(chinese, query: "wenjian") == [1], "pinyin syllables match Chinese names")
expect(FolderListController.ordered(chinese, query: "wen'jian") == [1] && FolderListController.ordered(chinese, query: "wen jian") == [1],
       "the input method's apostrophes and spaces are ignored")
expect(FolderListController.ordered(chinese, query: "jian") == [1], "any syllable starts a word")
expect(FolderListController.ordered(chinese, query: "wjj") == [1], "syllable initials match")
expect(FolderListController.ordered(chinese, query: "w").first == 1 || FolderListController.ordered(chinese, query: "w").first == 2,
       "one letter matches syllable starts")
expect(FolderListController.ordered(chinese, query: "文件") == [1], "Chinese characters still match directly")
print("PASS: Folders search ranks word starts, initials, then contains")

let applications = ApplicationListController(owner: owner)
owner.configureList(applications.table, width: AppDelegate.preferenceSize.width, title: "Application")
applications.table.reloadData()
// Deliberately give the coordinator another table. Cell callbacks must use their origin.
owner.applicationList = ApplicationListController(owner: owner)
let cell = applications.tableView(applications.table, viewFor: applications.table.tableColumns[1], row: 0)!
let recorder = cell.subviews.compactMap { $0 as? KeyRecorder }.first!
_ = owner.state.route(key: 79, down: true, repeated: false, bound: false)
recorder.onStart?()
expect(owner.state.held, "recording preserves standalone Caps")
expect(owner.state.route(key: 79, down: false, repeated: false, bound: false, input: .inactive).tap,
       "standalone Caps still replays after recording begins")
expect(applications.table.selectedRow == 0, "recording selects the originating application table")
expect(owner.applicationList?.table.selectedRow == -1, "recording does not select a different table")
expect(recorder.title == "⇪F", "assigned key label is preserved")
let header = PlainListHeaderView(frame: NSRect(x: 0, y: 0, width: 460, height: 28))
header.tableView = applications.table
header.layout()
expect(!cell.subviews.contains { $0 is NSTextField }, "the shortcut field includes Caps; there is no separate label")
let detailColumn = applications.table.frameOfCell(atColumn: 1, row: 0)
expect(abs(header.secondLabel.frame.minX + ListGeometry.labelTextInset - (detailColumn.minX + recorder.frame.minX)) < 0.01,
       "shortcut header text lines up with the left edge of the shortcut fields")
for (content, controller) in [(preferences.content, preferences.controller), (picker.content, picker.controller)] {
    let scroll = content.subviews.compactMap { $0 as? ListScrollView }.first!
    let isPicker = controller.presentation == .picker
    expect(scroll.fitsTableToViewport == isPicker, "only picker columns fit the viewport")
    expect(content.subviews.contains { $0 is PlainListHeaderView } == !isPicker,
           "only preferences has a header")
}
expect(owner.assignShortcut([46, 46], to: .app(path: owner.bindings[0].path), recorder: recorder) && owner.bindings[0].keys == [46, 46], "Caps + M + M uses the same key twice")
expect(!owner.assignShortcut([46, KeyCode.space], to: .app(path: owner.bindings[0].path), recorder: recorder), "Space stays reserved as a second key")
expect(!owner.assignShortcut([46, 13, KeyCode.space], to: .app(path: owner.bindings[0].path), recorder: recorder), "Space stays reserved as a third key")
expect(!owner.assignShortcut([46, KeyCode.delete], to: .app(path: owner.bindings[0].path), recorder: recorder), "Delete is reserved for editing a recording")
expect(!owner.assignShortcut([46, KeyCode.returnKey], to: .app(path: owner.bindings[0].path), recorder: recorder), "Return is reserved for confirming")
expect(!owner.assignShortcut([KeyCode.keypadEnter], to: .app(path: owner.bindings[0].path), recorder: recorder), "Enter is reserved for confirming")
expect(!owner.assignShortcut([46, 13, 14, 7], to: .app(path: owner.bindings[0].path), recorder: recorder), "a shortcut has at most three keys")
expect(owner.assignShortcut([46, 13], to: .app(path: owner.bindings[0].path), recorder: recorder)
       && owner.bindings[0].keys == [46, 13], "Caps + M + W is assigned without asking")
let comboCell = applications.tableView(applications.table, viewFor: applications.table.tableColumns[1], row: 0)!
expect(comboCell.subviews.compactMap { $0 as? KeyRecorder }.first?.title == "⇪M W", "two-key shortcuts show both keys")
expect(owner.assignShortcut([46, 13, 14], to: .app(path: owner.bindings[0].path), recorder: recorder)
       && owner.bindings[0].keys == [46, 13, 14], "Caps + M + W + E is assigned")
let tripleCell = applications.tableView(applications.table, viewFor: applications.table.tableColumns[1], row: 0)!
expect(tripleCell.subviews.compactMap { $0 as? KeyRecorder }.first?.title == "⇪M W E", "three-key shortcuts show all three keys")
expect(owner.assignShortcut([46, 13], to: .app(path: owner.bindings[0].path), recorder: recorder) && owner.bindings[0].keys == [46, 13], "assigning two keys clears the third key")
expect(owner.assignShortcut([3], to: .app(path: owner.bindings[0].path), recorder: recorder) && owner.bindings[0].keys == [3], "assigning one key clears the second key")
// Recording as used: Caps held, T then H, Caps released.
recorder.recording = true
expect(recorder.prompt == (owner.tap == nil ? "Turn on Clutch" : "Hold ⇪ to start…"), "the prompt depends on whether Clutch can see Caps")
recorder.capsAvailable = { true } // As if Clutch were enabled.
expect(recorder.prompt == "Hold ⇪ to start…", "the field asks to hold ⇪")
expect(recorder.maxKeys == 3, "App List records up to three keys")
recorder.capsPressed()
expect(recorder.title == "⇪…", "pressing Caps shows the field is listening")
recorder.capsReleased()
expect(recorder.recording, "releasing Caps alone records nothing")
expect(recorder.title == recorder.prompt, "releasing Caps alone shows the prompt again")
recorder.capsPressed()
recorder.capsKeyPressed(17)
expect(recorder.title == "⇪T…", "the first Caps key waits for more keys")
recorder.capsKeyPressed(4)
expect(recorder.title == "⇪T H…", "the field shows both keys while Caps is held")
recorder.capsReleased()
expect(!recorder.recording && owner.bindings[0].keys == [17, 4], "releasing Caps saves Caps + T + H")
recorder.recording = true
recorder.capsKeyPressed(17)
recorder.capsReleased()
expect(owner.bindings[0].keys == [17], "one key then Caps release saves a one-key shortcut")
recorder.recording = true
recorder.capsKeyPressed(17)
recorder.capsKeyPressed(17)
expect(recorder.title == "⇪T T…", "the same key can be recorded twice")
recorder.capsReleased()
expect(owner.bindings[0].keys == [17, 17], "releasing Caps saves Caps + T + T")
recorder.recording = true
recorder.capsKeyPressed(17)
recorder.capsKeyPressed(4)
recorder.capsKeyPressed(14)
expect(recorder.title == "⇪T H E", "the field shows all three keys")
recorder.capsKeyPressed(7)
expect(recorder.title == "⇪T H E", "a fourth key is not recorded")
recorder.capsKeyPressed(KeyCode.delete)
expect(recorder.title == "⇪T H…", "Caps + Delete removes the last key")
recorder.capsKeyPressed(KeyCode.delete)
recorder.capsKeyPressed(KeyCode.delete)
expect(recorder.title == "⇪…", "Caps + Delete can remove every key")
recorder.capsKeyPressed(17)
recorder.capsKeyPressed(4)
recorder.capsKeyPressed(14)
recorder.capsReleased()
expect(!recorder.recording && owner.bindings[0].keys == [17, 4, 14], "releasing Caps saves Caps + T + H + E")
recorder.recording = true
recorder.capsPressed()
recorder.capsKeyPressed(KeyCode.returnKey)
expect(recorder.recording && recorder.title == "⇪…", "Caps + Return with no keys records nothing")
recorder.capsKeyPressed(17)
recorder.capsKeyPressed(4)
recorder.capsKeyPressed(KeyCode.returnKey)
expect(!recorder.recording && owner.bindings[0].keys == [17, 4], "Caps + T + H + Return saves Caps + T + H at once")
recorder.capsReleased()
expect(owner.bindings[0].keys == [17, 4], "releasing Caps after Return changes nothing")
let clearCell = applications.tableView(applications.table, viewFor: applications.table.tableColumns[1], row: 0)!
let clearRecorder = clearCell.subviews.compactMap { $0 as? KeyRecorder }.first!
expect(clearRecorder.hasShortcut && clearRecorder.onClear != nil, "a field with a shortcut offers ✕")
clearRecorder.onClear?()
expect(!owner.bindings[0].hasShortcut && owner.bindings[0].keys.isEmpty, "✕ clears the shortcut and keeps the app")
let emptyRecorder = applications.tableView(applications.table, viewFor: applications.table.tableColumns[1], row: 0)!
    .subviews.compactMap { $0 as? KeyRecorder }.first!
expect(emptyRecorder.title == "Record Shortcut" && !emptyRecorder.hasShortcut, "an empty field says Record Shortcut")
let legacy = try! JSONDecoder().decode([AppShortcut].self, from: Data(#"[{"key":3,"name":"Old","path":"/tmp/old"}]"#.utf8))
expect(legacy[0].keys == [3], "a one-key shortcut saved without secondKey / thirdKey loads")
let twoKeySave = try! JSONDecoder().decode([AppShortcut].self, from: Data(#"[{"key":46,"name":"Word","path":"/tmp/word","secondKey":13}]"#.utf8))
expect(twoKeySave[0].keys == [46, 13], "lists saved with two-key shortcuts still load")
expect(try! JSONDecoder().decode([AppShortcut].self, from: JSONEncoder().encode(twoKeySave)) == twoKeySave,
       "app shortcuts round-trip in the saved format")
let unassignedJSON = String(decoding: try! JSONEncoder().encode(AppShortcut(name: "None", path: "/none", bundleID: nil)), as: UTF8.self)
expect(unassignedJSON.contains(#""key":65535"#) && !unassignedJSON.contains("secondKey"), "no shortcut is saved as the unassigned key")
expect(try! JSONDecoder().decode(AppShortcut.self, from: Data(unassignedJSON.utf8)).keys.isEmpty, "the unassigned key loads as no shortcut")
// Caps release decides, so Caps + M and Caps + M + W can belong to different apps.
owner.bindings = [AppShortcut(keys: [46], name: "Mail", path: "/mail", bundleID: nil),
                  AppShortcut(keys: [46, 13], name: "Word", path: "/word", bundleID: nil),
                  AppShortcut(keys: [46, 46], name: "Messages", path: "/messages", bundleID: nil)]
let notes = ShortcutOwner.app(path: "/notes")
let comboConflicts = owner.shortcutConflicts([46, 13], for: notes)
expect(comboConflicts.owners == [.app(path: "/word")] && comboConflicts.inUse == ["⇪M W already opens Word."], "only the same shortcut conflicts")
expect(owner.shortcutConflicts([46], for: notes).owners == [.app(path: "/mail")], "Caps + M alone conflicts only with Caps + M")
expect(owner.shortcutConflicts([46, 7], for: notes).owners.isEmpty, "a new two-key shortcut can share its first key")
expect(owner.shortcutConflicts([46, 13, 14], for: notes).owners.isEmpty, "a three-key shortcut can extend a two-key one")
expect(owner.shortcutConflicts([46, 13], for: .app(path: "/word")).owners.isEmpty, "an app never conflicts with itself")
let windowConflicts = owner.shortcutConflicts([46], for: .window(.center))
expect(windowConflicts.owners == [.app(path: "/mail"), .app(path: "/word"), .app(path: "/messages")]
       && windowConflicts.inUse == ["⇪M already opens Mail.", "⇪M already starts Word (⇪M W) and Messages (⇪M M)."],
       "a window action takes the key alone and every two-key shortcut starting with it")
owner.bindings = []
expect(recorder.onKeys?([0]) == false, "a removed binding cannot be assigned from a stale cell")

var invoked = 0
let button = ListActionButton { invoked += 1 }
button.performClick(nil)
expect(invoked == 1, "list buttons invoke their explicit callback once")
weak var releasedController: FolderListController?
var retainedTable: FolderTableView?
do {
    let controller = FolderListController(owner: owner, presentation: .picker)
    releasedController = controller
    retainedTable = controller.table
}
expect(releasedController == nil, "table and action callbacks do not retain the folder controller")
retainedTable?.openSelection?() // A callback from a detached view is harmless.
// Exercise AppKit's actual tracking loop: a drag must keep the click selection,
// while Shift/Command clicks still use the native selection rules.
let trackingOwner = AppDelegate()
trackingOwner.bindings = (0..<4).map { AppShortcut(keys: [3], name: "Row \($0)", path: "/tmp/\($0)", bundleID: nil) }
let trackingController = ApplicationListController(owner: trackingOwner)
let trackingTable = trackingController.table
trackingOwner.configureList(trackingTable, width: 460, title: "Application")
let trackingWindow = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 460, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
trackingWindow.isReleasedWhenClosed = false
trackingTable.frame = NSRect(x: 0, y: 0, width: 460, height: 200)
trackingWindow.contentView = trackingTable
trackingWindow.orderFront(nil)
trackingTable.reloadData()
trackingWindow.layoutIfNeeded()
func trackClick(row: Int, dragTo: Int? = nil, modifiers: NSEvent.ModifierFlags = []) {
    func event(_ type: NSEvent.EventType, at row: Int) -> NSEvent {
        let point = trackingTable.convert(NSPoint(x: 30, y: trackingTable.rect(ofRow: row).midY), to: nil)
        return NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers,
                                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: trackingWindow.windowNumber,
                                  context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }
    NSApp.postEvent(event(.leftMouseDown, at: row), atStart: true)
    let down = NSApp.nextEvent(matching: .leftMouseDown, until: .distantPast, inMode: .default, dequeue: true)!
    if let dragTo { NSApp.postEvent(event(.leftMouseDragged, at: dragTo), atStart: false) }
    NSApp.postEvent(event(.leftMouseUp, at: dragTo ?? row), atStart: false)
    trackingTable.mouseDown(with: down)
}
trackClick(row: 0, dragTo: 3)
expect(trackingTable.selectedRowIndexes == IndexSet(integer: 0), "sweeping over rows does not select a range")
trackClick(row: 3, modifiers: .shift)
expect(trackingTable.selectedRowIndexes == IndexSet(integersIn: 0..<4), "Shift-click still selects a range")
trackClick(row: 1, modifiers: .command)
expect(trackingTable.selectedRowIndexes == IndexSet([0, 2, 3]), "Command-click still toggles an individual row")
trackingWindow.close()
print("PASS: list delegates, independent selections, row styles, shortcut hints, recording origin, stale cells, button callbacks, controller release")

for count in 0...5 {
    for mask in 0..<(1 << count) {
        var items = Array(0..<count)
        let selected = IndexSet(items.filter { mask & (1 << $0) != 0 })
        let removed = ListSelection.remove(selected, from: &items)
        expect(items == Array(0..<count).filter { !selected.contains($0) },
               "multi-delete preserves surviving order")
        expect(removed == !selected.isEmpty, "only a non-empty selection triggers a save")
    }
}
var unchanged = [0, 1]
expect(!ListSelection.remove(IndexSet(integer: 99), from: &unchanged) && unchanged == [0, 1],
       "stale selection is harmless")
print("PASS: shared deletion boundaries, presentation settings, header/body alignment")

// Preferences > Windows lists window actions with App List's Caps + key fields.
let windowOwner = AppDelegate()
windowOwner.bindings = []
let windowList = WindowShortcutListController(owner: windowOwner)
windowOwner.windowShortcutList = windowList
windowOwner.configureList(windowList.table, width: AppDelegate.preferenceSize.width, title: "Action")
windowList.table.reloadData()
expect(windowList.table.numberOfRows == WindowCommand.allCases.count && windowList.table.tableColumns.map { $0.title } == ["Action", "Shortcut"],
       "window list has one row per action under Action / Shortcut")
func windowRecorder(_ row: Int) -> KeyRecorder? {
    windowList.tableView(windowList.table, viewFor: windowList.table.tableColumns[1], row: row)?
        .subviews.compactMap { $0 as? KeyRecorder }.first
}
let centerRow = WindowCommand.allCases.firstIndex(of: .center)!
expect(windowRecorder(centerRow)?.title == shortcutTitle(windowOwner.windowShortcuts.key(for: .center).map { [$0] } ?? []), "shortcut field shows the current key")
let savedWindowKeys = UserDefaults.standard.data(forKey: DefaultsKey.windowShortcuts)
windowOwner.windowShortcuts = .defaults
if let recorder = windowRecorder(centerRow) {
    expect(windowOwner.assignShortcut([40], to: .window(.center), recorder: recorder), "a free key is assigned without asking")
    expect(!windowOwner.assignShortcut([KeyCode.space], to: .window(.center), recorder: recorder), "Space stays reserved for Folders")
    expect(!windowOwner.assignShortcut([40, 13], to: .window(.center), recorder: recorder), "a window action takes one key")
}
expect(windowOwner.windowShortcuts.key(for: .center) == 40 && windowRecorder(centerRow)?.title == "⇪K", "assignment updates the list")
expect(windowRecorder(centerRow)?.maxKeys == 1, "window actions record one key")
windowRecorder(centerRow)?.onClear?()
expect(windowOwner.windowShortcuts.key(for: .center) == nil && windowRecorder(centerRow)?.title == "Record Shortcut",
       "✕ clears a window shortcut")
windowOwner.restoreDefaultWindowShortcuts()
expect(windowOwner.windowShortcuts == .defaults && windowRecorder(centerRow)?.title == "⇪/", "Restore Defaults brings back ⇪/")
if let data = savedWindowKeys { UserDefaults.standard.set(data, forKey: DefaultsKey.windowShortcuts) }
else { UserDefaults.standard.removeObject(forKey: DefaultsKey.windowShortcuts) }
print("PASS: window shortcut list")

// App List search matches application names only.
let savedShortcuts = UserDefaults.standard.data(forKey: DefaultsKey.shortcuts)
let searchOwner = AppDelegate()
searchOwner.bindings = [AppShortcut(keys: [46], name: "Messages", path: "/messages", bundleID: nil),
                        AppShortcut(keys: [46, 13], name: "Microsoft Word", path: "/word", bundleID: nil),
                        AppShortcut(keys: [13], name: "WeChat", path: "/wechat", bundleID: nil),
                        AppShortcut(name: "Stickies", path: "/stickies", bundleID: nil)]
let searchList = ApplicationListController(owner: searchOwner)
searchOwner.applicationList = searchList
searchOwner.configureList(searchList.table, width: AppDelegate.preferenceSize.width, title: "Application")
searchList.reload()
func shownNames() -> [String] { searchList.visibleIndices.map { searchOwner.bindings[$0].name } }
expect(shownNames().count == 4 && searchList.table.numberOfRows == 4, "an empty search shows every application")
searchList.setFilter("CHAT")
expect(shownNames() == ["WeChat"] && searchList.table.numberOfRows == 1, "names match anywhere, ignoring case")
searchList.setFilter(" word ")
expect(shownNames() == ["Microsoft Word"], "surrounding spaces are ignored")
for query in ["M W", "Caps + M", "mw"] {
    searchList.setFilter(query)
    expect(shownNames().isEmpty, "\"\(query)\" does not search shortcuts")
}
searchList.setFilter("zzz")
expect(searchList.table.numberOfRows == 0, "no match shows no rows")
let nameColumn = searchList.table.tableColumns[0], shortcutColumn = searchList.table.tableColumns[1]
searchList.setFilter("w")
expect(shownNames() == ["Microsoft Word", "WeChat"], "a filtered list keeps name order")
expect(searchList.tableView(searchList.table, typeSelectStringFor: nameColumn, row: 1) == "WeChat"
       && searchList.tableView(searchList.table, typeSelectStringFor: nil, row: 1) == "WeChat",
       "type selection uses the names of the rows shown")
expect(searchList.tableView(searchList.table, typeSelectStringFor: shortcutColumn, row: 1) == nil,
       "shortcut fields take no part in type selection")
let filteredCell = searchList.tableView(searchList.table, viewFor: nameColumn, row: 1)!
expect(filteredCell.subviews.compactMap { ($0 as? NSTextField)?.stringValue } == ["WeChat"], "filtered rows show their own application")
searchList.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
searchList.setFilter("word")
expect(searchList.table.selectedRowIndexes == IndexSet(integer: 0) && shownNames() == ["Microsoft Word"],
       "the selection follows its application when the search changes")
searchList.setFilter("w")
searchList.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
searchOwner.removeBinding()
expect(searchOwner.bindings.map { $0.name } == ["Messages", "Microsoft Word", "Stickies"],
       "removing while filtered removes the selected row's application")
expect(shownNames() == ["Microsoft Word"] && searchList.table.selectedRowIndexes == IndexSet(integer: 0),
       "after removal the nearest remaining row is selected")
searchList.setFilter("w")
searchList.reveal(bindingAt: 2)
expect(searchList.filter.isEmpty && searchList.table.selectedRowIndexes == IndexSet(integer: 2),
       "revealing a hidden application clears the search")
if let data = savedShortcuts { UserDefaults.standard.set(data, forKey: DefaultsKey.shortcuts) }
else { UserDefaults.standard.removeObject(forKey: DefaultsKey.shortcuts) }
print("PASS: App List search, type selection, filtered removal")
// Websites share the App List and Folders keys, and show in the HUD like them.
let savedWebsites = UserDefaults.standard.data(forKey: DefaultsKey.websites)
let siteOwner = AppDelegate()
siteOwner.bindings = [AppShortcut(keys: [46], name: "Mail", path: "/mail", bundleID: nil)]
siteOwner.folders = []
siteOwner.websites = [WebsiteEntry(url: "https://github.com"), WebsiteEntry(url: "https://github.com/qianshuguo/clutch")]
let siteList = WebsiteListController(owner: siteOwner)
siteOwner.websiteList = siteList
siteOwner.configureList(siteList.table, width: AppDelegate.preferenceSize.width, title: "Website",
                        nameWidth: AppDelegate.websiteNameColumnWidth)
siteList.reload()
expect(siteList.table.numberOfRows == 2, "the Websites page lists every website")
let siteNameCell = siteList.tableView(siteList.table, viewFor: siteList.table.tableColumns[0], row: 1)!
expect(siteNameCell.subviews.compactMap { ($0 as? NSTextField)?.stringValue } == ["github.com/qianshuguo/clutch"]
       && siteNameCell.toolTip == "https://github.com/qianshuguo/clutch\nIncluding subdomains", "a website row shows what it matches, and its address on hover")
siteOwner.websites[1].title = "Clutch"
siteList.reload()
let namedSiteCell = siteList.tableView(siteList.table, viewFor: siteList.table.tableColumns[0], row: 1)!
expect(namedSiteCell.subviews.compactMap { ($0 as? NSTextField)?.stringValue } == ["Clutch"]
       && namedSiteCell.toolTip == "https://github.com/qianshuguo/clutch\nIncluding subdomains",
       "a named website row shows only its name, and its address on hover")
expect(siteList.table.tableColumns[1].width >= CGFloat(ListGeometry.shortcutRecorderWidth),
       "the wider Websites name column still fits the shortcut field")
expect(siteList.tableView(siteList.table, typeSelectStringFor: siteList.table.tableColumns[0], row: 1) == "Clutch",
       "typing jumps to a website by its name")
siteOwner.websites[1].title = ""
siteList.reload()
let siteRecorder = siteList.tableView(siteList.table, viewFor: siteList.table.tableColumns[1], row: 0)!
    .subviews.compactMap { $0 as? KeyRecorder }.first!
expect(siteRecorder.maxKeys == 3, "websites record up to three keys")
expect(siteOwner.assignShortcut([5], to: .website(url: "https://github.com"), recorder: siteRecorder)
       && siteOwner.websites[0].keys == [5], "a website takes ⇪G")
if case .website(let site)? = siteOwner.shortcutTarget(for: [5]) {
    expect(site.url == "https://github.com", "⇪G opens the website")
} else { expect(false, "⇪G opens the website") }
expect(siteOwner.shortcutTarget(for: [5])?.path == "https://github.com", "the HUD tracks a website by its address")
expect(siteOwner.shortcutConflicts([5], for: .app(path: "/mail")).owners == [.website(url: "https://github.com")],
       "an app and a website cannot share a shortcut")
expect(siteOwner.shortcutConflicts([46], for: .website(url: "https://github.com")).inUse == ["⇪M already opens Mail."],
       "a website asks before taking an app's shortcut")
siteOwner.addWebsite(address: "www.github.com/")
expect(siteOwner.websites.count == 2 && siteList.table.selectedRowIndexes == IndexSet(integer: 0),
       "adding a website already listed selects it")
siteOwner.addWebsite(address: "news.ycombinator.com")
expect(siteOwner.websites.last?.url == "https://news.ycombinator.com" && siteList.table.selectedRowIndexes == IndexSet(integer: 2),
       "a new website is added and selected")
siteOwner.addWebsite(address: "example.com", name: "  Example  ")
expect(siteOwner.websites.last?.title == "Example" && siteOwner.websites.last?.name == "Example",
       "a website can be added with a name, like a bookmark")
expect(siteOwner.websites.last?.includesSubdomains == true, "a new website includes subdomains unless turned off")
siteOwner.updateWebsite(at: 3, name: "Example Docs", address: "example.com/docs/")
expect(siteOwner.websites[3].url == "https://example.com/docs" && siteOwner.websites[3].title == "Example Docs"
       && siteList.table.selectedRowIndexes == IndexSet(integer: 3), "editing changes a website's name and address")
siteOwner.websites[3].keys = [14]
siteOwner.updateWebsite(at: 3, name: "", address: "example.com/docs")
expect(siteOwner.websites[3].keys == [14] && siteOwner.websites[3].name == "example.com/docs",
       "editing keeps the shortcut, and clearing the name shows the address")
siteOwner.updateWebsite(at: 3, name: "", address: "example.com/docs", includesSubdomains: false)
expect(!siteOwner.websites[3].includesSubdomains, "editing can turn Include subdomains off")
siteOwner.updateWebsite(at: 3, name: "", address: "example.com/docs")
expect(!siteOwner.websites[3].includesSubdomains, "editing without the checkbox keeps it as it was")
expect(AppDelegate.editableAddress("https://github.com/x") == "github.com/x"
       && AppDelegate.editableAddress("http://localhost:3000") == "http://localhost:3000",
       "the Edit sheet shows the address as typed")
siteOwner.websites.removeLast()
siteList.table.selectRowIndexes(IndexSet([0, 2]), byExtendingSelection: false)
siteOwner.removeWebsites()
expect(siteOwner.websites.map { $0.name } == ["github.com/qianshuguo/clutch"] && siteList.table.selectedRowIndexes == IndexSet(integer: 0),
       "removing selected websites selects the nearest remaining row")
expect(AppDelegate.preferenceTabs.map { $0.id } == ["general", "apps", "folders", "websites", "windows"],
       "Websites is its own Preferences page, before Windows")
if let data = savedWebsites { UserDefaults.standard.set(data, forKey: DefaultsKey.websites) }
else { UserDefaults.standard.removeObject(forKey: DefaultsKey.websites) }
print("PASS: Websites list, names, shared shortcuts, adding, editing and removing")
