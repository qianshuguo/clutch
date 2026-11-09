import Cocoa
import CoreServices

// A browser whose tabs Clutch can list and switch to through Apple Events. Safari and
// the Chromium browsers share Chrome's scripting dictionary; others (Firefox, Arc,
// Orion…) only get a new tab.
struct Browser {
    enum Kind { case safari, chromium }
    let bundleID: String
    let kind: Kind
    let name: String

    static func kind(of bundleID: String) -> Kind? {
        switch bundleID {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            return .safari
        case "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
             "org.chromium.Chromium", "com.microsoft.edgemac", "com.microsoft.edgemac.Beta",
             "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary",
             "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly", "com.vivaldi.Vivaldi":
            return .chromium
        default:
            return nil
        }
    }

    // The app web pages open in, and its name ("Safari"), whether or not Clutch can script it.
    static func defaultApplication() -> (url: URL, bundleID: String?, name: String)? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else { return nil }
        let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        return (url, Bundle(url: url)?.bundleIdentifier, name)
    }
    // The default browser, when Clutch can script it.
    static func scriptableDefault() -> Browser? {
        guard let app = defaultApplication(), let bundleID = app.bundleID,
              let scripting = Self.kind(of: bundleID) else { return nil }
        return Browser(bundleID: bundleID, kind: scripting, name: app.name)
    }
    var running: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }
    }
    // Scripting codes: a window's tabs, and a tab's address.
    var tabClass: String { kind == .safari ? "bTab" : "CrTb" }
    var urlProperty: String { kind == .safari ? "pURL" : "URL " }
}

// Lists a running browser's tabs and switches to one. Each Apple Event can wait for a
// busy browser, and the first one for the person to answer the Automation prompt, so
// everything runs on one serial queue off the main thread, which also services the
// keyboard event tap.
//
// The events go to the browser's process, by its process ID, and never through
// AppleScript's `tell application`: compiling or running such a script launches the
// browser whenever it is not running at that moment. A browser that had just quit, or
// was still quitting, was then launched again once per script, and each new Chrome
// said "Something went wrong when opening your profile" while the old one still held
// it. An event to a process that is gone fails instead (procNotFound, connectionInvalid),
// and the caller hands the address to the system.
final class BrowserTabs {
    enum Outcome { case focused, notFound, notPermitted, failed }

    private let queue = DispatchQueue(label: "local.maxvoid.Clutch.browser-tabs", qos: .userInteractive)
    // errAEEventNotPermitted: the person turned Clutch off for this browser under Automation.
    private static let notPermitted = -1743

    // Switches to the tab WebsiteTabChoice picks for `site`, leaving out tabs that belong
    // to `others` inside it. `completion` runs on the main thread, through the run loop
    // rather than the main queue: it may start the launch confirmation's modal session,
    // which would hold up every later main-queue block.
    func focus(_ site: WebsiteScope, others: [WebsiteScope], in browser: Browser, browserFrontmost: Bool,
               completion: @escaping (Outcome) -> Void) {
        let processID = browser.running?.processIdentifier
        queue.async {
            let outcome = processID.map { Self.focus(site, others: others, in: browser, processID: $0,
                                                     browserFrontmost: browserFrontmost) } ?? .failed
            performOnMainRunLoop { completion(outcome) }
        }
    }
    private static func focus(_ site: WebsiteScope, others: [WebsiteScope], in browser: Browser, processID: pid_t,
                              browserFrontmost: Bool) -> Outcome {
        let permission = Self.permission(for: processID)
        guard permission != notPermitted else { return .notPermitted }
        guard permission == 0 else { return .failed }
        let events = ProcessEvents(processID: processID)
        let listed: [ListedWindow]
        do { listed = try windows(of: browser, through: events) } catch {
            return error.code == notPermitted ? .notPermitted : .failed
        }
        // Only the window used last counts: a matching tab in another window is left
        // alone, and without one there the address opens in a new tab of that window.
        // When that window cannot be told apart, every window counts, front first.
        var windows = listed
        if let last = lastUsed(windows, processID: processID) { windows = [windows[last]] }
        guard let tab = WebsiteTabChoice.choose(site, tabs: tabs(of: windows), browserFrontmost: browserFrontmost,
                                                others: others),
              let window = windows.first(where: { $0.id == tab.window }) else { return .notFound }
        do {
            let target = window.specifier
            try? events.set(.property("pmnd", of: target), to: NSAppleEventDescriptor(boolean: false))
            switch browser.kind {
            case .safari:
                try events.set(.property("cTab", of: target), to: .index(browser.tabClass, tab.index, of: target))
            case .chromium:
                try events.set(.property("acTI", of: target), to: NSAppleEventDescriptor(int32: Int32(tab.index)))
            }
            try bringForward(target, through: events, processID: processID)
        } catch {
            return error.code == notPermitted ? .notPermitted : .failed
        }
        return .focused
    }

    // Puts `window` first among the browser's windows, then raises it. `set index` only
    // reorders the browser's own windows: macOS keeps the window that was key before,
    // and activating the browser brings that one back in front of the tab just chosen.
    // Raising the window through Accessibility makes it the main window, so activation
    // keeps it in front and typing goes to it.
    private static func bringForward(_ window: NSAppleEventDescriptor, through events: ProcessEvents,
                                     processID: pid_t) throws {
        try events.set(.property("pidx", of: window), to: NSAppleEventDescriptor(int32: 1))
        let title = try? events.get(.property("pnam", of: window))?.stringValue
        let frame = (try? events.get(.property("pbnd", of: window))).flatMap(screenFrame(from:))
        raiseWindow(processID: processID, title: title, frame: frame)
    }

    // Finds the window `title` and `frame` (top-left screen coordinates like
    // Accessibility's) describe among the browser's Accessibility windows, by its frame
    // and then its title, and makes it the front, main window.
    private static func raiseWindow(processID: pid_t, title: String?, frame: CGRect?) {
        let application = AXQuery.application(processID)
        guard let windows = AXQuery.value(application, kAXWindowsAttribute) as? [AXUIElement],
              !windows.isEmpty else { return }
        let titled = windows.filter { title != nil && (AXQuery.value($0, kAXTitleAttribute) as? String) == title }
        let framed = frame.map { target in windows.filter { window in
            AXQuery.frame(of: window).map { WindowLayout.same($0, target) } ?? false
        } } ?? []
        let both = framed.filter { window in titled.contains { CFEqual($0, window) } }
        let chosen = both.first ?? (framed.count == 1 ? framed.first : nil) ?? (titled.count == 1 ? titled.first : nil)
        guard let window = chosen else { return }
        AXQuery.raise(window, in: application)
    }

    enum OpenOutcome { case opened, notPermitted, failed }

    // Opens `url` in a new tab of the window used last (see lastUsed), or of the front
    // window when that one cannot be told apart, and brings that window forward. Handing the
    // address to the system instead lets the browser pick a window, and with several
    // windows macOS can then bring a different one to the front. A browser with no
    // window gets a new one. `completion` runs on the main run loop.
    func open(_ url: URL, in browser: Browser, completion: @escaping (OpenOutcome) -> Void) {
        let processID = browser.running?.processIdentifier
        queue.async {
            let outcome = processID.map { Self.open(url, in: browser, processID: $0) } ?? .failed
            performOnMainRunLoop { completion(outcome) }
        }
    }
    private static func open(_ url: URL, in browser: Browser, processID: pid_t) -> OpenOutcome {
        let permission = Self.permission(for: processID)
        guard permission != notPermitted else { return .notPermitted }
        guard permission == 0 else { return .failed }
        let events = ProcessEvents(processID: processID)
        let address = NSAppleEventDescriptor(string: url.absoluteString)
        do {
            // Windows with tabs, front first; Settings and other windows are left out.
            let windows = try Self.windows(of: browser, through: events)
            let target: NSAppleEventDescriptor
            if let window = lastUsed(windows, processID: processID).map({ windows[$0] }) ?? windows.first {
                target = window.specifier
                try? events.set(.property("pmnd", of: target), to: NSAppleEventDescriptor(boolean: false))
                let properties = NSAppleEventDescriptor.record()
                properties.setDescriptor(address, forKeyword: fourCharCode(browser.urlProperty))
                let tab = try events.make(browser.tabClass, at: .end(of: .every(browser.tabClass, of: target)),
                                          properties: properties)
                switch browser.kind {
                case .safari:
                    let made = tab ?? .object(browser.tabClass, form: "indx", .ordinal("last"), of: target)
                    try events.set(.property("cTab", of: target), to: made)
                case .chromium:
                    let count = try events.count(browser.tabClass, in: target)
                    try events.set(.property("acTI", of: target), to: NSAppleEventDescriptor(int32: Int32(count)))
                }
            } else {
                switch browser.kind {
                case .safari:
                    let properties = NSAppleEventDescriptor.record()
                    properties.setDescriptor(address, forKeyword: fourCharCode("pURL"))
                    try events.make("docu", properties: properties)
                case .chromium:
                    try events.make("cwin")
                    try events.set(.property("URL ", of: .property("acTa", of: .index("cwin", 1, of: .application))),
                                   to: address)
                }
                target = .index("cwin", 1, of: .application)
            }
            try bringForward(target, through: events, processID: processID)
        } catch {
            return error.code == notPermitted ? .notPermitted : .failed
        }
        return .opened
    }

    // Asks for Automation access to the browser the first time (the system prompt names
    // Clutch and uses NSAppleEventsUsageDescription), and waits for the answer without
    // the events' timeout. 0 when allowed.
    private static func permission(for processID: pid_t) -> Int {
        let target = NSAppleEventDescriptor(processIdentifier: processID)
        guard let address = target.aeDesc else { return -1 }
        // typeWildCard ('****'): any event.
        let any = FourCharCode(0x2A2A2A2A)
        return Int(AEDeterminePermissionToAutomateTarget(address, any, any, true))
    }

    // One window with tabs, in the browser's own order: its id, its selected tab's
    // index, every tab's URL, and its bounds and name to find it among the
    // Accessibility windows.
    private struct ListedWindow {
        let id: Int
        let specifier: NSAppleEventDescriptor
        let selected: Int
        let urls: [String]
        let frame: CGRect?
        let title: String?
    }
    // Windows whose tabs cannot be read (such as Settings) are left out. An error that
    // means the browser cannot be reached at all (gone, not permitted, busy) is thrown.
    private static func windows(of browser: Browser, through events: ProcessEvents) throws -> [ListedWindow] {
        guard let ids = try events.get(.property("ID  ", of: .every("cwin", of: .application))),
              ids.numberOfItems > 0 else { return [] }
        var windows: [ListedWindow] = []
        for item in 1...ids.numberOfItems {
            guard let idDescriptor = ids.atIndex(item) else { continue }
            let window = NSAppleEventDescriptor.id("cwin", idDescriptor, of: .application)
            do {
                let selected: NSAppleEventDescriptor?
                switch browser.kind {
                case .safari: selected = try events.get(.property("pidx", of: .property("cTab", of: window)))
                case .chromium: selected = try events.get(.property("acTI", of: window))
                }
                guard let index = selected?.int32Value,
                      let urls = try events.get(.property(browser.urlProperty, of: .every(browser.tabClass, of: window))),
                      urls.numberOfItems > 0 else { continue }
                // A blank tab's URL is `missing value`, which has no string.
                let addresses = (1...urls.numberOfItems).map { urls.atIndex($0)?.stringValue ?? "" }
                let bounds = try? events.get(.property("pbnd", of: window))
                let title = try? events.get(.property("pnam", of: window))?.stringValue
                windows.append(ListedWindow(id: Int(idDescriptor.int32Value), specifier: window, selected: Int(index),
                                            urls: addresses, frame: bounds.flatMap(screenFrame(from:)), title: title))
            } catch let error where ProcessEvents.unreachable(error) {
                throw error
            } catch {
                continue
            }
        }
        return windows
    }
    // `windows` in order: 1 is the front window.
    private static func tabs(of windows: [ListedWindow]) -> [BrowserTab] {
        windows.enumerated().flatMap { position, window in
            window.urls.enumerated().map { offset, url in
                BrowserTab(window: window.id, windowIndex: position + 1, index: offset + 1,
                           url: url, active: window.selected == offset + 1)
            }
        }
    }
    // Which listed window was used last: the one the browser would bring forward. Chrome's
    // scripting order, and Accessibility's list of windows, do not follow use: with windows
    // of the same size, or on other Spaces or in full screen, the window used last can come
    // second. The browser's focused window through Accessibility is the one used last, even
    // while the browser is in the background. It is found among the listed windows by its
    // title (the selected tab's), then by its frame when titles repeat; nil when that
    // leaves none or more than one.
    private static func lastUsed(_ windows: [ListedWindow], processID: pid_t) -> Int? {
        guard !windows.isEmpty else { return nil }
        let application = AXQuery.application(processID)
        guard let focused = AXQuery.focusedWindow(of: application) else { return nil }
        let title = AXQuery.value(focused, kAXTitleAttribute) as? String
        let frame = AXQuery.frame(of: focused)
        var candidates = windows.indices.filter { index in
            guard let listed = windows[index].title, let title = title, !listed.isEmpty, !title.isEmpty else { return false }
            return listed == title || title.hasPrefix(listed) || listed.hasPrefix(title)
        }
        if candidates.count != 1, let frame = frame {
            let pool = candidates.isEmpty ? Array(windows.indices) : candidates
            candidates = pool.filter { index in windows[index].frame.map { listed in WindowLayout.same(listed, frame) } ?? false }
        }
        return candidates.count == 1 ? candidates.first : nil
    }
    // A window's bounds as a frame in Accessibility's top-left screen coordinates. Cocoa
    // scripting replies with a QuickDraw rectangle (top, left, bottom, right); a list is
    // AppleScript's order (left, top, right, bottom).
    private static func screenFrame(from bounds: NSAppleEventDescriptor) -> CGRect? {
        let left, top, right, bottom: CGFloat
        if bounds.descriptorType == typeQDRectangle, bounds.data.count == 8 {
            let edges = bounds.data.withUnsafeBytes { raw in (0..<4).map { CGFloat(raw.load(fromByteOffset: $0 * 2, as: Int16.self)) } }
            (top, left, bottom, right) = (edges[0], edges[1], edges[2], edges[3])
        } else if let list = bounds.coerce(toDescriptorType: typeAEList), list.numberOfItems == 4 {
            let edges = (1...4).map { CGFloat(list.atIndex($0)?.int32Value ?? 0) }
            (left, top, right, bottom) = (edges[0], edges[1], edges[2], edges[3])
        } else {
            return nil
        }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

// MARK: Apple Events to one process

func fourCharCode(_ code: String) -> FourCharCode {
    code.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
}

private extension Error {
    // The Apple Event error number.
    var code: Int { (self as NSError).code }
}

// Sends Apple Events to one process, by its process ID, waiting at most 3 seconds for
// each reply: a hung browser makes the shortcut open a new tab after 3 seconds instead
// of the default two minutes. A failed event, or a reply carrying an error, throws an
// NSError whose code is the Apple Event error number.
private struct ProcessEvents {
    let target: NSAppleEventDescriptor
    init(processID: pid_t) { target = NSAppleEventDescriptor(processIdentifier: processID) }

    // Errors after which no further event will get through: the process is gone, or
    // Clutch may not send it events, or it did not answer in time.
    static func unreachable(_ error: Error) -> Bool {
        [Int(procNotFound), Int(connectionInvalid), Int(errAETimeout), -1743].contains(error.code)
    }

    @discardableResult
    func send(_ eventClass: String, _ eventID: String, _ direct: NSAppleEventDescriptor? = nil,
              _ parameters: [String: NSAppleEventDescriptor] = [:]) throws -> NSAppleEventDescriptor? {
        let event = NSAppleEventDescriptor(eventClass: fourCharCode(eventClass), eventID: fourCharCode(eventID),
                                           targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        if let direct = direct { event.setParam(direct, forKeyword: keyDirectObject) }
        for (key, value) in parameters { event.setParam(value, forKeyword: fourCharCode(key)) }
        let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 3)
        if let number = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value, number != 0 {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(number))
        }
        return reply.paramDescriptor(forKeyword: keyDirectObject)
    }
    func get(_ specifier: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor? {
        try send("core", "getd", specifier)
    }
    func set(_ specifier: NSAppleEventDescriptor, to value: NSAppleEventDescriptor) throws {
        try send("core", "setd", specifier, ["data": value])
    }
    func count(_ kind: String, in container: NSAppleEventDescriptor) throws -> Int {
        Int(try send("core", "cnte", container, ["kocl": NSAppleEventDescriptor(typeCode: fourCharCode(kind))])?.int32Value ?? 0)
    }
    // `make new <kind> [at <location>] [with properties <properties>]`; the reply is
    // the new object when the browser gives one.
    @discardableResult
    func make(_ kind: String, at location: NSAppleEventDescriptor? = nil,
              properties: NSAppleEventDescriptor? = nil) throws -> NSAppleEventDescriptor? {
        var parameters = ["kocl": NSAppleEventDescriptor(typeCode: fourCharCode(kind))]
        if let location = location { parameters["insh"] = location }
        if let properties = properties { parameters["prdt"] = properties }
        return try send("core", "crel", nil, parameters)
    }
}

// Object specifiers, as AppleScript would build them: `window id 3`, `URL of every tab
// of …`, `end of every tab of …`.
private extension NSAppleEventDescriptor {
    static var application: NSAppleEventDescriptor { .null() }

    static func object(_ kind: String, form: String, _ data: NSAppleEventDescriptor,
                       of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: fourCharCode(kind)), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: fourCharCode(form)), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(data, forKeyword: AEKeyword(keyAEKeyData))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        return record.coerce(toDescriptorType: typeObjectSpecifier) ?? record
    }
    static func ordinal(_ code: String) -> NSAppleEventDescriptor {
        var value = fourCharCode(code)
        return NSAppleEventDescriptor(descriptorType: typeAbsoluteOrdinal, bytes: &value,
                                      length: MemoryLayout<FourCharCode>.size) ?? .null()
    }
    static func every(_ kind: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        object(kind, form: "indx", .ordinal("all "), of: container)
    }
    static func index(_ kind: String, _ index: Int, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        object(kind, form: "indx", NSAppleEventDescriptor(int32: Int32(index)), of: container)
    }
    static func id(_ kind: String, _ id: NSAppleEventDescriptor, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        object(kind, form: "ID  ", id, of: container)
    }
    static func property(_ code: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        object("prop", form: "prop", NSAppleEventDescriptor(typeCode: fourCharCode(code)), of: container)
    }
    static func end(of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(container, forKeyword: keyAEObject)
        record.setDescriptor(NSAppleEventDescriptor(enumCode: fourCharCode("end ")), forKeyword: keyAEPosition)
        return record.coerce(toDescriptorType: typeInsertionLoc) ?? record
    }
}
