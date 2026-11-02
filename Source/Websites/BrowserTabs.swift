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
}

// Lists a running browser's tabs and switches to one. Each Apple Event can wait for a
// busy browser, and the first one for the person to answer the Automation prompt, so
// everything runs on one serial queue off the main thread, which also services the
// keyboard event tap. NSAppleScript objects are made and run only on that queue, one
// at a time. Callers check that the browser is running: scripting a browser that is
// not would launch it.
final class BrowserTabs {
    enum Outcome { case focused, notFound, notPermitted, failed }

    private let queue = DispatchQueue(label: "local.maxvoid.Clutch.browser-tabs", qos: .userInteractive)
    // errAEEventNotPermitted: the person turned Clutch off for this browser under Automation.
    private static let notPermitted = -1743
    // Compiled tab-listing scripts by browser; used only on `queue`.
    private var listScripts: [String: NSAppleScript] = [:]

    // Switches to the tab WebsiteTabChoice picks for `site`, leaving out tabs that belong
    // to `others` inside it. `completion` runs on the main thread, through the run loop
    // rather than the main queue: it may start the launch confirmation's modal session,
    // which would hold up every later main-queue block.
    func focus(_ site: WebsiteScope, others: [WebsiteScope], in browser: Browser, browserFrontmost: Bool,
               completion: @escaping (Outcome) -> Void) {
        queue.async { [self] in
            let outcome = focus(site, others: others, in: browser, browserFrontmost: browserFrontmost)
            performOnMainRunLoop { completion(outcome) }
        }
    }
    private func focus(_ site: WebsiteScope, others: [WebsiteScope], in browser: Browser,
                       browserFrontmost: Bool) -> Outcome {
        let permission = Self.permission(for: browser)
        guard permission != Self.notPermitted else { return .notPermitted }
        guard permission == 0 else { return .failed }
        let script = listScripts[browser.bundleID] ?? NSAppleScript(source: Self.listSource(browser))
        listScripts[browser.bundleID] = script
        guard let compiled = script else { return .failed }
        let listed = Self.execute(compiled)
        if listed.error == Self.notPermitted { return .notPermitted }
        guard listed.error == nil, let list = listed.result else { return .failed }
        // Only the window used last counts: a matching tab in another window is left
        // alone, and without one there the address opens in a new tab of that window.
        // When that window cannot be told apart, every window counts, front first.
        var windows = Self.windows(in: list)
        if let pid = browser.running?.processIdentifier, let last = Self.lastUsed(windows, processID: pid) {
            windows = [windows[last]]
        }
        guard let tab = WebsiteTabChoice.choose(site, tabs: Self.tabs(of: windows), browserFrontmost: browserFrontmost,
                                                others: others) else { return .notFound }
        let select = browser.kind == .safari ? "set current tab of w to tab \(tab.index) of w"
                                             : "set active tab index of w to \(tab.index)"
        let restore = browser.kind == .safari ? "set miniaturized of w to false" : "set minimized of w to false"
        let switched = Self.run(Self.script("""
            set w to window id \(tab.window)
            try
                \(restore)
            end try
            \(select)
            set index of w to 1
            return {name of w, bounds of w}
            """, in: browser))
        guard switched.error == nil else { return .failed }
        // `set index` only reorders the browser's own windows: macOS keeps the window that
        // was key before, and activating the browser brings that one back in front of the
        // tab just chosen. Raising the window through Accessibility makes it the main
        // window, so activation keeps it in front and typing goes to it.
        if let pid = browser.running?.processIdentifier, let reply = switched.result {
            Self.raiseWindow(processID: pid, reply: reply)
        }
        return .focused
    }

    // Finds the window the switch script described ({name, {left, top, right, bottom}},
    // top-left screen coordinates like Accessibility's) among the browser's Accessibility
    // windows, by its frame and then its title, and makes it the front, main window.
    private static func raiseWindow(processID: pid_t, reply: NSAppleEventDescriptor) {
        guard reply.numberOfItems == 2 else { return }
        let title = reply.atIndex(1)?.stringValue
        let frame = reply.atIndex(2).flatMap(screenFrame(from:))
        let application = AXQuery.application(processID)
        guard let windows = AXQuery.value(application, kAXWindowsAttribute) as? [AXUIElement],
              !windows.isEmpty else { return }
        let titled = windows.filter { title != nil && (AXQuery.value($0, kAXTitleAttribute) as? String) == title }
        let framed = frame.map { target in windows.filter { window in
            axFrame(of: window).map { nearlyEqual($0, target) } ?? false
        } } ?? []
        let both = framed.filter { window in titled.contains { CFEqual($0, window) } }
        let chosen = both.first ?? (framed.count == 1 ? framed.first : nil) ?? (titled.count == 1 ? titled.first : nil)
        guard let window = chosen else { return }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(application, kAXFocusedWindowAttribute as CFString, window)
    }
    private static func axFrame(of window: AXUIElement) -> CGRect? {
        guard let positionValue = AXQuery.value(window, kAXPositionAttribute),
              let sizeValue = AXQuery.value(window, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    enum OpenOutcome { case opened, notPermitted, failed }

    // Opens `url` in a new tab of the window used last (see lastUsed), or of the front
    // window when that one cannot be told apart, and brings that window forward. Handing the
    // address to the system instead lets the browser pick a window, and with several
    // windows macOS can then bring a different one to the front. A browser with no
    // window gets a new one. `completion` runs on the main run loop.
    func open(_ url: URL, in browser: Browser, completion: @escaping (OpenOutcome) -> Void) {
        queue.async { [self] in
            let outcome = open(url, in: browser)
            performOnMainRunLoop { completion(outcome) }
        }
    }
    private func open(_ url: URL, in browser: Browser) -> OpenOutcome {
        let permission = Self.permission(for: browser)
        guard permission != Self.notPermitted else { return .notPermitted }
        guard permission == 0 else { return .failed }
        let preferred = lastUsedWindow(in: browser).map { "try\n    set target to window id \($0)\nend try" } ?? ""
        let address = url.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let body: String
        switch browser.kind {
        case .chromium:
            body = """
                set target to missing value
                \(preferred)
                if target is missing value then
                    repeat with w in (every window)
                        try
                            if (count of tabs of w) > 0 then
                                set target to contents of w
                                exit repeat
                            end if
                        end try
                    end repeat
                end if
                if target is missing value then
                    make new window
                    set target to window 1
                    set URL of active tab of target to "\(address)"
                else
                    try
                        set minimized of target to false
                    end try
                    tell target to make new tab with properties {URL:"\(address)"}
                    set active tab index of target to (count of tabs of target)
                end if
                set index of target to 1
                return {name of target, bounds of target}
                """
        case .safari:
            body = """
                set target to missing value
                \(preferred)
                if target is missing value then
                    repeat with w in (every window)
                        try
                            if (count of tabs of w) > 0 then
                                set target to contents of w
                                exit repeat
                            end if
                        end try
                    end repeat
                end if
                if target is missing value then
                    make new document with properties {URL:"\(address)"}
                    set target to window 1
                else
                    try
                        set miniaturized of target to false
                    end try
                    tell target
                        set newTab to make new tab at end of tabs with properties {URL:"\(address)"}
                        set current tab to newTab
                    end tell
                end if
                set index of target to 1
                return {name of target, bounds of target}
                """
        }
        let opened = Self.run(Self.script(body, in: browser))
        if opened.error == Self.notPermitted { return .notPermitted }
        guard opened.error == nil else { return .failed }
        if let pid = browser.running?.processIdentifier, let reply = opened.result {
            Self.raiseWindow(processID: pid, reply: reply)
        }
        return .opened
    }

    // Asks for Automation access to the browser the first time (the system prompt names
    // Clutch and uses NSAppleEventsUsageDescription), and waits for the answer without
    // the scripts' timeout. 0 when allowed.
    private static func permission(for browser: Browser) -> Int {
        let target = NSAppleEventDescriptor(bundleIdentifier: browser.bundleID)
        guard let address = target.aeDesc else { return -1 }
        // typeWildCard ('****'): any event.
        let any = FourCharCode(0x2A2A2A2A)
        return Int(AEDeterminePermissionToAutomateTarget(address, any, any, true))
    }

    // Per window: its id, its selected tab's index, every tab's URL, and its bounds and
    // name to find it among the Accessibility windows. Windows without tabs (such as
    // Settings) fail inside the try and are left out.
    private static func listSource(_ browser: Browser) -> String {
        let selected = browser.kind == .safari ? "index of current tab of w" : "active tab index of w"
        return script("""
            set output to {}
            repeat with w in (every window)
                try
                    set end of output to {id of w, \(selected), URL of every tab of w, bounds of w, name of w}
                end try
            end repeat
            return output
            """, in: browser)
    }
    // A hung browser makes the shortcut open a new tab after 3 seconds instead of
    // AppleScript's default two minutes.
    private static func script(_ body: String, in browser: Browser) -> String {
        """
        with timeout of 3 seconds
        tell application id "\(browser.bundleID)"
        \(body)
        end tell
        end timeout
        """
    }
    // One window as the listing script reports it, in the browser's own order.
    private struct ListedWindow {
        let id: Int
        let selected: Int
        let urls: [String]
        let frame: CGRect?
        let title: String?
    }
    private static func windows(in list: NSAppleEventDescriptor) -> [ListedWindow] {
        var windows: [ListedWindow] = []
        guard list.numberOfItems > 0 else { return windows }
        for item in 1...list.numberOfItems {
            guard let window = list.atIndex(item), window.numberOfItems >= 3,
                  let id = window.atIndex(1)?.int32Value, let selected = window.atIndex(2)?.int32Value,
                  let urls = window.atIndex(3), urls.numberOfItems > 0 else { continue }
            // A blank tab's URL is `missing value`, which has no string.
            let addresses = (1...urls.numberOfItems).map { urls.atIndex($0)?.stringValue ?? "" }
            windows.append(ListedWindow(id: Int(id), selected: Int(selected), urls: addresses,
                                        frame: window.numberOfItems >= 4 ? window.atIndex(4).flatMap(screenFrame(from:)) : nil,
                                        title: window.numberOfItems >= 5 ? window.atIndex(5)?.stringValue : nil))
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
    // The id of the window used last, through the listing script; nil when it cannot be
    // told apart. Runs on `queue`.
    private func lastUsedWindow(in browser: Browser) -> Int? {
        let script = listScripts[browser.bundleID] ?? NSAppleScript(source: Self.listSource(browser))
        listScripts[browser.bundleID] = script
        guard let compiled = script, let pid = browser.running?.processIdentifier else { return nil }
        let listed = Self.execute(compiled)
        guard listed.error == nil, let list = listed.result else { return nil }
        let windows = Self.windows(in: list)
        return Self.lastUsed(windows, processID: pid).map { windows[$0].id }
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
        guard let focused = AXQuery.element(application, kAXFocusedWindowAttribute)
                ?? AXQuery.element(application, kAXMainWindowAttribute) else { return nil }
        let title = AXQuery.value(focused, kAXTitleAttribute) as? String
        let frame = axFrame(of: focused)
        var candidates = windows.indices.filter { index in
            guard let listed = windows[index].title, let title = title, !listed.isEmpty, !title.isEmpty else { return false }
            return listed == title || title.hasPrefix(listed) || listed.hasPrefix(title)
        }
        if candidates.count != 1, let frame = frame {
            let pool = candidates.isEmpty ? Array(windows.indices) : candidates
            candidates = pool.filter { index in windows[index].frame.map { listed in nearlyEqual(listed, frame) } ?? false }
        }
        return candidates.count == 1 ? candidates.first : nil
    }
    private static func nearlyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2
            && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }
    // AppleScript bounds, {left, top, right, bottom}, as a frame in Accessibility's
    // top-left screen coordinates.
    private static func screenFrame(from bounds: NSAppleEventDescriptor) -> CGRect? {
        guard bounds.numberOfItems == 4 else { return nil }
        let edges = (1...4).map { CGFloat(bounds.atIndex($0)?.int32Value ?? 0) }
        return CGRect(x: edges[0], y: edges[1], width: edges[2] - edges[0], height: edges[3] - edges[1])
    }

    private static func run(_ source: String) -> (result: NSAppleEventDescriptor?, error: Int?) {
        guard let script = NSAppleScript(source: source) else { return (nil, -1) }
        return execute(script)
    }
    private static func execute(_ script: NSAppleScript) -> (result: NSAppleEventDescriptor?, error: Int?) {
        var info: NSDictionary?
        let result: NSAppleEventDescriptor? = script.executeAndReturnError(&info)
        if let info = info { return (nil, (info[NSAppleScript.errorNumber] as? Int) ?? -1) }
        return (result, nil)
    }
}
