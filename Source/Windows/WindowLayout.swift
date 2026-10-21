import Foundation
// Newer SDKs no longer expose CGRect geometry (minX, width, Equatable, …)
// through Foundation alone.
import CoreGraphics

// Caps + arrow / − / = / slash window layouts, modelled on Rectangle's defaults.
// Foundation and CoreGraphics only (no AppKit), so the pure keyboard tests can compile it. All rects use
// Accessibility coordinates: origin at the top-left of the primary display,
// y growing downward.
enum WindowCommand: String, CaseIterable {
    case left, right, up, down, smaller, larger, center

    var title: String {
        switch self {
        case .left: return "Left Half"
        case .right: return "Right Half"
        case .up: return "Fill Height (Again: Full)"
        case .down: return "Restore"
        case .smaller: return "Make Smaller"
        case .larger: return "Make Larger"
        case .center: return "Center"
        }
    }
    // Shown as the row's tooltip on the Windows page.
    var detail: String {
        switch self {
        case .left: return "Snap to the left half. Press again for 2/3, then 1/3."
        case .right: return "Snap to the right half. Press again for 2/3, then 1/3."
        case .up: return "Fill the screen height, keeping position and width. Press again to switch between full height and maximized."
        case .down: return "Return to the size and place before the first layout."
        case .smaller: return "Shrink by 30 points in each direction."
        case .larger: return "Grow by 30 points in each direction."
        case .center: return "Center on the screen, keeping the size."
        }
    }
    // One visual family: every icon is a window-shaped rectangle.
    var symbol: String {
        switch self {
        case .left: return "rectangle.lefthalf.filled"
        case .right: return "rectangle.righthalf.filled"
        case .up: return "rectangle.expand.vertical"            // macOS 13+
        case .down: return "arrow.uturn.backward.square"
        case .smaller: return "rectangle.arrowtriangle.2.inward"
        case .larger: return "rectangle.arrowtriangle.2.outward"
        case .center: return "rectangle.center.inset.filled"
        }
    }
    // Used when `symbol` is missing on the running macOS, so a row is never blank.
    var fallbackSymbol: String {
        switch self {
        case .up: return "arrow.up.and.down"
        case .down: return "arrow.uturn.backward"
        case .smaller: return "arrow.down.right.and.arrow.up.left"
        case .larger: return "arrow.up.left.and.arrow.down.right"
        default: return symbol
        }
    }
    // Rectangle-style defaults: arrows, −, = and /.
    var defaultKey: UInt16 {
        switch self {
        case .left: return 123
        case .right: return 124
        case .up: return 126
        case .down: return 125
        case .smaller: return 27
        case .larger: return 24
        case .center: return 44
        }
    }
}

// Caps + key for each window command, edited on the Windows page of Preferences.
// Saved as JSON {command: key code} under "WindowShortcuts"; unassigned is `unassignedKey`.
struct WindowShortcuts: Equatable {
    private var keys: [WindowCommand: UInt16]
    static let defaultsKey = "WindowShortcuts"
    static let defaults = WindowShortcuts(keys: Dictionary(uniqueKeysWithValues: WindowCommand.allCases.map { ($0, $0.defaultKey) }))

    private init(keys: [WindowCommand: UInt16]) { self.keys = keys }

    func key(for command: WindowCommand) -> UInt16 { keys[command] ?? unassignedKey }
    func command(for key: UInt16) -> WindowCommand? {
        guard key != unassignedKey else { return nil }
        return WindowCommand.allCases.first { keys[$0] == key }
    }
    // One key belongs to one command: assigning it clears any other command using it.
    mutating func assign(_ key: UInt16, to command: WindowCommand) {
        for other in WindowCommand.allCases where other != command && keys[other] == key { keys[other] = unassignedKey }
        keys[command] = key
    }
    mutating func clear(_ key: UInt16) {
        for command in WindowCommand.allCases where keys[command] == key { keys[command] = unassignedKey }
    }

    // Commands missing from a save keep their defaults; unreadable data loads the defaults.
    static func load(from defaults: UserDefaults = .standard) -> WindowShortcuts {
        var result = Self.defaults
        guard let data = defaults.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode([String: UInt16].self, from: data) else { return result }
        for command in WindowCommand.allCases {
            if let key = stored[command.rawValue] { result.keys[command] = key }
        }
        // A hand-edited save could repeat a key; keep the first command that claims it.
        var seen = Set<UInt16>()
        for command in WindowCommand.allCases {
            let key = result.key(for: command)
            if key != unassignedKey && !seen.insert(key).inserted { result.keys[command] = unassignedKey }
        }
        return result
    }
    func save(to defaults: UserDefaults = .standard) {
        let stored = Dictionary(uniqueKeysWithValues: WindowCommand.allCases.map { ($0.rawValue, key(for: $0)) })
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

enum WindowAction: Equatable {
    // `step` indexes WindowLayout.halfFractions: repeating ← or → cycles 1/2 → 2/3 → 1/3.
    case leftHalf(step: Int), rightHalf(step: Int)
    case maximizeHeight, maximize, restore, smaller, larger, center
}

// One Accessibility attribute write that moves a window toward its target frame.
enum FrameWrite: Equatable { case size, position }

// What Clutch last did to one window, and where the window was before.
struct WindowMemory: Equatable {
    var restoreFrame: CGRect
    var lastAction: WindowAction
    var lastFrame: CGRect
    // The frame before the last maximize, so ↑ again can go back to it.
    var unmaximizedFrame: CGRect? = nil
}

// The window actions pressed during one Caps hold, simulated on the window's frame
// so the preview shows exactly where the window will land. Releasing Caps applies
// `frame` once and keeps `memory`, as if each action had been performed in turn.
struct WindowPlan: Equatable {
    let start: CGRect
    let screen: CGRect
    private let startMemory: WindowMemory?
    private(set) var frame: CGRect
    private(set) var memory: WindowMemory?
    // False until an action applies; Restore without a restore point applies nothing.
    private(set) var applied = false
    private var lastCommand: WindowCommand?

    init(start: CGRect, screen: CGRect, memory: WindowMemory?) {
        self.start = start; self.screen = screen; startMemory = memory; frame = start; self.memory = memory
    }
    // Pressing the same key again continues (← ½ → ⅔ → ⅓, ↑ height ⇄ full, = = −).
    // Switching to another key starts over from the window as it is, so ← then ↑
    // previews exactly what ↑ alone would.
    mutating func apply(_ command: WindowCommand) {
        if let previous = lastCommand, Self.family(previous) != Self.family(command) {
            frame = start; memory = startMemory; applied = false
        }
        lastCommand = command
        guard let action = WindowLayout.action(for: command, current: frame, screen: screen, memory: memory),
              let target = WindowLayout.frame(for: action, window: frame, screen: screen, restore: memory?.restoreFrame,
                                              unmaximized: memory?.unmaximizedFrame) else { return }
        memory = WindowLayout.remember(action, before: frame, after: target, memory: memory)
        frame = target
        applied = true
    }
    // − and = step the same size, so they continue each other.
    private static func family(_ command: WindowCommand) -> WindowCommand { command == .larger ? .smaller : command }
}

enum WindowLayout {
    static let halfFractions: [CGFloat] = [1.0 / 2, 2.0 / 3, 1.0 / 3]
    static let sizeStep: CGFloat = 30
    // Make Smaller stops at a quarter of the screen in each direction.
    static let minimumFraction: CGFloat = 0.25
    static let tolerance: CGFloat = 2

    static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance &&
            abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    // The action a command performs. A repeated command continues from the last
    // action only while the window is still where Clutch put it.
    static func action(for command: WindowCommand, current: CGRect, screen: CGRect, memory: WindowMemory?) -> WindowAction? {
        let last = memory.flatMap { same($0.lastFrame, current) ? $0.lastAction : nil }
        let steps = halfFractions.count
        switch command {
        case .left:
            if case .leftHalf(let step)? = last { return .leftHalf(step: (step + 1) % steps) }
            return .leftHalf(step: 0)
        case .right:
            if case .rightHalf(let step)? = last { return .rightHalf(step: (step + 1) % steps) }
            return .rightHalf(step: 0)
        case .up:
            // ↑ toggles fill height ⇄ maximize. ↑ on a window that already spans top to
            // bottom maximizes; ↑ on a window Clutch maximized goes back to full height.
            // The history check covers apps that stop just short (terminal row grids).
            if last == .maximize { return .maximizeHeight }
            return fillsHeight(current, of: screen) || last == .maximizeHeight ? .maximize : .maximizeHeight
        case .down:
            return memory == nil ? nil : .restore
        case .smaller:
            return .smaller
        case .larger:
            return .larger
        case .center:
            return .center
        }
    }

    static func fillsHeight(_ window: CGRect, of screen: CGRect) -> Bool {
        abs(window.minY - screen.minY) <= tolerance && abs(window.maxY - screen.maxY) <= tolerance
    }

    // The target frame, or nil when the action has nothing to change.
    // `unmaximized`: the frame before the last maximize, used when ↑ leaves maximize.
    static func frame(for action: WindowAction, window: CGRect, screen: CGRect, restore: CGRect?,
                      unmaximized: CGRect? = nil) -> CGRect? {
        switch action {
        case .leftHalf(let step):
            let width = (screen.width * halfFractions[step % halfFractions.count]).rounded()
            return CGRect(x: screen.minX, y: screen.minY, width: width, height: screen.height)
        case .rightHalf(let step):
            let width = (screen.width * halfFractions[step % halfFractions.count]).rounded()
            return CGRect(x: screen.maxX - width, y: screen.minY, width: width, height: screen.height)
        case .maximizeHeight:
            // Leaving maximize, keep the width and place the window had before it.
            let base = same(window, screen) ? (unmaximized ?? restore ?? window) : window
            let width = min(base.width, screen.width)
            let x = min(max(base.minX, screen.minX), screen.maxX - width)
            return CGRect(x: x, y: screen.minY, width: width, height: screen.height)
        case .maximize:
            return screen
        case .restore:
            return restore
        case .smaller:
            return resized(window, in: screen, by: -sizeStep)
        case .larger:
            return resized(window, in: screen, by: sizeStep)
        case .center:
            return centered(window.size, in: screen)
        }
    }

    // A size no larger than the screen, centered in it.
    static func centered(_ size: CGSize, in screen: CGRect) -> CGRect {
        let width = min(size.width, screen.width).rounded()
        let height = min(size.height, screen.height).rounded()
        return CGRect(x: (screen.midX - width / 2).rounded(), y: (screen.midY - height / 2).rounded(),
                      width: width, height: height)
    }

    // Grows or shrinks both directions by `delta`. Edges touching the screen stay
    // attached; otherwise the window keeps its center. Growing never leaves the screen.
    static func resized(_ window: CGRect, in screen: CGRect, by delta: CGFloat) -> CGRect? {
        func axis(origin: CGFloat, length: CGFloat, lower: CGFloat, upper: CGFloat) -> (origin: CGFloat, length: CGFloat) {
            let span = upper - lower
            let newLength: CGFloat
            if delta < 0 {
                let minimum = (span * minimumFraction).rounded()
                newLength = length <= minimum ? length : max(length + delta, minimum)
            } else {
                newLength = length >= span ? length : min(length + delta, span)
            }
            let change = newLength - length
            let atLower = abs(origin - lower) <= tolerance
            let atUpper = abs(origin + length - upper) <= tolerance
            var newOrigin: CGFloat
            if atLower && !atUpper { newOrigin = origin }
            else if atUpper && !atLower { newOrigin = origin + length - newLength }
            else { newOrigin = origin - change / 2 }
            if delta > 0 && newLength <= span {
                newOrigin = min(max(newOrigin, lower), upper - newLength)
            }
            return (newOrigin.rounded(), newLength.rounded())
        }
        let x = axis(origin: window.minX, length: window.width, lower: screen.minX, upper: screen.maxX)
        let y = axis(origin: window.minY, length: window.height, lower: screen.minY, upper: screen.maxY)
        let result = CGRect(x: x.origin, y: y.origin, width: x.length, height: y.length)
        return same(result, window) ? nil : result
    }

    // The memory to keep after `action` moved the window from `before` to `after`.
    // A window moved by hand since Clutch last touched it gets a new restore point.
    static func remember(_ action: WindowAction, before: CGRect, after: CGRect, memory: WindowMemory?) -> WindowMemory? {
        if action == .restore { return nil }
        let restoreFrame: CGRect
        if let memory = memory, same(memory.lastFrame, before) { restoreFrame = memory.restoreFrame }
        else { restoreFrame = before }
        return WindowMemory(restoreFrame: restoreFrame, lastAction: action, lastFrame: after,
                            unmaximizedFrame: action == .maximize ? before : nil)
    }

    // Each Accessibility write makes the app lay out and redraw, and every
    // intermediate frame shows on screen. Write only what changes, and pick the
    // order whose in-between frame still fits on a display, so no app has to
    // clamp it. Only when neither order fits does it fall back to Rectangle's
    // size, position, size.
    static func writes(from current: CGRect, to target: CGRect, screens: [CGRect]) -> [FrameWrite] {
        let resize = abs(current.width - target.width) > tolerance || abs(current.height - target.height) > tolerance
        let move = abs(current.minX - target.minX) > tolerance || abs(current.minY - target.minY) > tolerance
        switch (resize, move) {
        case (false, false): return []
        case (true, false): return [.size]
        case (false, true): return [.position]
        case (true, true):
            if fits(CGRect(origin: current.origin, size: target.size), in: screens) { return [.size, .position] }
            if fits(CGRect(origin: target.origin, size: current.size), in: screens) { return [.position, .size] }
            return [.size, .position, .size]
        }
    }

    // The writes still needed when an app did not land on the target (for example it
    // clamped the size, or moved the window while resizing): size first, then position.
    static func corrections(from result: CGRect, to target: CGRect) -> [FrameWrite] {
        var writes: [FrameWrite] = []
        if abs(result.width - target.width) > tolerance || abs(result.height - target.height) > tolerance { writes.append(.size) }
        if abs(result.minX - target.minX) > tolerance || abs(result.minY - target.minY) > tolerance { writes.append(.position) }
        return writes
    }

    static func fits(_ rect: CGRect, in screens: [CGRect]) -> Bool {
        screens.contains { screen in
            rect.minX >= screen.minX - tolerance && rect.minY >= screen.minY - tolerance &&
                rect.maxX <= screen.maxX + tolerance && rect.maxY <= screen.maxY + tolerance
        }
    }

    // The display holding most of the window; the first display when it is off-screen.
    static func screenIndex(for window: CGRect, screens: [CGRect]) -> Int {
        func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
        let overlaps = screens.map { area($0.intersection(window)) }
        if let best = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }), overlaps[best] > 0 { return best }
        let center = CGPoint(x: window.midX, y: window.midY)
        return screens.firstIndex { $0.contains(center) } ?? 0
    }
}
