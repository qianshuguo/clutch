import Cocoa

// Shared application state. Feature behavior is implemented in the extensions
// under App, Keyboard, Applications, Folders, Preferences, and Shared.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let preferenceTabs = [(id: "general", title: "General", symbol: "gearshape"),
                                 (id: "apps", title: "App List", symbol: "list.bullet.rectangle"),
                                 (id: "folders", title: "Folders", symbol: "folder"),
                                 (id: "windows", title: "Windows", symbol: "macwindow")]
    // Exactly fits the Windows list without scrolling: its rows plus the list chrome
    // from makeListScroll (33 bottom bar, 28 header, 6 + 6 spacing). 7 rows → 311.
    static let preferenceSize = NSSize(width: 460, height: 73 + CGFloat(WindowCommand.allCases.count) * appRowHeight)
    static let appRowHeight: CGFloat = 34
    static let listIconFrame = NSRect(x: 6, y: 7, width: 20, height: 20)
    static let listNameFrame = NSRect(x: 34, y: 7, width: 172, height: 18)
    var item: NSStatusItem!
    var window: NSWindow!
    var applicationList: ApplicationListController?
    var table: NSTableView? { applicationList?.table }
    var toggleButton: NSButton!
    var toggleMenuItems: [NSMenuItem] = []
    var loginCheckbox: NSButton?
    var hideCheckbox: NSButton?
    var accessibilityNoticeRow: NSView?
    var pages: [NSView] = []
    var selectedPage = 0
    let reopenNotification = Notification.Name("local.maxvoid.HyperKey.showPreferences")
    var tap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var permissionTimer: Timer?
    var state = KeyboardState()
    var lastKeyEventUptime: TimeInterval = 0
    // Keys consumed by a Caps recording in the App List, whose releases are consumed too.
    var recordingCapsKeys = Set<UInt16>()
    let mapping = CapsMapping()
    var wantsEnabled = false
    var starting = false
    var ownsLifecycle = false
    var bindings: [AppShortcut] = []
    let applicationWindowCycle = ApplicationWindowCycle()
    let windowManager = WindowManager()
    var windowShortcuts = WindowShortcuts.load()
    var windowShortcutList: WindowShortcutListController?
    var showingLaunchConfirmation = false
    var closingPreferencesForAction = false
    var folderWindow: FolderPanel?
    var folderList: FolderListController?
    var preferencesFolderList: FolderListController?
    var folderTable: NSTableView? { folderList?.table }
    var preferencesFolderTable: NSTableView? { preferencesFolderList?.table }
    var folders: [FolderEntry] = []
    let folderDragType = NSPasteboard.PasteboardType("local.maxvoid.HyperKey.folder")
}
