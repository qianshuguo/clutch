import Cocoa

// Shared application state. Feature behavior is implemented in the extensions
// under App, Keyboard, Applications, Folders, Shelf, Websites, Preferences, and Shared.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let preferenceTabs = [(id: "general", title: "General", symbol: "gearshape"),
                                 (id: "apps", title: "App List", symbol: "list.bullet.rectangle"),
                                 (id: "folders", title: "Folders", symbol: "folder"),
                                 (id: "websites", title: "Websites", symbol: "globe"),
                                 (id: "windows", title: "Windows", symbol: "macwindow")]
    // The Windows list's rows plus the list chrome (ListGeometry.chromeHeight), and one
    // more row of room so General is not crowded. 7 + 1 rows → 345.
    static let preferenceSize = NSSize(width: 460, height: ListGeometry.chromeHeight + CGFloat(WindowCommand.allCases.count + 1) * appRowHeight)
    // The Shelf picker's list, which has no column header or bottom bar: 8 rows and a gap → 278.
    static let shelfRows = 8
    static let shelfListSize = NSSize(width: 460, height: ListGeometry.spacing + CGFloat(shelfRows) * appRowHeight)
    static let appRowHeight: CGFloat = 34
    static let listIconFrame = NSRect(x: ListGeometry.leadingInset, y: 7, width: 20, height: 20)
    static let listNameFrame = NSRect(x: ListGeometry.leadingInset + 28, y: 7, width: 172, height: 18)
    var item: NSStatusItem!
    var window: NSWindow!
    var applicationList: ApplicationListController?
    var toggleButton: NSButton!
    var toggleMenuItems: [NSMenuItem] = []
    var loginCheckbox: NSButton?
    var hideCheckbox: NSButton?
    var askBeforeOpeningCheckbox: NSButton?
    var accessibilityHint: NSTextField?
    var accessibilityNotice: NSButton?
    var pages: [NSView] = []
    var selectedPage = 0
    let reopenNotification = Notification.Name("local.maxvoid.Clutch.showPreferences")
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
    let windowPreviewOverlay = WindowPreviewOverlay()
    // The one Caps HUD window: keys pressed, app card, and launch confirmation.
    let capsOverlay = CapsOverlay()
    var windowPreview: WindowPreviewSession?
    var windowShortcuts = WindowShortcuts.load()
    var windowShortcutList: WindowShortcutListController?
    var showingLaunchConfirmation = false
    var folderList: FolderListController?
    var folders: [FolderEntry] = []
    let folderDragType = NSPasteboard.PasteboardType("local.maxvoid.Clutch.folder")
    // Caps + Space: the Shelf picker and its files, in the user's order (new files on top).
    var shelf: [ShelfEntry] = []
    var shelfPanel: ShelfPanel?
    var shelfList: ShelfListController?
    var websites: [WebsiteEntry] = []
    var websiteList: WebsiteListController?
    let browserTabs = BrowserTabs()
    // Browsers already reported as refusing Automation, so the alert shows once per launch.
    var automationDeniedBrowsers = Set<String>()
}
