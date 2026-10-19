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
print("PASS: app-independent window cycling, stable order, wraparound, window changes, app changes")

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
expect(owner.table?.selectedRow == -1, "recording does not select a different table")
expect(recorder.title == "F", "assigned key label is preserved")
let header = PlainListHeaderView(frame: NSRect(x: 0, y: 0, width: 460, height: 28))
header.tableView = applications.table
header.layout()
let prefix = cell.subviews.compactMap { $0 as? NSTextField }.first!
let detailColumn = applications.table.frameOfCell(atColumn: 1, row: 0)
expect(abs(header.secondLabel.frame.minX - (detailColumn.minX + prefix.frame.minX)) < 0.01,
       "shortcut header aligns with the actual row contents")
for (content, controller) in [(preferences.content, preferences.controller), (picker.content, picker.controller)] {
    let scroll = content.subviews.compactMap { $0 as? ListScrollView }.first!
    let isPicker = controller.presentation == .picker
    expect(scroll.fitsTableToViewport == isPicker, "only picker columns fit the viewport")
    expect(content.subviews.contains { $0 is PlainListHeaderView } == !isPicker,
           "only preferences has a header")
}
owner.bindings = []
expect(recorder.onKey?(0) == false, "a removed binding cannot be assigned from a stale cell")

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
        let next = ListSelection.remove(selected, from: &items)
        expect(items == Array(0..<count).filter { !selected.contains($0) },
               "multi-delete preserves surviving order")
        if let first = selected.first {
            let expected = items.isEmpty ? IndexSet() : IndexSet(integer: min(first, items.count - 1))
            expect(next == expected, "multi-delete selects the nearest surviving row")
        } else { expect(next == nil, "empty selection does not trigger a save") }
    }
}
var unchanged = [0, 1]
expect(ListSelection.remove(IndexSet(integer: 99), from: &unchanged) == nil && unchanged == [0, 1],
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
expect(windowRecorder(centerRow)?.title == keyName(windowOwner.windowShortcuts.key(for: .center)) ?? "Click to set", "shortcut field shows the current key")
let savedWindowKeys = UserDefaults.standard.data(forKey: WindowShortcuts.defaultsKey)
windowOwner.windowShortcuts = .defaults
if let recorder = windowRecorder(centerRow) {
    expect(windowOwner.assignWindowShortcut(40, to: .center, recorder: recorder), "a free key is assigned without asking")
    expect(!windowOwner.assignWindowShortcut(KeyCode.space, to: .center, recorder: recorder), "Space stays reserved for Folders")
}
expect(windowOwner.windowShortcuts.key(for: .center) == 40 && windowRecorder(centerRow)?.title == "K", "assignment updates the list")
windowOwner.restoreDefaultWindowShortcuts()
expect(windowOwner.windowShortcuts == .defaults && windowRecorder(centerRow)?.title == "/", "Restore Defaults brings back Caps + /")
if let data = savedWindowKeys { UserDefaults.standard.set(data, forKey: WindowShortcuts.defaultsKey) }
else { UserDefaults.standard.removeObject(forKey: WindowShortcuts.defaultsKey) }
print("PASS: window shortcut list")
