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
        guard let tab = WebsiteTabChoice.choose(site, tabs: Self.tabs(in: list), browserFrontmost: browserFrontmost,
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
            """, in: browser))
        return switched.error == nil ? .focused : .failed
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

    // Per window: its id, its selected tab's index and every tab's URL. Windows without
    // tabs (such as Settings) fail inside the try and are left out.
    private static func listSource(_ browser: Browser) -> String {
        let selected = browser.kind == .safari ? "index of current tab of w" : "active tab index of w"
        return script("""
            set output to {}
            repeat with w in (every window)
                try
                    set end of output to {id of w, \(selected), URL of every tab of w}
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
    private static func tabs(in list: NSAppleEventDescriptor) -> [BrowserTab] {
        var tabs: [BrowserTab] = []
        guard list.numberOfItems > 0 else { return tabs }
        for windowIndex in 1...list.numberOfItems {
            guard let window = list.atIndex(windowIndex), window.numberOfItems == 3,
                  let id = window.atIndex(1)?.int32Value, let selected = window.atIndex(2)?.int32Value,
                  let urls = window.atIndex(3), urls.numberOfItems > 0 else { continue }
            for index in 1...urls.numberOfItems {
                // A blank tab's URL is `missing value`, which has no string.
                tabs.append(BrowserTab(window: Int(id), windowIndex: windowIndex, index: index,
                                       url: urls.atIndex(index)?.stringValue ?? "", active: Int(selected) == index))
            }
        }
        return tabs
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
