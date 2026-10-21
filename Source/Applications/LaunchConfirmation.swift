import Cocoa

// Shared look of the launch hint (shown while Caps is held) and the launch
// confirmation (shown after release when the app is not running). Both use this
// view at the same fixed size, so the confirmation takes over without a visible change.
enum LaunchHUD {
    static let size = NSSize(width: 148, height: 148)
    static let cornerRadius: CGFloat = 20

    // The exact center of the screen with the key window (menu bar and Dock included).
    static func frame() -> NSRect {
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.frame ?? .zero
        return NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}

// Two stages at one fixed size.
// Hint (Caps held): a large icon over the app's name.
// Confirmation (Caps released, app not running): a smaller icon over the same name,
// with "⎋ Cancel" in the bottom-left corner and "↩ Open" in the bottom-right.
final class LaunchHUDView: NSVisualEffectView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let cancelKey = NSTextField(labelWithString: "⎋ Cancel")
    private let openKey = NSTextField(labelWithString: "↩ Open")
    static let transition: TimeInterval = 0.18
    private static let keyInset: CGFloat = 9
    private static let keyBottom: CGFloat = 9
    private static let returnGlyphOffset: CGFloat = -2
    // "Visual Studio Code" at 13 pt is about as wide as a 124 pt label, so it fit in one
    // window and was cut off in the other. 8 pt leaves headroom for names that long.
    private static let labelInset: CGFloat = 8

    init() {
        super.init(frame: NSRect(origin: .zero, size: LaunchHUD.size))
        // Layer-backed so the stage change animates even inside the modal session.
        wantsLayer = true
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        let size = LaunchHUD.size, radius = LaunchHUD.cornerRadius
        maskImage = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        // Squeeze letter spacing slightly before cutting a name off.
        nameLabel.allowsDefaultTighteningForTruncation = true
        for key in [cancelKey, openKey] {
            key.font = .systemFont(ofSize: 10)
            key.textColor = .secondaryLabelColor
        }
        cancelKey.alignment = .left
        openKey.alignment = .right
        // The ↩ glyph sits high next to the text; lower just that character.
        let rightAligned = NSMutableParagraphStyle()
        rightAligned.alignment = .right
        let returnGlyph = NSMutableAttributedString(string: "↩ Open", attributes: [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: rightAligned])
        returnGlyph.addAttribute(.baselineOffset, value: Self.returnGlyphOffset, range: NSRange(location: 0, length: 1))
        openKey.attributedStringValue = returnGlyph
        // Sized to their text and pinned to the corners. The lowered ↩ makes the right
        // label taller at the bottom, so it moves down by that much to keep both
        // labels' text on the same baseline.
        cancelKey.sizeToFit()
        openKey.sizeToFit()
        let cancelSize = cancelKey.frame.size, openSize = openKey.frame.size
        cancelKey.frame = NSRect(x: Self.keyInset, y: Self.keyBottom,
                                 width: cancelSize.width, height: cancelSize.height)
        openKey.frame = NSRect(x: size.width - Self.keyInset - openSize.width,
                               y: Self.keyBottom - max(0, openSize.height - cancelSize.height),
                               width: openSize.width, height: openSize.height)
        [iconView, nameLabel, cancelKey, openKey].forEach { addSubview($0) }
        setConfirming(false, animated: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var icon: NSImage? {
        get { iconView.image }
        set { iconView.image = newValue }
    }
    var name: String {
        get { nameLabel.stringValue }
        set { nameLabel.stringValue = newValue }
    }

    func setConfirming(_ confirming: Bool, animated: Bool) {
        let width = LaunchHUD.size.width
        let iconSize: CGFloat = confirming ? 72 : 88
        let iconFrame = NSRect(x: (width - iconSize) / 2, y: confirming ? 56 : 42, width: iconSize, height: iconSize)
        let labelFrame = NSRect(x: Self.labelInset, y: confirming ? 30 : 14,
                                width: width - Self.labelInset * 2, height: 18)
        guard animated else {
            iconView.frame = iconFrame
            nameLabel.frame = labelFrame
            cancelKey.alphaValue = confirming ? 1 : 0
            openKey.alphaValue = confirming ? 1 : 0
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.transition
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            self.iconView.animator().frame = iconFrame
            self.nameLabel.animator().frame = labelFrame
            self.cancelKey.animator().alphaValue = confirming ? 1 : 0
            self.openKey.animator().alphaValue = confirming ? 1 : 0
        }
    }
}

final class LaunchConfirmationPanel: NSPanel {
    private(set) var dismissedByOutsideClick = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

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
        guard KeyCode.isReturn(event.keyCode) else { return super.performKeyEquivalent(with: event) }
        NSApp.stopModal(withCode: .OK)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if !performKeyEquivalent(with: event) { super.keyDown(with: event) }
    }
}

// Confirmation for an app that is not running. It opens as an exact copy of the
// launch hint shown while Caps was held (same frame, icon and name), then the same
// window animates to its second stage: smaller icon, same name, ⎋ Cancel / ↩ Open.
final class LaunchConfirmation: NSObject {
    private let panel = LaunchConfirmationPanel(contentRect: NSRect(origin: .zero, size: LaunchHUD.size),
                                styleMask: [.borderless], backing: .buffered, defer: false)

    // `hint` is the visible launch hint, if any: the confirmation takes its exact
    // place and hides it once the confirmation is on screen.
    func run(appName: String, icon: NSImage, replacing hint: LaunchHintOverlay? = nil) -> Bool {
        let previousFocus = PreviousFocus()
        let frame = hint?.visibleFrame ?? LaunchHUD.frame()
        let content = LaunchHUDView()
        content.icon = icon
        content.name = appName
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.setFrame(frame, display: false)
        panel.contentView = content
        panel.invalidateShadow()

        NSApp.activateFromBackground()
        panel.makeKeyAndOrderFront(nil)
        hint?.hideNow()
        content.setConfirming(true, animated: true)
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
            previousFocus.restore()
        }
        return confirmed
    }

}
