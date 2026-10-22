import Cocoa
import ApplicationServices

// Accessibility reads shared by window cycling (App List) and window layout. Each
// call can wait up to the messaging timeout for a busy app, so callers run them off
// the main thread, which also services the keyboard event tap.
enum AXQuery {
    static func application(_ processID: pid_t) -> AXUIElement {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.25)
        return application
    }
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }
    // An attribute that holds a UI element (such as a window); nil for anything else.
    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let found = value(element, attribute), CFGetTypeID(found) == AXUIElementGetTypeID() else { return nil }
        return (found as! AXUIElement)
    }
}

// Moves and resizes the focused window of the frontmost application through
// Accessibility. AppKit screen geometry is captured on the main thread; the
// Accessibility calls, which can block on a busy app, run on a serial queue
// that also owns the per-window memory used by repeats and Restore.
final class WindowManager {
    private let queue = DispatchQueue(label: "local.maxvoid.Clutch.window-layout", qos: .userInteractive)
    private var memories: [(window: AXUIElement, memory: WindowMemory)] = []
    private static let memoryLimit = 64
    private static let enhancedUserInterface = "AXEnhancedUserInterface" as CFString

    private struct Screen { let frame: CGRect; let visible: CGRect }

    // Everything needed to apply a plan to one window when Caps is released.
    struct Target {
        let window: AXUIElement
        let application: AXUIElement
        let screens: [CGRect]
        let plan: WindowPlan
    }

    // Reads the focused window once, off the main thread. `completion` runs on the
    // main thread with nil when there is no window to arrange.
    func beginPlan(in app: NSRunningApplication, completion: @escaping (Target?) -> Void) {
        let screens = Self.screens()
        guard !screens.isEmpty else { completion(nil); return }
        let processID = app.processIdentifier
        queue.async { [self] in
            let target = makeTarget(processID: processID, screens: screens)
            DispatchQueue.main.async { completion(target) }
        }
    }

    // Moves the window to the plan's frame in one go and keeps the plan's memory,
    // so repeats and Restore continue from where the window actually landed.
    func commit(_ plan: WindowPlan, to target: Target) {
        guard plan.applied else { return }
        queue.async { [self] in
            let current = Self.frame(of: target.window) ?? plan.start
            let result = WindowLayout.same(plan.frame, current) ? current
                : Self.setFrame(plan.frame, from: current, of: target.window, in: target.application, screens: target.screens)
            if let index = memories.firstIndex(where: { CFEqual($0.window, target.window) }) { memories.remove(at: index) }
            if var memory = plan.memory {
                memory.lastFrame = result
                memories.append((target.window, memory))
                if memories.count > Self.memoryLimit { memories.removeFirst(memories.count - Self.memoryLimit) }
            }
        }
    }

    private func makeTarget(processID: pid_t, screens: [Screen]) -> Target? {
        let application = AXQuery.application(processID)
        guard let window = Self.focusedWindow(of: application),
              (AXQuery.value(window, "AXFullScreen") as? Bool) != true,
              let current = Self.frame(of: window) else { return nil }
        let memory = memories.first { CFEqual($0.window, window) }?.memory
        let screen = screens[WindowLayout.screenIndex(for: current, screens: screens.map { $0.frame })]
        return Target(window: window, application: application, screens: screens.map { $0.visible },
                      plan: WindowPlan(start: current, screen: screen.visible, memory: memory))
    }

    // NSScreen uses bottom-left coordinates; Accessibility uses top-left of the primary
    // display. The same flip converts either way.
    static func flip(_ rect: CGRect, primaryTop top: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }
    private static func screens() -> [Screen] {
        guard let primary = NSScreen.screens.first else { return [] }
        let top = primary.frame.maxY
        return NSScreen.screens.map { Screen(frame: flip($0.frame, primaryTop: top), visible: flip($0.visibleFrame, primaryTop: top)) }
    }

    private static func focusedWindow(of application: AXUIElement) -> AXUIElement? {
        AXQuery.element(application, kAXFocusedWindowAttribute) ?? AXQuery.element(application, kAXMainWindowAttribute)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let positionValue = AXQuery.value(window, kAXPositionAttribute), CFGetTypeID(positionValue) == AXValueGetTypeID(),
              let sizeValue = AXQuery.value(window, kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    // Every write is a visible redraw in the target app, so only the attributes that
    // change are written, in an order that never needs an off-screen in-between frame
    // (see WindowLayout.writes). A follow-up write is made only if the app missed.
    private static func setFrame(_ frame: CGRect, from current: CGRect, of window: AXUIElement,
                                 in application: AXUIElement, screens: [CGRect]) -> CGRect {
        let writes = WindowLayout.writes(from: current, to: frame, screens: screens)
        guard !writes.isEmpty else { return current }
        // Apps with enhanced Accessibility UI (Chromium, Electron) animate and drop
        // frame changes; turn it off while resizing.
        let enhanced = (AXQuery.value(application, enhancedUserInterface as String) as? Bool) == true
        if enhanced { AXUIElementSetAttributeValue(application, enhancedUserInterface, kCFBooleanFalse) }
        defer { if enhanced { AXUIElementSetAttributeValue(application, enhancedUserInterface, kCFBooleanTrue) } }
        for write in writes { apply(write, frame, to: window) }
        guard let result = self.frame(of: window) else { return frame }
        // The full fallback already re-applied the size; otherwise fix what the app missed once.
        let corrections = writes.count < 3 ? WindowLayout.corrections(from: result, to: frame) : []
        guard !corrections.isEmpty else { return result }
        for write in corrections { apply(write, frame, to: window) }
        return self.frame(of: window) ?? frame
    }

    private static func apply(_ write: FrameWrite, _ frame: CGRect, to window: AXUIElement) {
        switch write {
        case .size:
            var size = frame.size
            if let axValue = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axValue)
            }
        case .position:
            var origin = frame.origin
            if let axValue = AXValueCreate(.cgPoint, &origin) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axValue)
            }
        }
    }
}

// The preview of a window action (Rectangle's "footprint"): a translucent rounded
// rectangle with a border, in the accent color, where the window will land. It never
// takes focus or mouse events, and fades in and out; changing steps moves it at once.
final class WindowPreviewOverlay {
    private var panel: NSPanel?
    static let alpha: CGFloat = 0.3
    static let borderWidth: CGFloat = 2
    static let cornerRadius: CGFloat = 10
    static let fade: TimeInterval = 0.15

    // `frame` uses Accessibility coordinates (top-left of the primary display).
    func show(_ frame: CGRect) {
        guard let primary = NSScreen.screens.first else { return }
        let rect = WindowManager.flip(frame, primaryTop: primary.frame.maxY)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(rect, display: true)
        if !panel.isVisible { panel.alphaValue = 0; panel.orderFrontRegardless() }
        // Already shown or fading in; a preview fading out fades back in.
        guard panel.alphaValue < 1 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fade
            panel.animator().alphaValue = 1
        }
    }
    func hide() {
        guard let panel = panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fade
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            // A preview shown again during the fade stays visible.
            if let panel = panel, panel.alphaValue == 0 { panel.orderOut(nil) }
        })
    }
    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let view = PreviewView()
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        return panel
    }
    private final class PreviewView: NSView {
        override var wantsUpdateLayer: Bool { true }
        override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
        required init?(coder: NSCoder) { super.init(coder: coder); wantsLayer = true }
        // Resolved here so the accent color follows light/dark mode and user changes.
        override func updateLayer() {
            guard let layer = layer else { return }
            let color = NSColor.controlAccentColor
            layer.cornerRadius = WindowPreviewOverlay.cornerRadius
            layer.borderWidth = WindowPreviewOverlay.borderWidth
            layer.borderColor = color.cgColor
            layer.backgroundColor = color.withAlphaComponent(WindowPreviewOverlay.alpha).cgColor
        }
    }
}

// One Caps hold of window actions: the target is read once, then each key press
// updates the plan and the preview; releasing Caps applies it.
final class WindowPreviewSession {
    var target: WindowManager.Target?
    var plan: WindowPlan?
    // Pressed before the window was read.
    var pending: [WindowCommand] = []
    var commitRequested = false
}

extension AppDelegate {
    func previewWindowCommand(_ command: WindowCommand) {
        if let session = windowPreview {
            guard var plan = session.plan else { session.pending.append(command); return }
            plan.apply(command)
            session.plan = plan
            showWindowPlan(plan)
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication, !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let session = WindowPreviewSession()
        session.pending = [command]
        windowPreview = session
        windowManager.beginPlan(in: app) { [weak self, weak session] target in
            guard let self = self, let session = session, self.windowPreview === session else { return }
            guard let target = target else { self.cancelWindowPreview(); return }
            var plan = target.plan
            for pending in session.pending { plan.apply(pending) }
            session.pending = []
            session.target = target
            session.plan = plan
            if session.commitRequested { self.commitWindowPreview() } else { self.showWindowPlan(plan) }
        }
    }
    private func showWindowPlan(_ plan: WindowPlan) {
        // Restore without a restore point changes nothing, so nothing is shown.
        if plan.applied { windowPreviewOverlay.show(plan.frame) } else { windowPreviewOverlay.hide() }
    }
    // Caps released: apply the previewed frame. If the window is still being read,
    // it is applied as soon as the read finishes.
    func commitWindowPreview() {
        guard let session = windowPreview else { return }
        guard let plan = session.plan, let target = session.target else { session.commitRequested = true; return }
        windowPreview = nil
        windowPreviewOverlay.hide()
        windowManager.commit(plan, to: target)
    }
    func cancelWindowPreview() {
        windowPreview = nil
        windowPreviewOverlay.hide()
    }
}
