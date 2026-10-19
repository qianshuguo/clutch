import Cocoa
import ApplicationServices

// Moves and resizes the focused window of the frontmost application through
// Accessibility. AppKit screen geometry is captured on the main thread; the
// Accessibility calls, which can block on a busy app, run on a serial queue
// that also owns the per-window memory used by repeats and Restore.
final class WindowManager {
    private let queue = DispatchQueue(label: "local.maxvoid.HyperCaps.window-layout", qos: .userInteractive)
    private var memories: [(window: AXUIElement, memory: WindowMemory)] = []
    private static let memoryLimit = 64
    private static let enhancedUserInterface = "AXEnhancedUserInterface" as CFString

    private struct Screen { let frame: CGRect; let visible: CGRect }

    func perform(_ command: WindowCommand, in app: NSRunningApplication) {
        let screens = Self.screens()
        guard !screens.isEmpty else { return }
        let processID = app.processIdentifier
        queue.async { [self] in perform(command, processID: processID, screens: screens) }
    }

    // NSScreen uses bottom-left coordinates; Accessibility uses top-left of the primary display.
    private static func screens() -> [Screen] {
        guard let primary = NSScreen.screens.first else { return [] }
        let top = primary.frame.maxY
        func flip(_ rect: NSRect) -> CGRect {
            CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
        }
        return NSScreen.screens.map { Screen(frame: flip($0.frame), visible: flip($0.visibleFrame)) }
    }

    private func perform(_ command: WindowCommand, processID: pid_t, screens: [Screen]) {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.25)
        guard let window = Self.focusedWindow(of: application),
              (Self.value(window, "AXFullScreen") as? Bool) != true,
              let current = Self.frame(of: window) else { return }
        let index = memories.firstIndex { CFEqual($0.window, window) }
        let memory = index.map { memories[$0].memory }
        let screen = screens[WindowLayout.screenIndex(for: current, screens: screens.map { $0.frame })]
        guard let action = WindowLayout.action(for: command, current: current, screen: screen.visible,
                                               memory: memory) else { return }
        guard let target = WindowLayout.frame(for: action, window: current, screen: screen.visible,
                                              restore: memory?.restoreFrame) else { return }
        // A target equal to the current frame still records the action, so a repeat
        // continues the sequence even when the first press changed nothing.
        let result = WindowLayout.same(target, current) ? current
            : Self.setFrame(target, from: current, of: window, in: application, screens: screens.map { $0.visible })
        if let index = index { memories.remove(at: index) }
        if let updated = WindowLayout.remember(action, before: current, after: result, memory: memory) {
            memories.append((window, updated))
            if memories.count > Self.memoryLimit { memories.removeFirst(memories.count - Self.memoryLimit) }
        }
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    private static func focusedWindow(of application: AXUIElement) -> AXUIElement? {
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let window = value(application, attribute), CFGetTypeID(window) == AXUIElementGetTypeID() {
                return (window as! AXUIElement)
            }
        }
        return nil
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let positionValue = value(window, kAXPositionAttribute), CFGetTypeID(positionValue) == AXValueGetTypeID(),
              let sizeValue = value(window, kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
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
        let enhanced = (value(application, enhancedUserInterface as String) as? Bool) == true
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

extension AppDelegate {
    func performWindowCommand(_ command: WindowCommand) {
        guard let app = NSWorkspace.shared.frontmostApplication, !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        windowManager.perform(command, in: app)
    }
}
