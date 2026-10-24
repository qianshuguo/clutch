import Foundation

// One Websites entry, like a browser bookmark: a name and an address. Caps + `keys` goes
// to the page at `url`. When the default browser already has a matching tab open, it
// switches to that tab; otherwise it opens `url`. Foundation-only, so the pure tests can
// compile it.
struct WebsiteEntry: Codable, Equatable, KeyShortcut {
    // Normalized by WebsiteAddress.normalize ("https://github.com/qianshuguo/clutch").
    // It also identifies the entry.
    var url: String
    // The name the person gave it ("GitHub"); empty shows the address instead.
    var title: String
    // Caps + these keys, in order, from any app (⇪G, ⇪G H, ⇪G H C).
    var keys: [UInt16]
    // Include subdomains in the Add/Edit sheet: "ctrip.com" also matches
    // flight.ctrip.com. On unless the person turned it off.
    var includesSubdomains: Bool

    init(url: String, title: String = "", keys: [UInt16] = [], includesSubdomains: Bool = true) {
        self.url = url; self.title = title; self.keys = keys; self.includesSubdomains = includesSubdomains
    }

    // What the entry matches: "github.com" is the whole site,
    // "github.com/qianshuguo/clutch" that page and below.
    var address: String { WebsiteAddress(url)?.display ?? url }
    // The pages Caps goes to; nil for an address that no longer parses.
    var scope: WebsiteScope? {
        WebsiteAddress(url).map { WebsiteScope($0, includesSubdomains: includesSubdomains) }
    }
    // What the list, the HUD card and the launch confirmation show: the name, or the
    // address when it has none. The list shows the full address on hover.
    var name: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? address : trimmed
    }

    // Saved under "shortcut", left out when there is none, like folders. "title" is left
    // out when empty, and "subdomains" is saved only when off, so websites saved before
    // either existed load unchanged and include subdomains.
    private enum CodingKeys: String, CodingKey { case url, title, keys = "shortcut", includesSubdomains = "subdomains" }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        keys = try container.decodeIfPresent([UInt16].self, forKey: .keys) ?? []
        includesSubdomains = try container.decodeIfPresent(Bool.self, forKey: .includesSubdomains) ?? true
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        if !title.isEmpty { try container.encode(title, forKey: .title) }
        if !keys.isEmpty { try container.encode(keys, forKey: .keys) }
        if !includesSubdomains { try container.encode(false, forKey: .includesSubdomains) }
    }
}

// A web address as Websites compares it: the host (lowercased, without a leading
// "www."), the port, and the path (lowercased, without trailing "/"; empty for the
// whole site). The scheme, query and fragment are ignored, so http and https,
// "?tab=…" and "#inbox" all count as the same page.
struct WebsiteAddress: Equatable {
    let host: String
    let port: Int?
    let path: String

    // nil for anything that is not an http(s) page (chrome://newtab, about:blank, file://).
    init?(_ string: String) {
        guard let components = URLComponents(string: string),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let rawHost = components.host, !rawHost.isEmpty else { return nil }
        var host = rawHost.lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = components.percentEncodedPath.lowercased()
        while path.hasSuffix("/") { path.removeLast() }
        self.host = host
        self.port = components.port
        self.path = path
    }

    var display: String { host + (port.map { ":\($0)" } ?? "") + (path.removingPercentEncoding ?? path) }

    // localhost and IP addresses have no subdomains to include.
    var hasSubdomains: Bool {
        host != "localhost" && host.contains(".") && !host.allSatisfy { $0.isNumber || $0 == "." }
    }

    // Only a host: every page of that site, with or without "www.". With a path: that
    // page and the pages below it, so "/a/b" matches "/a/b" and "/a/b/c" but not "/a/bc".
    // Subdomains (gist.github.com) count only with `includingSubdomains`.
    func matches(_ page: WebsiteAddress, includingSubdomains: Bool = false) -> Bool {
        let sameHost = page.host == host
            || (includingSubdomains && hasSubdomains && page.host.hasSuffix("." + host))
        guard sameHost, page.port == port else { return false }
        guard !path.isEmpty else { return true }
        return page.path == path || page.path.hasPrefix(path + "/")
    }

    // Typed or pasted text as the address to save: "github.com" → "https://github.com",
    // "localhost:3000" → "http://localhost:3000". nil for text that is not a web address.
    static func normalize(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else { return nil }
        let typedScheme = trimmed.range(of: "://") != nil
        guard var components = URLComponents(string: typedScheme ? trimmed : "https://" + trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        // A local server or an IP address has no dot-separated domain, and usually no https.
        let local = host == "localhost" || host.allSatisfy { $0.isNumber || $0 == "." }
        guard local || (host.contains(".") && !host.hasPrefix(".") && !host.hasSuffix(".")) else { return nil }
        components.scheme = local && !typedScheme ? "http" : scheme
        components.host = host
        if components.query == nil && components.fragment == nil {
            var path = components.percentEncodedPath
            while path.hasSuffix("/") { path.removeLast() }
            components.percentEncodedPath = path
        }
        return components.string
    }
}

// The pages one website goes to: its address, and whether subdomains count.
struct WebsiteScope: Equatable {
    let address: WebsiteAddress
    let includesSubdomains: Bool

    init(_ address: WebsiteAddress, includesSubdomains: Bool = false) {
        self.address = address
        self.includesSubdomains = includesSubdomains && address.hasSubdomains
    }
    func matches(_ page: WebsiteAddress) -> Bool {
        address.matches(page, includingSubdomains: includesSubdomains)
    }
    // Another website inside this one ("flight.ctrip.com" or "ctrip.com/hotels" inside
    // "ctrip.com"): the pages it matches are its own, not this one's.
    func contains(_ other: WebsiteScope) -> Bool {
        other.address != address && matches(other.address)
    }
}

// One open tab, as the browser lists it. `window` is the browser's window id, which
// stays the same while windows change order; `windowIndex` is the window's place
// front to back (1 is the front window); `index` is the tab's place in its window, from 1.
struct BrowserTab: Equatable {
    var window: Int
    var windowIndex: Int
    var index: Int
    var url: String
    var active: Bool
}

enum WebsiteTabChoice {
    // The tab Caps goes to for `site`, or nil when none matches (a new tab opens).
    // `others` are the other saved websites: a tab one of them inside `site` matches
    // belongs to that website ("flight.ctrip.com" saved with its own shortcut is not a
    // "ctrip.com" tab).
    // - Not already on a match: the site's own host before its subdomains, then the
    //   front-most window's match, its selected tab first.
    // - Already on a match (the browser frontmost, its front window showing one): the next
    //   match, wrapping around. The order is by window id and tab, not front to back,
    //   because switching brings that window to the front and would otherwise send the
    //   next press straight back.
    static func choose(_ site: WebsiteScope, tabs: [BrowserTab], browserFrontmost: Bool,
                       others: [WebsiteScope] = []) -> BrowserTab? {
        let inside = others.filter(site.contains)
        let matching = tabs.filter { tab in
            guard let page = WebsiteAddress(tab.url), site.matches(page) else { return false }
            return !inside.contains { $0.matches(page) }
        }
        guard !matching.isEmpty else { return nil }
        let frontWindow = tabs.map { $0.windowIndex }.min()
        if browserFrontmost,
           let current = matching.first(where: { $0.active && $0.windowIndex == frontWindow }) {
            let stable = matching.sorted { ($0.window, $0.index) < ($1.window, $1.index) }
            guard let position = stable.firstIndex(of: current) else { return current }
            return stable[(position + 1) % stable.count]
        }
        let ownHost = matching.filter { WebsiteAddress($0.url)?.host == site.address.host }
        return (ownHost.isEmpty ? matching : ownHost).min {
            ($0.windowIndex, $0.active ? 0 : 1, $0.index) < ($1.windowIndex, $1.active ? 0 : 1, $1.index)
        }
    }
}
