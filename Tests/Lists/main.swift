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
owner.bindings = [AppShortcut(key: 3, name: "Example", path: "/Applications/Example.app", bundleID: nil)]
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
expect(pickerTable.numberOfRows == 1 && search.folderIndex(forRow: 0) == 0, "paths match too")
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
print("PASS: Folders search field filters by name and path, maps rows, Escape/arrows")
let ranked = [FolderEntry(name: "Kidocs", path: "/k"), FolderEntry(name: "Project Docs", path: "/p"),
              FolderEntry(name: "Downloads", path: "/d"), FolderEntry(name: "Photo Dump", path: "/docs/x"),
              FolderEntry(name: "Docker", path: "/r")]
expect(FolderListController.ordered(ranked, query: "doc") == [1, 4, 0, 3],
       "word starts first (in list order), then names containing it, then paths")
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
owner.configureList(applications.table, width: AppDelegate.preferenceSize.width, columnID: "app")
applications.table.reloadData()
// Deliberately give the coordinator another table. Cell callbacks must use their origin.
owner.applicationList = ApplicationListController(owner: owner)
let cell = applications.tableView(applications.table, viewFor: applications.table.tableColumns[1], row: 0)!
let recorder = cell.subviews.compactMap { $0 as? KeyRecorder }.first!
_ = owner.state.route(key: 79, down: true, repeated: false, bound: false)
recorder.onStart?()
expect(owner.state.held, "recording preserves standalone Caps")
expect(owner.state.route(key: 79, down: false, repeated: false, bound: false, shortcutsEnabled: false).tap,
       "standalone Caps still replays after recording begins")
expect(applications.table.selectedRow == 0, "recording selects the originating application table")
expect(owner.applicationList?.table.selectedRow == -1, "recording does not select a different table")
expect(recorder.title == "Caps + F", "assigned key label is preserved")
let header = PlainListHeaderView(frame: NSRect(x: 0, y: 0, width: 460, height: 28))
header.tableView = applications.table
header.layout()
expect(!cell.subviews.contains { $0 is NSTextField }, "the shortcut field includes Caps; there is no separate label")
let detailColumn = applications.table.frameOfCell(atColumn: 1, row: 0)
expect(abs(header.secondLabel.frame.minX - (detailColumn.minX + recorder.frame.minX)) < 0.01,
       "shortcut header aligns with the actual row contents")
for (content, controller) in [(preferences.content, preferences.controller), (picker.content, picker.controller)] {
    let scroll = content.subviews.compactMap { $0 as? ListScrollView }.first!
    let isPicker = controller.presentation == .picker
    expect(scroll.fitsTableToViewport == isPicker, "only picker columns fit the viewport")
    expect(content.subviews.contains { $0 is PlainListHeaderView } == !isPicker,
           "only preferences has a header")
}
expect(owner.assignShortcut(46, 46, to: owner.bindings[0], recorder: recorder) && owner.bindings[0].secondKey == 46, "Caps + M + M uses the same key twice")
expect(!owner.assignShortcut(46, KeyCode.space, to: owner.bindings[0], recorder: recorder), "Space stays reserved as a second key")
expect(owner.assignShortcut(46, 13, to: owner.bindings[0], recorder: recorder)
       && owner.bindings[0].key == 46 && owner.bindings[0].secondKey == 13, "Caps + M + W is assigned without asking")
let comboCell = applications.tableView(applications.table, viewFor: applications.table.tableColumns[1], row: 0)!
expect(comboCell.subviews.compactMap { $0 as? KeyRecorder }.first?.title == "Caps + M + W", "two-key shortcuts show both keys")
expect(owner.assignShortcut(3, to: owner.bindings[0], recorder: recorder) && owner.bindings[0].secondKey == nil, "assigning one key clears the second key")
// Recording as used: Caps held, T then H, Caps released.
recorder.recording = true
expect(recorder.prompt == (owner.tap == nil ? "Turn on Clutch" : "Hold Caps + 1 or 2 keys"), "the prompt depends on whether Clutch can see Caps")
recorder.capsAvailable = { true } // As if Clutch were enabled.
expect(recorder.prompt == "Hold Caps + 1 or 2 keys", "App List asks for Caps + 1 or 2 keys")
recorder.capsPressed()
expect(recorder.title == "Caps + …", "pressing Caps shows the field is listening")
recorder.capsReleased()
expect(recorder.recording, "releasing Caps alone records nothing")
expect(recorder.title == recorder.prompt, "releasing Caps alone shows the prompt again")
recorder.capsPressed()
recorder.capsKeyPressed(17)
expect(recorder.title == "Caps + T + …", "the first Caps key waits for an optional second key")
recorder.capsKeyPressed(4)
expect(recorder.title == "Caps + T + H", "the field shows both keys while Caps is held")
recorder.capsReleased()
expect(!recorder.recording && owner.bindings[0].key == 17 && owner.bindings[0].secondKey == 4, "releasing Caps saves Caps + T + H")
recorder.recording = true
recorder.capsKeyPressed(17)
recorder.capsReleased()
expect(owner.bindings[0].key == 17 && owner.bindings[0].secondKey == nil, "one key then Caps release saves a one-key shortcut")
recorder.recording = true
recorder.capsKeyPressed(17)
recorder.capsKeyPressed(17)
expect(recorder.title == "Caps + T + T", "the same key can be recorded twice")
recorder.capsReleased()
expect(owner.bindings[0].key == 17 && owner.bindings[0].secondKey == 17, "releasing Caps saves Caps + T + T")
let legacy = try! JSONDecoder().decode([AppShortcut].self, from: Data(#"[{"key":3,"name":"Old","path":"/tmp/old"}]"#.utf8))
expect(legacy[0].key == 3 && legacy[0].secondKey == nil, "lists saved before two-key shortcuts still load")
// Caps release decides, so Caps + M and Caps + M + W can belong to different apps.
owner.bindings = [AppShortcut(key: 46, name: "Mail", path: "/mail", bundleID: nil),
                  AppShortcut(key: 46, name: "Word", path: "/word", bundleID: nil, secondKey: 13),
                  AppShortcut(key: 46, name: "Messages", path: "/messages", bundleID: nil, secondKey: 46)]
let comboConflicts = owner.shortcutConflicts(46, 13, excluding: "/notes")
expect(comboConflicts.indices == [1] && comboConflicts.inUse == ["Caps + M + W already opens Word."], "only the same shortcut conflicts")
expect(owner.shortcutConflicts(46, nil, excluding: "/notes").indices == [0], "Caps + M alone conflicts only with Caps + M")
expect(owner.shortcutConflicts(46, 7, excluding: "/notes").indices.isEmpty, "a new two-key shortcut can share its first key")
expect(owner.shortcutConflicts(46, 13, excluding: "/word").indices.isEmpty, "an app never conflicts with itself")
let windowConflicts = owner.firstKeyConflicts(46)
expect(windowConflicts.indices == [0, 1, 2] && windowConflicts.inUse == ["Caps + M already opens Mail.", "Caps + M already starts Word (M + W) and Messages (M + M)."],
       "a window action takes the key alone and every two-key shortcut starting with it")
owner.bindings = []
expect(recorder.onKeys?(0, nil) == false, "a removed binding cannot be assigned from a stale cell")

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
trackingOwner.bindings = (0..<4).map { AppShortcut(key: 3, name: "Row \($0)", path: "/tmp/\($0)", bundleID: nil) }
let trackingController = ApplicationListController(owner: trackingOwner)
let trackingTable = trackingController.table
trackingOwner.configureList(trackingTable, width: 460, columnID: "app")
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
windowOwner.configureList(windowList.table, width: AppDelegate.preferenceSize.width, columnID: "window")
windowList.table.reloadData()
expect(windowList.table.numberOfRows == WindowCommand.allCases.count && windowList.table.tableColumns.map { $0.title } == ["Action", "Shortcut"],
       "window list has one row per action under Action / Shortcut")
func windowRecorder(_ row: Int) -> KeyRecorder? {
    windowList.tableView(windowList.table, viewFor: windowList.table.tableColumns[1], row: row)?
        .subviews.compactMap { $0 as? KeyRecorder }.first
}
let centerRow = WindowCommand.allCases.firstIndex(of: .center)!
expect(windowRecorder(centerRow)?.title == shortcutTitle(windowOwner.windowShortcuts.key(for: .center), nil), "shortcut field shows the current key")
let savedWindowKeys = UserDefaults.standard.data(forKey: DefaultsKey.windowShortcuts)
windowOwner.windowShortcuts = .defaults
if let recorder = windowRecorder(centerRow) {
    expect(windowOwner.assignWindowShortcut(40, to: .center, recorder: recorder), "a free key is assigned without asking")
    expect(!windowOwner.assignWindowShortcut(KeyCode.space, to: .center, recorder: recorder), "Space stays reserved for Folders")
}
expect(windowOwner.windowShortcuts.key(for: .center) == 40 && windowRecorder(centerRow)?.title == "Caps + K", "assignment updates the list")
windowOwner.restoreDefaultWindowShortcuts()
expect(windowOwner.windowShortcuts == .defaults && windowRecorder(centerRow)?.title == "Caps + /", "Restore Defaults brings back Caps + /")
if let data = savedWindowKeys { UserDefaults.standard.set(data, forKey: DefaultsKey.windowShortcuts) }
else { UserDefaults.standard.removeObject(forKey: DefaultsKey.windowShortcuts) }
print("PASS: window shortcut list")

// App List search matches application names only.
let savedShortcuts = UserDefaults.standard.data(forKey: DefaultsKey.shortcuts)
let searchOwner = AppDelegate()
searchOwner.bindings = [AppShortcut(key: 46, name: "Messages", path: "/messages", bundleID: nil),
                        AppShortcut(key: 46, name: "Microsoft Word", path: "/word", bundleID: nil, secondKey: 13),
                        AppShortcut(key: 13, name: "WeChat", path: "/wechat", bundleID: nil),
                        AppShortcut(key: unassignedKey, name: "Stickies", path: "/stickies", bundleID: nil)]
let searchList = ApplicationListController(owner: searchOwner)
searchOwner.applicationList = searchList
searchOwner.configureList(searchList.table, width: AppDelegate.preferenceSize.width, columnID: "app")
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
