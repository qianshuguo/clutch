import Cocoa
import ServiceManagement
import ApplicationServices
import UniformTypeIdentifiers
import Carbon

let capsUsage: UInt64 = 0x700000039
let f18Usage: UInt64 = 0x70000006D
let sourceKey = "HIDKeyboardModifierMappingSrc"
let destinationKey = "HIDKeyboardModifierMappingDst"
let keys: [(String, UInt16)] = [
    ("A",0),("B",11),("C",8),("D",2),("E",14),("F",3),("G",5),
    ("H",4),("I",34),("J",38),("K",40),("L",37),("M",46),("N",45),
    ("O",31),("P",35),("Q",12),("R",15),("S",1),("T",17),("U",32),
    ("V",9),("W",13),("X",7),("Y",16),("Z",6),
    ("0",29),("1",18),("2",19),("3",20),("4",21),("5",23),
    ("6",22),("7",26),("8",28),("9",25)]

let unassignedKey: UInt16 = .max
let extraKeys: [UInt16: String] = [36:"Return",48:"Tab",49:"Space",51:"⌫",117:"⌦",
    123:"←",124:"→",125:"↓",126:"↑",115:"Home",119:"End",116:"PgUp",121:"PgDn",
    27:"−",24:"=",33:"[",30:"]",42:"\\",41:";",39:"'",43:",",47:".",44:"/",50:"`",
    122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",
    109:"F10",103:"F11",111:"F12",105:"F13",107:"F14",113:"F15",106:"F16",64:"F17",80:"F19",90:"F20"]
func keyName(_ code: UInt16) -> String? { keys.first { $0.1 == code }?.0 ?? extraKeys[code] }

final class KeyRecorder: NSButton {
    var savedTitle = "Click to set"
    var recording = false
    var onStart: (() -> Void)?
    var onKey: ((UInt16) -> Bool)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard window?.makeFirstResponder(self) == true else { return }
        if !recording { savedTitle = title; recording = true; onStart?() }
        title = "Press a key…"
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { cancelRecording(); return }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers.isEmpty, keyName(event.keyCode) != nil else { NSSound.beep(); return }
        if onKey?(event.keyCode) == true {
            recording = false
            window?.makeFirstResponder(nil)
        }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        if event.modifierFlags.contains(.command), [1, 13].contains(event.keyCode) { return false }
        keyDown(with: event)
        return true
    }
    func cancelRecording() {
        if recording { title = savedTitle; recording = false }
    }
    override func resignFirstResponder() -> Bool {
        cancelRecording()
        return super.resignFirstResponder()
    }
}

struct Binding: Codable {
    var key: UInt16
    var name: String
    var path: String
    var bundleID: String?
}

struct ToolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func isWindowCloseShortcut(_ event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
    return (event.keyCode == 53 && modifiers.isEmpty) || (event.keyCode == 13 && modifiers == .command)
}

enum ListGeometry {
    static let selectionExtension: CGFloat = 4
    static let applicationOverflow: CGFloat = 2
}

enum InterfacePalette {
    static let surface = NSColor(name: NSColor.Name("HyperCapsListSurface")) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.windowBackgroundColor
            : NSColor(srgbRed: 222 / 255, green: 222 / 255, blue: 222 / 255, alpha: 1)
    }
}

// Only the surface color is customized; controls and selection remain native.
final class ListSurface: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = InterfacePalette.surface.cgColor }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// Plain labels and rules; NSTableHeaderView continues to handle column resizing.
final class PlainListHeaderView: NSTableHeaderView {
    let firstLabel = NSTextField(labelWithString: "")
    let secondLabel = NSTextField(labelWithString: "")
    let bottomRule = NSBox()
    let columnRule = NSBox()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }
    private func configure() {
        for label in [firstLabel, secondLabel] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }
        for rule in [bottomRule, columnRule] {
            rule.boxType = .separator
            addSubview(rule)
        }
        needsLayout = true
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }
    override func draw(_ dirtyRect: NSRect) {
        InterfacePalette.surface.setFill()
        bounds.fill()
    }
    override func layout() {
        super.layout()
        guard let table = tableView, table.tableColumns.count == 2 else { return }
        let folders = table.tableColumns[0].identifier.rawValue == "folder"
        let firstColumn = table.tableColumns[0]
        let secondColumn = table.tableColumns[1]
        let firstBody = table.numberOfRows > 0 ? table.frameOfCell(atColumn: 0, row: 0)
            : NSRect(x: 16, y: 0, width: firstColumn.width - 16, height: 0)
        let secondBody = table.numberOfRows > 0 ? table.frameOfCell(atColumn: 1, row: 0)
            : NSRect(x: firstColumn.width, y: 0, width: secondColumn.width - 16, height: 0)
        firstLabel.stringValue = firstColumn.title
        secondLabel.stringValue = secondColumn.title
        for label in [firstLabel, secondLabel] { label.font = .systemFont(ofSize: 11) }
        firstLabel.frame = NSRect(x: firstBody.minX + ListGeometry.selectionExtension, y: 7, width: max(0, firstBody.width - 6 - ListGeometry.selectionExtension), height: 18)
        let secondX = folders ? secondBody.minX + 12 : secondBody.maxX - 166 - ListGeometry.selectionExtension
        secondLabel.frame = NSRect(x: secondX, y: 7, width: max(0, secondBody.maxX - secondX - ListGeometry.selectionExtension), height: 18)
        bottomRule.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        columnRule.isHidden = !table.allowsColumnResizing
        columnRule.frame = NSRect(x: headerRect(ofColumn: 0).maxX - 0.5, y: 5, width: 1, height: 18)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

final class PreferencesWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if attachedSheet == nil, isWindowCloseShortcut(event) {
            if event.keyCode == 53, cancelFolderRename(in: self) { return true }
            if event.keyCode == 53, let recorder = firstResponder as? KeyRecorder, recorder.recording {
                recorder.cancelRecording()
            } else {
                performClose(nil)
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func cancelOperation(_ sender: Any?) {
        if attachedSheet == nil { performClose(sender) }
    }
}

final class LaunchConfirmationPanel: NSPanel {
    private(set) var dismissedByOutsideClick = false

    func dismissForOutsideClick() {
        guard NSApp.modalWindow === self else { return }
        dismissedByOutsideClick = true
        NSApp.stopModal(withCode: .cancel)
        // Wake the modal event loop even when the click belongs to another app.
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windowNumber, context: nil, subtype: 0, data1: 0, data2: 0) {
            NSApp.postEvent(event, atStart: true)
        }
    }

    override func resignKey() {
        super.resignKey()
        dismissForOutsideClick()
    }

    override func performClose(_ sender: Any?) { NSApp.stopModal(withCode: .cancel) }
    override func cancelOperation(_ sender: Any?) { performClose(sender) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isWindowCloseShortcut(event) { performClose(nil); return true }
        switch event.keyCode {
        case 36, 76: NSApp.stopModal(withCode: .OK); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if !performKeyEquivalent(with: event) { super.keyDown(with: event) }
    }
}

// Keep the label cell's geometry while using AppKit's field editor for renaming.
final class FolderNameField: NSTextField, NSTextFieldDelegate {
    static weak var active: FolderNameField?
    weak var folderTable: NSTableView?
    var onRename: ((String) -> Void)?
    private var originalName = ""

    override func draw(_ dirtyRect: NSRect) {
        // A native cell border adds insets and shifts the field editor in this label-sized frame.
        // Draw the editing chrome separately so display and editing share the same baseline.
        if isEditable {
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            NSColor.textBackgroundColor.setFill()
            outline.fill()
            NSColor.keyboardFocusIndicatorColor.setStroke()
            outline.lineWidth = 1
            outline.stroke()
        }
        super.draw(dirtyRect)
    }

    @objc func beginRename() {
        guard !isEditable else { return }
        Self.active?.finishRename(cancelled: false)
        Self.active = self
        originalName = stringValue
        delegate = self
        isEditable = true
        isSelectable = true
        // Keep the cell borderless; its native border would change the text insets.
        needsDisplay = true
        selectText(nil)
    }

    func finishRename(cancelled: Bool) {
        guard isEditable else { return }
        let proposed = (currentEditor()?.string ?? stringValue).trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cancelled || proposed.isEmpty ? originalName : proposed
        isEditable = false
        if Self.active === self { Self.active = nil }
        isSelectable = false
        needsDisplay = true
        stringValue = name
        window?.makeFirstResponder(folderTable)
        if name != originalName { onRename?(name) }
    }

    func controlTextDidEndEditing(_ notification: Notification) { finishRename(cancelled: false) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finishRename(cancelled: true)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            finishRename(cancelled: false)
            return true
        }
        return false
    }
}

func cancelFolderRename(in window: NSWindow) -> Bool {
    guard let field = FolderNameField.active, field.window === window, field.isEditable else { return false }
    field.finishRename(cancelled: true)
    return true
}

final class FolderTableView: NSTableView {
    var openSelection: (() -> Void)?
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        if !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        guard let cell = view(atColumn: 0, row: row, makeIfNecessary: true),
              let field = cell.subviews.first(where: { $0 is FolderNameField }) as? FolderNameField else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let rename = NSMenuItem(title: "Rename", action: #selector(FolderNameField.beginRename), keyEquivalent: "")
        rename.target = field
        rename.isEnabled = selectedRowIndexes.count == 1
        menu.addItem(rename)
        return menu
    }
    override func flagsChanged(with event: NSEvent) { window?.flagsChanged(with: event) }
    override func keyDown(with event: NSEvent) {
        if [36, 76].contains(event.keyCode) { openSelection?() }
        else if event.keyCode == 53 { window?.keyDown(with: event) }
        else { super.keyDown(with: event) }
    }
}

final class FolderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var previousApplication: NSRunningApplication?
    weak var previousKeyWindow: NSWindow?
    override func performClose(_ sender: Any?) {
        guard attachedSheet == nil else { return }
        close()
        if previousApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            if let window = previousKeyWindow, window.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        } else if let application = previousApplication, !application.isTerminated {
            application.activate(options: [.activateIgnoringOtherApps])
        }
    }
    var openSelection: (() -> Void)?
    var selectNumber: ((Int) -> Void)?
    override func resignKey() {
        super.resignKey()
        if isVisible, attachedSheet == nil { close() }
    }
    override func cancelOperation(_ sender: Any?) { performClose(sender) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if attachedSheet == nil, isWindowCloseShortcut(event) {
            if event.keyCode == 53, cancelFolderRename(in: self) { return true }
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: performClose(nil)
        case 36, 76: openSelection?()
        default: super.keyDown(with: event)
        }
    }
}

final class LaunchConfirmation: NSObject {
    private let panel = LaunchConfirmationPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 88),
                                styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)

    func run(appName: String) -> Bool {
        let previousApplication = NSWorkspace.shared.frontmostApplication
        let previousKeyWindow = NSApp.keyWindow
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        guard let content = panel.contentView else { return false }
        let label = NSTextField(wrappingLabelWithString: "Open \(appName)?")
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24)
        ])
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        let mouseDowns: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDowns) { [weak panel] event in
            if let panel = panel, event.window !== panel { panel.dismissForOutsideClick() }
            return event
        }
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDowns) { [weak panel] _ in
            panel?.dismissForOutsideClick()
        }
        let confirmed = NSApp.runModal(for: panel) == .OK
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        panel.orderOut(nil)
        if !confirmed, !panel.dismissedByOutsideClick {
            if previousApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                previousKeyWindow?.makeKeyAndOrderFront(nil)
            } else if let application = previousApplication, !application.isTerminated {
                // Preserve the application's selected window instead of raising all its windows.
                application.activate(options: [.activateIgnoringOtherApps])
            }
        }
        return confirmed
    }

}

// hidutil has no persistent effect after reboot. Only this app's Caps entry is restored.
final class CapsMapping {
    let defaults = UserDefaults.standard
    let recoveryKey = "CapsMappingRecovery"
    func run(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output; process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let error = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ToolError(message: "Keyboard mapping failed: " + (String(data: error, encoding: .utf8) ?? "hidutil"))
        }
        return data
    }
    func read() throws -> [[String: UInt64]] {
        let data = try run(["property", "--get", "UserKeyMapping"])
        return try MappingCodec.decode(data)
    }
    func write(_ entries: [[String: UInt64]]) throws {
        let data = try JSONSerialization.data(withJSONObject: ["UserKeyMapping": entries])
        _ = try run(["property", "--set", String(data: data, encoding: .utf8)!])
        guard try read() == entries else { throw ToolError(message: "Keyboard mapping was not accepted. Check permissions or other keyboard tools.") }
    }
    func install() throws {
        try restore()
        let current = try read()
        defaults.set(try JSONEncoder().encode(current.filter { $0[sourceKey] == capsUsage }), forKey: recoveryKey)
        try write(MappingPolicy.install(current))
    }
    func restore() throws {
        guard let data = defaults.data(forKey: recoveryKey) else { return }
        let previous = try JSONDecoder().decode([[String: UInt64]].self, from: data)
        let current = try read()
        if current.contains(where: { $0[sourceKey] == capsUsage && $0[destinationKey] == f18Usage }) {
            let updated = MappingPolicy.restore(current, previous: previous)
            try write(updated)
        }
        defaults.removeObject(forKey: recoveryKey)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSMenuItemValidation, NSToolbarDelegate {
    static let preferenceTabs = [(title: "General", symbol: "gearshape"),
                                 (title: "App List", symbol: "list.bullet.rectangle"),
                                 (title: "Folders", symbol: "folder"),
                                 (title: "About", symbol: "person.crop.square")]
    static let preferenceSize = NSSize(width: 460, height: 310)
    static let appRowHeight: CGFloat = 34
    static let listIconFrame = NSRect(x: 6, y: 7, width: 20, height: 20)
    static let listNameFrame = NSRect(x: 34, y: 7, width: 172, height: 18)
    var item: NSStatusItem!
    var window: NSWindow!
    var table: NSTableView!
    var toggleButton: NSButton!
    var pauseItem: NSMenuItem!
    var loginCheckbox: NSButton?
    var hideCheckbox: NSButton?
    var accessibilityNotice: NSButton?
    var pages: [NSView] = []
    var selectedPage = 0
    let pageIDs = ["general", "apps", "folders", "about"]
    let reopenNotification = Notification.Name("local.maxvoid.HyperKey.showPreferences")
    var tap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var permissionTimer: Timer?
    var lastNonASCIIInputSource: TISInputSource?
    var state = KeyboardState()
    let mapping = CapsMapping()
    var wantsEnabled = false
    var starting = false
    var ownsLifecycle = false
    var bindings: [Binding] = []
    var showingLaunchConfirmation = false
    var folderWindow: FolderPanel?
    var folderTable: NSTableView?
    var preferencesFolderTable: NSTableView?
    var activeFolderTable: NSTableView? {
        if let panel = folderWindow,
           NSApp.keyWindow === panel || NSApp.keyWindow?.sheetParent === panel { return folderTable }
        return preferencesFolderTable
    }
    func isFolderTable(_ tableView: NSTableView) -> Bool {
        tableView.tableColumns.first?.identifier.rawValue == "folder"
    }
    var folders: [FolderEntry] = []
    let folderDragType = NSPasteboard.PasteboardType("local.maxvoid.HyperKey.folder")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Canvas needs the AppKit event loop, but none of the utility's startup
        // side effects (single-instance exit, mapping recovery, or event taps).
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        // Prevent two instances fighting over the same global mapping.
        // Xcode 15's Canvas host has the same bundle ID but never owns the
        // utility lifecycle or observes reopen requests. Ignore that host.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { app in
               app.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
                   !(app.bundleURL?.path.contains("/Intermediates.noindex/Previews/") ?? false)
           }) {
            DistributedNotificationCenter.default().postNotificationName(reopenNotification, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil); return
        }
        ownsLifecycle = true
        loadBindings()
        if let data = UserDefaults.standard.data(forKey: "Folders"),
           let loaded = try? JSONDecoder().decode([FolderEntry].self, from: data) { folders = loaded }
        createMenu()
        item.isVisible = !UserDefaults.standard.bool(forKey: "HideStatusBarIcon")
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showSettings), name: reopenNotification, object: nil)
        do { try mapping.restore() } catch { showError(error) }
        wantsEnabled = UserDefaults.standard.bool(forKey: "Enabled")
        if wantsEnabled { start() }
        if ProcessInfo.processInfo.arguments.contains("--settings") { showSettings() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }
    func loadBindings() {
        if let data = UserDefaults.standard.data(forKey: "Bindings"), let loaded = try? JSONDecoder().decode([Binding].self, from: data) {
            bindings = loaded; return
        }
        let candidates: [(String, UInt16, String)] = [
            ("Finder",3,"/System/Library/CoreServices/Finder.app"),
            ("Safari",1,"/Applications/Safari.app"),
            ("Terminal",17,"/System/Applications/Utilities/Terminal.app"),
            ("Google Chrome",8,"/Applications/Google Chrome.app"),
            ("Visual Studio Code",9,"/Applications/Visual Studio Code.app")]
        bindings = candidates.filter { FileManager.default.fileExists(atPath: $0.2) }.map {
            Binding(key: $0.1, name: $0.0, path: $0.2, bundleID: Bundle(path: $0.2)?.bundleIdentifier)
        }
    }
    func save() {
        if let data = try? JSONEncoder().encode(bindings) { UserDefaults.standard.set(data, forKey: "Bindings") }
        table?.reloadData()
    }
    func createMenu() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⇪+"
        item.button?.toolTip = "HyperCaps — Caps shortcuts"
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Preferences", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self; menu.addItem(settingsItem)
        let foldersItem = NSMenuItem(title: "Folders…", action: #selector(showFolders), keyEquivalent: "")
        foldersItem.target = self; menu.addItem(foldersItem)
        pauseItem = NSMenuItem(title: "Enable HyperCaps", action: #selector(toggle), keyEquivalent: "s")
        pauseItem.target = self; menu.addItem(pauseItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit HyperCaps", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        let closeItem = NSMenuItem(title: "Close Window", action: #selector(closeSettings), keyEquivalent: "w")
        closeItem.target = self
        closeItem.isHidden = true
        closeItem.allowsKeyEquivalentWhenHidden = true
        menu.insertItem(closeItem, at: 1)
        item.menu = menu
        // App-scoped shortcuts; Command-S in another app keeps its normal meaning.
        let main = NSMenu()
        let root = NSMenuItem(); root.submenu = menu.copy() as? NSMenu
        main.addItem(root); NSApp.mainMenu = main
    }
    func label(_ text: String, frame: NSRect, size: CGFloat = 13) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.frame = frame; field.font = .systemFont(ofSize: size); field.lineBreakMode = .byWordWrapping
        return field
    }
    func createWindow() {
        window = PreferencesWindow(contentRect: NSRect(origin: .zero, size: Self.preferenceSize),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Preferences"
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        let toolbar = NSToolbar(identifier: "Preferences")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .preference
        window.contentView = makePreferencesContent()
    }
    // Shared by the running app and Xcode Canvas. No keyboard services start here.
    func makePreferencesContent() -> NSView {
        let content = ListSurface(frame: NSRect(origin: .zero, size: Self.preferenceSize))
        pages = Self.preferenceTabs.map { _ in NSView(frame: content.bounds) }
        for page in pages {
            page.autoresizingMask = [.width, .height]
            content.addSubview(page)
        }
        let general = pages[0]
        toggleButton = NSButton(checkboxWithTitle: "Enable HyperCaps", target: self, action: #selector(toggle))
        toggleButton.frame = NSRect(x: 120, y: 244, width: 280, height: 24)
        general.addSubview(toggleButton)
        let notice = NSButton(title: "Waiting for Accessibility access", target: self, action: #selector(openPermissions))
        notice.isBordered = false
        notice.alignment = .left
        let noticeTitle = NSMutableAttributedString(string: notice.title, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        noticeTitle.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                                 range: (notice.title as NSString).range(of: "Accessibility access"))
        notice.attributedTitle = noticeTitle
        notice.sizeToFit()
        notice.frame = NSRect(x: 140, y: 216, width: notice.frame.width, height: 20)
        notice.toolTip = "Open Accessibility settings to allow HyperCaps."
        notice.setAccessibilityLabel("Waiting for Accessibility access. Open Accessibility settings.")
        accessibilityNotice = notice
        general.addSubview(notice)
        let divider = NSBox(frame: NSRect(x: 24, y: 194, width: 412, height: 1))
        divider.boxType = .separator
        general.addSubview(divider)
        loginCheckbox = NSButton(checkboxWithTitle: "Launch on Login", target: self, action: #selector(changeLoginLaunch))
        loginCheckbox!.frame = NSRect(x: 120, y: 153, width: 300, height: 24)
        general.addSubview(loginCheckbox!)
        hideCheckbox = NSButton(checkboxWithTitle: "Hide Status Bar Icon", target: self, action: #selector(changeStatusIcon))
        hideCheckbox!.frame = NSRect(x: 120, y: 115, width: 300, height: 24)
        general.addSubview(hideCheckbox!)
        let hint = label("Open HyperCaps again to show Preferences.", frame: NSRect(x: 140, y: 89, width: 296, height: 20), size: 11)
        hint.textColor = .secondaryLabelColor
        general.addSubview(hint)

        let apps = pages[1]
        // Preserve the fixed shortcut column's original two-point native overflow.
        let scroll = makeListScroll(size: Self.preferenceSize, headerHeight: 0, additionalWidth: ListGeometry.applicationOverflow)
        table = NSTableView()
        configureList(table, width: Self.preferenceSize.width, columnID: "app", showsHeaders: true)
        // Every shortcut cell contains "Caps +"; type selection would make C cycle rows.
        table.allowsTypeSelect = false
        scroll.documentView = table
        apps.addSubview(scroll)
        let bottomDivider = NSBox(frame: NSRect(x: 0, y: 32, width: Self.preferenceSize.width, height: 1))
        bottomDivider.boxType = .separator
        apps.addSubview(bottomDivider)
        apps.addSubview(makeListButton(symbol: "plus", x: 8, action: #selector(addBinding), tip: "Add Application"))
        apps.addSubview(makeListButton(symbol: "minus", x: 38, action: #selector(removeBinding), tip: "Remove Application"))
        let folderContent = makeFoldersContent(size: Self.preferenceSize, showsHeaders: true)
        preferencesFolderTable = folderContent.list
        pages[2].addSubview(folderContent.content)
        syncPreferences()
        selectPage(selectedPage)
        return content
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        pageIDs.map { NSToolbarItem.Identifier($0) }
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let index = pageIDs.firstIndex(of: identifier.rawValue) else { return nil }
        let tab = Self.preferenceTabs[index]
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = tab.title
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
        item.target = self; item.action = #selector(changePage)
        item.tag = index
        return item
    }
    @objc func changePage(_ sender: NSToolbarItem) { selectPage(sender.tag) }
    func selectPage(_ index: Int) {
        (window?.firstResponder as? KeyRecorder)?.cancelRecording()
        window?.makeFirstResponder(nil)
        selectedPage = index
        for (position, page) in pages.enumerated() { page.isHidden = position != index }
        window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(pageIDs[index])
        if pageIDs[index] == "folders" { window?.makeFirstResponder(preferencesFolderTable) }
    }
    var legacyLoginURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/local.maxvoid.HyperKey.login.plist")
    }
    var loginLaunchEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
        }
        return FileManager.default.fileExists(atPath: legacyLoginURL.path)
    }
    func syncPreferences() {
        toggleButton?.state = wantsEnabled ? .on : .off
        loginCheckbox?.state = loginLaunchEnabled ? .on : .off
        hideCheckbox?.state = UserDefaults.standard.bool(forKey: "HideStatusBarIcon") ? .on : .off
        accessibilityNotice?.isHidden = !(wantsEnabled && tap == nil && !AXIsProcessTrusted())
    }
    @objc func changeLoginLaunch(_ sender: NSButton) {
        do {
            if #available(macOS 13.0, *) {
                if sender.state == .on {
                    try SMAppService.mainApp.register()
                    if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
                } else { try SMAppService.mainApp.unregister() }
            } else if sender.state == .on {
                guard let executable = Bundle.main.executableURL else { throw ToolError(message: "Could not locate HyperCaps.") }
                let plist: [String: Any] = ["Label": "local.maxvoid.HyperKey.login", "ProgramArguments": [executable.path], "RunAtLoad": true]
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try FileManager.default.createDirectory(at: legacyLoginURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: legacyLoginURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: legacyLoginURL.path) {
                try FileManager.default.removeItem(at: legacyLoginURL)
            }
        } catch { showError(error) }
        syncPreferences()
    }
    @objc func changeStatusIcon(_ sender: NSButton) {
        let hidden = sender.state == .on
        UserDefaults.standard.set(hidden, forKey: "HideStatusBarIcon")
        item.isVisible = !hidden
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func numberOfRows(in tableView: NSTableView) -> Int { isFolderTable(tableView) ? folders.count : bindings.count }
    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        if isFolderTable(tableView) { return folders.indices.contains(row) ? folders[row].name : nil }
        return bindings.indices.contains(row) ? bindings[row].name : nil
    }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let columnIndex = column.flatMap { tableView.tableColumns.firstIndex(of: $0) } ?? 0
        let cellWidth = tableView.frameOfCell(atColumn: columnIndex, row: row).width
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: cellWidth, height: Self.appRowHeight))
        if isFolderTable(tableView) {
            let folder = folders[row]
            cell.toolTip = folder.path
            if columnIndex == 1 {
                let showsShortcut = tableView.identifier?.rawValue != "preferencesFolders"
                let shortcutWidth: CGFloat = showsShortcut ? 40 : 0
                let path = label(folder.path, frame: NSRect(x: 12, y: Self.listNameFrame.minY,
                                                      width: max(0, cellWidth - 12 - ListGeometry.selectionExtension - shortcutWidth), height: Self.listNameFrame.height), size: 12)
                path.autoresizingMask = [.width]
                path.textColor = .secondaryLabelColor
                path.lineBreakMode = .byTruncatingHead
                path.toolTip = folder.path
                path.alignment = .left
                path.maximumNumberOfLines = 1
                path.attributedStringValue = formattedFolderPath(folder.path)
                cell.addSubview(path)
                if showsShortcut, row < 9 {
                    let hint = label("⇪\(row + 1)", frame: NSRect(
                        x: cellWidth - ListGeometry.selectionExtension - 34,
                        y: Self.listNameFrame.minY, width: 28, height: Self.listNameFrame.height), size: 12)
                    hint.autoresizingMask = [.minXMargin]
                    hint.alignment = .right
                    hint.textColor = .secondaryLabelColor
                    cell.addSubview(hint)
                }
                return cell
            }
            cell.addSubview(makeListIcon(path: folder.path))
            let name = FolderNameField(labelWithString: folder.name)
            configureListName(name, width: cellWidth)
            name.folderTable = tableView
            name.onRename = { [weak self] value in
                guard let self = self, let index = self.folders.firstIndex(where: { $0.path == folder.path }) else { return }
                self.folders[index].name = value
                self.saveFolders()
            }
            cell.addSubview(name)
            return cell
        }
        let binding = bindings[row]
        if columnIndex == 0 {
            cell.addSubview(makeListIcon(path: binding.path))
            let name = NSTextField(labelWithString: binding.name)
            configureListName(name, width: cellWidth)
            cell.addSubview(name)
            return cell
        }
        let prefix = NSTextField(labelWithString: "Caps +")
        let shortcutX = cellWidth - 166 - ListGeometry.selectionExtension
        prefix.frame = NSRect(x: shortcutX, y: Self.listNameFrame.minY, width: 46, height: Self.listNameFrame.height)
        prefix.autoresizingMask = [.minXMargin]
        prefix.font = .systemFont(ofSize: 13)
        cell.addSubview(prefix)
        let recorder = KeyRecorder(frame: NSRect(x: shortcutX + 50, y: 3, width: 116, height: 24))
        recorder.autoresizingMask = [.minXMargin]
        recorder.bezelStyle = .rounded
        recorder.controlSize = .small
        recorder.font = .systemFont(ofSize: 12)
        recorder.title = keyName(binding.key) ?? "Click to set"
        recorder.toolTip = "Click and press a key. Replacing an existing assignment requires confirmation. Escape cancels."
        recorder.onStart = { [weak self] in
            self?.state.reset()
            self?.table?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        recorder.onKey = { [weak self] code in
            guard let self = self,
                  let index = self.bindings.firstIndex(where: { $0.path == binding.path }) else { return false }
            let replacedNames = self.bindings.indices.filter { $0 != index && self.bindings[$0].key == code }
                .map { self.bindings[$0].name }
            if !replacedNames.isEmpty {
                (self.window?.firstResponder as? KeyRecorder)?.cancelRecording()
                let alert = NSAlert()
                alert.messageText = "Replace shortcut?"
                alert.informativeText = "Caps + \(keyName(code) ?? "?") is already assigned to \(replacedNames.joined(separator: ", ")). Replace it with \(binding.name)? \(replacedNames.joined(separator: ", ")) will stay in the list without a shortcut."
                let replaceButton = alert.addButton(withTitle: "Replace")
                replaceButton.keyEquivalent = "\r"
                replaceButton.keyEquivalentModifierMask = []
                let cancelButton = alert.addButton(withTitle: "Cancel")
                cancelButton.keyEquivalent = "\u{1b}"
                cancelButton.keyEquivalentModifierMask = []
                guard alert.runModal() == .alertFirstButtonReturn else { return false }
            }
            for otherIndex in self.bindings.indices where otherIndex != index && self.bindings[otherIndex].key == code {
                self.bindings[otherIndex].key = unassignedKey
            }
            self.bindings[index].key = code
            // Finish recording before reload removes the focused view.
            (self.window?.firstResponder as? KeyRecorder)?.recording = false
            self.save()
            let replacement = replacedNames.isEmpty ? "" : ". Cleared shortcut for \(replacedNames.joined(separator: ", "))"
            self.setStatus("Saved: \(binding.name) → Caps + \(keyName(code) ?? "?")\(replacement)")
            return true
        }
        cell.addSubview(recorder)
        return cell
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard isFolderTable(tableView), folders.indices.contains(row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(folders[row].path, forType: folderDragType)
        return item
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard isFolderTable(tableView), info.draggingSource as? NSTableView === tableView,
              (0...folders.count).contains(row),
              !draggedFolderPaths(info).isEmpty,
              draggedFolderPaths(info).allSatisfy({ path in folders.contains { $0.path == path } }) else { return [] }
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard isFolderTable(tableView), info.draggingSource as? NSTableView === tableView,
              let selection = FolderOrder.move(&folders, paths: draggedFolderPaths(info), to: row) else { return false }
        saveFolders()
        tableView.selectRowIndexes(selection, byExtendingSelection: false)
        if let first = selection.first { tableView.scrollRowToVisible(first) }
        return true
    }
    func draggedFolderPaths(_ info: NSDraggingInfo) -> [String] {
        (info.draggingPasteboard.pasteboardItems ?? []).compactMap { $0.string(forType: folderDragType) }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggle) {
            menuItem.title = tap != nil ? "Disable HyperCaps" : (wantsEnabled ? "Cancel Enabling" : "Enable HyperCaps")
        }
        if menuItem.action == #selector(closeSettings) { return window?.isVisible == true || folderWindow?.isVisible == true }
        return true
    }
    @objc func closeSettings() { (NSApp.modalWindow ?? NSApp.keyWindow)?.performClose(nil) }
    @objc func showSettings() {
        // A visible Preferences window participates in the Dock and Command-Tab.
        NSApp.setActivationPolicy(.regular)
        if window == nil { createWindow() }
        syncPreferences()
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func windowDidResignKey(_ notification: Notification) {
        (window?.firstResponder as? KeyRecorder)?.cancelRecording()
        state.reset()
    }
    func windowWillClose(_ notification: Notification) {
        if let closed = notification.object as? NSWindow, closed === folderWindow {
            if let clip = folderTable?.enclosingScrollView?.contentView {
                NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: clip)
            }
            folderWindow = nil; folderTable = nil
            if window?.isVisible != true { NSApp.setActivationPolicy(.accessory) }
            return
        }
        // Drop the settings view tree while the menu-bar utility runs in the background.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.window?.isVisible == false else { return }
            NSApp.setActivationPolicy(.accessory)
            self.window = nil; self.table = nil; self.preferencesFolderTable = nil
            self.toggleButton = nil; self.loginCheckbox = nil; self.hideCheckbox = nil
            self.accessibilityNotice = nil; self.pages = []
        }
    }
    func configureList(_ list: NSTableView, width: CGFloat, columnID: String, showsHeaders: Bool) {
        list.style = .inset
        let folders = columnID == "folder"
        let first = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(columnID))
        first.title = folders ? "Name" : "Application"
        first.minWidth = 110
        first.maxWidth = width - (folders ? 180 : 190)
        first.width = (folders ? 140 : 240) + ListGeometry.selectionExtension
        first.resizingMask = []
        let second = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(columnID + "Detail"))
        second.title = folders ? "Path" : "Shortcut"
        second.minWidth = folders ? 180 : 190
        second.width = width + ListGeometry.selectionExtension * 2 + (folders ? 0 : ListGeometry.applicationOverflow) - first.width
        second.resizingMask = [.autoresizingMask]
        for column in [first, second] {
            column.headerCell.alignment = .left
            list.addTableColumn(column)
        }
        list.headerView = showsHeaders ? PlainListHeaderView(frame: NSRect(x: 0, y: 0, width: width, height: 28)) : nil
        list.allowsColumnReordering = false
        list.allowsColumnResizing = false
        list.rowHeight = Self.appRowHeight
        list.intercellSpacing = .zero
        list.backgroundColor = showsHeaders ? InterfacePalette.surface : .windowBackgroundColor
        list.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        list.delegate = self
        list.dataSource = self
    }
    func tableViewColumnDidResize(_ notification: Notification) {
        guard let table = notification.object as? NSTableView,
              let header = table.headerView as? PlainListHeaderView else { return }
        header.needsLayout = true
        header.layoutSubtreeIfNeeded()
    }
    func formattedFolderPath(_ path: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingHead
        let text = NSMutableAttributedString(string: path, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor.tertiaryLabelColor
        ])
        let leaf = URL(fileURLWithPath: path).lastPathComponent
        let range = (path as NSString).range(of: leaf, options: .backwards)
        if !leaf.isEmpty, range.location != NSNotFound {
            text.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        }
        return text
    }
    func makeListIcon(path: String, leadingOffset: CGFloat = -6 + ListGeometry.selectionExtension) -> NSImageView {
        let icon = NSImageView(frame: Self.listIconFrame.offsetBy(dx: leadingOffset, dy: 0))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.image = NSWorkspace.shared.icon(forFile: path)
        return icon
    }
    func configureListName(_ name: NSTextField, width: CGFloat, leadingOffset: CGFloat = -6 + ListGeometry.selectionExtension) {
        name.frame = Self.listNameFrame.offsetBy(dx: leadingOffset, dy: 0)
        name.frame.size.width = max(0, width - name.frame.minX - 6)
        name.autoresizingMask = [.width]
        name.font = .systemFont(ofSize: 13)
        name.lineBreakMode = .byTruncatingTail
    }
    func makeListScroll(size: NSSize, headerHeight: CGFloat, bottomMargin: CGFloat = 0, additionalWidth: CGFloat = 0) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: -ListGeometry.selectionExtension, y: 33 + bottomMargin,
                                                width: size.width + ListGeometry.selectionExtension * 2 + additionalWidth,
                                                height: size.height - 33 - headerHeight - bottomMargin))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: ListGeometry.selectionExtension + additionalWidth)
        scroll.borderType = .noBorder
        scroll.backgroundColor = InterfacePalette.surface
        scroll.automaticallyAdjustsContentInsets = false
        return scroll
    }
    func makeListButton(symbol: String, x: CGFloat, y: CGFloat = 2, action: Selector, tip: String) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .light))
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.frame = NSRect(x: x, y: y, width: 28, height: 28)
        button.toolTip = tip
        button.setAccessibilityLabel(tip)
        return button
    }
    func makeFoldersContent(size: NSSize, showsHeaders: Bool = false, bottomMargin: CGFloat = 0) -> (content: NSView, list: FolderTableView) {
        let content: NSView = showsHeaders
            ? ListSurface(frame: NSRect(origin: .zero, size: size))
            : NSView(frame: NSRect(origin: .zero, size: size))
        let scroll = makeListScroll(size: size, headerHeight: 0, bottomMargin: bottomMargin)
        if !showsHeaders { scroll.backgroundColor = .windowBackgroundColor }
        let list = FolderTableView()
        if showsHeaders { list.identifier = NSUserInterfaceItemIdentifier("preferencesFolders") }
        list.openSelection = { [weak self] in self?.openSelectedFolder() }
        configureList(list, width: size.width, columnID: "folder", showsHeaders: showsHeaders)
        list.allowsMultipleSelection = true
        list.target = self; list.doubleAction = #selector(doubleClickFolder)
        list.registerForDraggedTypes([folderDragType])
        list.setDraggingSourceOperationMask(.move, forLocal: true)
        scroll.documentView = list
        content.addSubview(scroll)
        let divider = NSBox(frame: NSRect(x: 0, y: 32 + bottomMargin, width: size.width, height: 1))
        divider.boxType = .separator
        content.addSubview(divider)
        // Include the outer bottom margin when centering controls beneath the divider.
        let buttonY = (32 + bottomMargin - 28) / 2
        content.addSubview(makeListButton(symbol: "plus", x: 8, y: buttonY, action: #selector(addFolder), tip: "Add Folder"))
        content.addSubview(makeListButton(symbol: "minus", x: 38, y: buttonY, action: #selector(removeFolder), tip: "Remove Folder"))
        return (content, list)
    }
    @objc func showFolders() {
        guard !showingLaunchConfirmation else { return }
        if folderWindow == nil {
            let sidePadding: CGFloat = 6
            let topPadding: CGFloat = 6
            let bottomPadding: CGFloat = 0
            let listSize = Self.preferenceSize
            let panelSize = NSSize(width: listSize.width + sidePadding * 2,
                                   height: listSize.height + topPadding + bottomPadding)
            // Match the launch confirmation's native rounded, transparent title-bar shell.
            let panel = FolderPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                                    styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            panel.title = "Folders"
            panel.backgroundColor = .windowBackgroundColor
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                panel.standardWindowButton(kind)?.isHidden = true
            }
            panel.isMovableByWindowBackground = true
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.center()
            let contentSize = NSSize(width: listSize.width, height: listSize.height + bottomPadding)
            let folderContent = makeFoldersContent(size: contentSize, bottomMargin: bottomPadding)
            let list = folderContent.list
            let shell = NSView(frame: NSRect(origin: .zero, size: panelSize))
            folderContent.content.frame.origin = NSPoint(x: sidePadding, y: 0)
            shell.addSubview(folderContent.content)
            panel.contentView = shell
            panel.openSelection = { [weak self] in self?.openSelectedFolder() }
            panel.selectNumber = { [weak self] row in
                guard let self = self, self.folders.indices.contains(row) else { return }
                self.folderTable?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                self.folderTable?.scrollRowToVisible(row)
                self.folderWindow?.makeFirstResponder(self.folderTable)
            }
            folderWindow = panel; folderTable = list
        }
        folderTable?.reloadData()
        if folderTable?.selectedRow == -1, !folders.isEmpty {
            folderTable?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        if let panel = folderWindow, !panel.isVisible {
            panel.previousApplication = NSWorkspace.shared.frontmostApplication
            panel.previousKeyWindow = NSApp.keyWindow
        }
        folderWindow?.makeKeyAndOrderFront(nil)
        folderWindow?.makeFirstResponder(folderTable)
        NSApp.activate(ignoringOtherApps: true)
    }
    func saveFolders() {
        if let data = try? JSONEncoder().encode(folders) { UserDefaults.standard.set(data, forKey: "Folders") }
        folderTable?.reloadData()
        preferencesFolderTable?.reloadData()
    }
    @objc func addFolder() {
        guard let targetTable = activeFolderTable, let owner = targetTable.window else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Folders"
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: owner) { [weak self] response in
            guard let self = self, response == .OK else { return }
            var selected: Int?
            for url in panel.urls {
                let path = url.standardizedFileURL.path
                if let index = self.folders.firstIndex(where: { $0.path == path }) { selected = index; continue }
                self.folders.append(FolderEntry(name: FileManager.default.displayName(atPath: path), path: path))
                selected = self.folders.count - 1
            }
            self.saveFolders()
            if let index = selected {
                targetTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                targetTable.scrollRowToVisible(index)
            }
        }
    }
    @objc func removeFolder() {
        guard let selection = activeFolderTable?.selectedRowIndexes, let first = selection.first else { return }
        for row in selection.reversed() where folders.indices.contains(row) { folders.remove(at: row) }
        saveFolders()
        if !folders.isEmpty { activeFolderTable?.selectRowIndexes(IndexSet(integer: min(first, folders.count - 1)), byExtendingSelection: false) }
    }
    @objc func doubleClickFolder() {
        guard let row = activeFolderTable?.clickedRow, folders.indices.contains(row) else { return }
        openSelectedFolder()
    }
    @objc func openSelectedFolder() {
        guard let targetTable = activeFolderTable, targetTable.window?.attachedSheet == nil,
              !targetTable.selectedRowIndexes.isEmpty else { return }
        let selection = targetTable.selectedRowIndexes
        let selected = selection.compactMap { folders.indices.contains($0) ? folders[$0] : nil }
        for folder in selected {
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &directory), directory.boolValue else {
                showError(ToolError(message: "Could not find \(folder.name). Add the folder again.")); return
            }
        }
        for folder in selected {
            guard NSWorkspace.shared.open(URL(fileURLWithPath: folder.path, isDirectory: true)) else {
                showError(ToolError(message: "Could not open \(folder.name).")); return
            }
        }
        if targetTable === folderTable { folderWindow?.close() }
    }
    @objc func openPermissions() {
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func addBinding() {
        let panel = NSOpenPanel(); panel.title = "Choose an Application"
        panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath:"/Applications")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url, let bundle = Bundle(url:url), bundle.bundleIdentifier != nil else { return }
            let name = (bundle.object(forInfoDictionaryKey:"CFBundleDisplayName") as? String) ?? url.deletingPathExtension().lastPathComponent
            if let index = self.bindings.firstIndex(where: { $0.path == url.path || $0.bundleID == bundle.bundleIdentifier }) {
                self.table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                self.table.scrollRowToVisible(index)
                return
            }
            self.bindings.append(Binding(key:unassignedKey,name:name,path:url.path,bundleID:bundle.bundleIdentifier))
            self.bindings.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            self.save()
            if let index = self.bindings.firstIndex(where: { $0.path == url.path }) {
                self.table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                self.table.scrollRowToVisible(index)
            }
            self.setStatus("Added \(name). Click its shortcut field to assign a key.")
        }
    }
    @objc func removeBinding() {
        guard table.selectedRow >= 0 else { return }; bindings.remove(at:table.selectedRow); save()
    }
    @objc func testSelected() {
        guard table.selectedRow >= 0 else { return }; activate(bindings[table.selectedRow])
    }
    func activate(_ binding: Binding) {
        guard !showingLaunchConfirmation else { return }
        let workspace = NSWorkspace.shared
        let original = URL(fileURLWithPath:binding.path)
        let url = FileManager.default.fileExists(atPath:binding.path) ? original : binding.bundleID.flatMap { workspace.urlForApplication(withBundleIdentifier:$0) }
        guard let target = url else { showError(ToolError(message:"Could not find \(binding.name). Add the application again.")); return }
        let bundleID = Bundle(url: target)?.bundleIdentifier ?? binding.bundleID
        let running = workspace.runningApplications.first {
            !$0.isTerminated && ($0.bundleURL?.standardizedFileURL == target.standardizedFileURL ||
                (bundleID != nil && $0.bundleIdentifier == bundleID))
        }
        if let app = running {
            app.unhide()
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return
        }
        showingLaunchConfirmation = true
        let confirmed = LaunchConfirmation().run(appName: binding.name)
        showingLaunchConfirmation = false
        guard confirmed else { return }
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
        workspace.openApplication(at:target, configuration:configuration) { [weak self] app,error in
            DispatchQueue.main.async {
                if let error = error { self?.showError(error) }
                else { app?.unhide(); app?.activate(options:[.activateAllWindows,.activateIgnoringOtherApps]) }
            }
        }
    }
    func setStatus(_ message: String) {
        item?.button?.toolTip = "HyperCaps — " + message
        // Keep the app menu equivalent in sync with the status menu.
        if let menu = NSApp.mainMenu?.items.first?.submenu,
           let entry = menu.items.first(where: { $0.action == #selector(toggle) }) {
            entry.title = pauseItem?.title ?? "Enable HyperCaps"
        }
        syncPreferences()
        NSLog("HyperCaps: %@", message)
    }
    func showError(_ error: Error) {
        setStatus(error.localizedDescription)
        let alert = NSAlert(); alert.messageText = "HyperCaps"; alert.informativeText = error.localizedDescription
        alert.runModal()
    }
    @objc func toggle() {
        if wantsEnabled || tap != nil {
            wantsEnabled = false; UserDefaults.standard.set(false, forKey: "Enabled"); stop()
        } else {
            wantsEnabled = true; UserDefaults.standard.set(true, forKey: "Enabled")
            if !AXIsProcessTrusted() {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
            start()
        }
    }
    func start() {
        guard tap == nil, !starting else { return }
        guard AXIsProcessTrusted() else {
            setStatus("Waiting for Accessibility access. HyperCaps will enable automatically.")
            pauseItem.title = "Cancel Enabling"
            if permissionTimer == nil {
                permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    if self.wantsEnabled && AXIsProcessTrusted() { self.start() }
                }
            }
            return
        }
        permissionTimer?.invalidate(); permissionTimer = nil
        starting = true; defer { starting = false }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context = context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().handle(type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            wantsEnabled = false
            setStatus("Could not monitor the keyboard. Allow Accessibility access and reopen HyperCaps.")
            pauseItem.title = "Retry Enabling"
            return
        }
        tap = created
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0) else { stop(); return }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        do {
            try mapping.install()
            state.reset()
            CGEvent.tapEnable(tap: created, enable: true)
            setStatus("Enabled.")
            pauseItem.title = "Disable"
        } catch { wantsEnabled = false; stop(); showError(error) }
    }
    @discardableResult func stop() -> Bool {
        permissionTimer?.invalidate(); permissionTimer = nil
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; runLoopSource = nil; state.reset()
        do { try mapping.restore() }
        catch { showError(error); return false }
        setStatus("Disabled. The original Caps Lock mapping has been restored.")
        pauseItem?.title = "Enable HyperCaps"
        return true
    }
    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            wantsEnabled = false
            DispatchQueue.main.async { [weak self] in
                self?.stop(); self?.setStatus("Keyboard monitoring stopped. Caps Lock was restored. Enable HyperCaps to retry.")
            }
            return Unmanaged.passUnretained(event)
        }
        if let recorder = window?.firstResponder as? KeyRecorder, recorder.recording {
            state.reset()
            // Let the focused recorder receive the key without launching an app.
            return event.getIntegerValueField(.keyboardEventKeycode) == 79 ? nil : Unmanaged.passUnretained(event)
        }
        let otherModifier = !event.flags.intersection([.maskControl, .maskAlternate]).isEmpty
        let commandModifier = event.flags.contains(.maskCommand)
        if type == .flagsChanged {
            if event.getIntegerValueField(.keyboardEventKeycode) == 57 { return Unmanaged.passUnretained(event) }
            let result = state.modifierChanged(otherModifier: otherModifier, commandModifier: commandModifier)
            if result.showFolders {
                DispatchQueue.main.async { [weak self] in self?.showFolders() }
            }
            return Unmanaged.passUnretained(event)
        }
        let key = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let selectionPanel = folderWindow.flatMap { panel -> FolderPanel? in
            guard panel.isKeyWindow, panel.attachedSheet == nil,
                  let table = folderTable, panel.firstResponder === table else { return nil }
            return panel
        }
        let result = state.route(key: key, down: type == .keyDown,
                                 repeated: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                                 bound: !showingLaunchConfirmation && bindings.contains { $0.key == key }, otherModifier: otherModifier, commandModifier: commandModifier,
                                 folderSelectionActive: selectionPanel != nil)
        if let number = result.folderNumber, let panel = selectionPanel {
            DispatchQueue.main.async { [weak self, weak panel] in
                guard let self = self, let panel = panel, self.folderWindow === panel,
                      panel.isKeyWindow, panel.attachedSheet == nil,
                      let table = self.folderTable, panel.firstResponder === table else { return }
                panel.selectNumber?(number)
            }
        }
        if result.openFolderSelection, let panel = selectionPanel {
            DispatchQueue.main.async { [weak self, weak panel] in
                guard let self = self, let panel = panel, self.folderWindow === panel,
                      panel.isKeyWindow, panel.attachedSheet == nil,
                      let table = self.folderTable, panel.firstResponder === table else { return }
                panel.openSelection?()
            }
        }
        if result.showFolders {
            DispatchQueue.main.async { [weak self] in self?.showFolders() }
        }
        if result.tap {
            do { try standaloneCaps() } catch { failLater(error) }
        }
        if let code = result.launch, let binding = bindings.first(where: { $0.key == code }) {
            DispatchQueue.main.async { [weak self] in self?.activate(binding) }
        }
        // During Caps navigation, Command must not turn typing into shortcuts.
        if result.stripCommandModifier { event.flags.remove(.maskCommand) }
        return result.swallow ? nil : Unmanaged.passUnretained(event)
    }
    func failLater(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.wantsEnabled = false; self?.stop(); self?.showError(error)
        }
    }
    func standaloneCaps() throws {
        guard tap != nil else { return }
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let properties: [String: Any] = [kTISPropertyInputSourceIsEnabled as String: true,
            kTISPropertyInputSourceIsSelectCapable as String: true,
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String]
        let sources = TISCreateInputSourceList(properties as CFDictionary, false).takeRetainedValue() as! [TISInputSource]
        func isASCII(_ source: TISInputSource) -> Bool {
            guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) else { return false }
            return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
        }
        let target: TISInputSource?
        if isASCII(current) {
            target = sources.first { source in !isASCII(source) && lastNonASCIIInputSource.map { CFEqual(source, $0) } == true }
                ?? sources.first { !isASCII($0) }
        } else {
            lastNonASCIIInputSource = current
            target = TISCopyCurrentASCIICapableKeyboardInputSource().takeRetainedValue()
        }
        if let target = target {
            guard TISSelectInputSource(target) == noErr else { throw ToolError(message: "The input source could not be switched.") }
        } else { throw ToolError(message: "Add both a Latin and a non-Latin input source in System Settings.") }
    }
    @objc func willSleep() { stop() }
    @objc func didWake() { if wantsEnabled { start() } }
    @objc func quitApp() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ownsLifecycle else { return .terminateNow }
        wantsEnabled = false
        return stop() ? .terminateNow : .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) { permissionTimer?.invalidate(); if ownsLifecycle { stop() } }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
// Keep the host alive for Xcode's injected preview renderer as well as normal runs.
application.run()
