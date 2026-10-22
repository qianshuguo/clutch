import Cocoa

// One HUD window for everything Caps shows, in the upper part of the screen where
// Spotlight's field sits. It changes size instead of being swapped for another window:
// - keys: the keys pressed while Caps is held, ⇪ followed by the first two keys
//   ("⇪ M W"), centered, with "No matching app" beneath them;
// - app: when the keys select an app, the same window grows downward into the app card
//   (the keys stay on top, the icon and name fade in below);
// - confirming: after release, when the app is not running, the card animates on to a
//   smaller icon with "⎋ Cancel" / "↩ Open", and the window becomes a modal panel.
// Caps held alone shows nothing; the keyboard light shows Caps Lock. Caps + Space hides
// it as the Folders panel opens.
extension NSImage {
    // Where the glyph is actually drawn, left to right, in image points: SF Symbol
    // images carry side padding, which made the gap after ⇪ wider than between keys.
    // Measured once from the rendered pixels.
    func inkHorizontalRange() -> ClosedRange<CGFloat> {
        let whole: ClosedRange<CGFloat> = 0...size.width
        guard let image = cgImage(forProposedRect: nil, context: nil, hints: nil),
              image.width > 0, image.height > 0 else { return whole }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return whole }
        var first: Int?, last: Int?
        for x in 0..<width {
            var inked = false
            for y in 0..<height where pixels[(y * width + x) * 4 + 3] > 16 { inked = true; break }
            if inked { if first == nil { first = x }; last = x }
        }
        guard let left = first, let right = last else { return whole }
        let scale = size.width / CGFloat(width)
        return CGFloat(left) * scale...CGFloat(right + 1) * scale
    }
    // Laid out at `height`: the glyph's width, and the frame for the whole image that
    // puts the glyph's left edge at x = 0.
    func glyphLayout(height: CGFloat, ink: ClosedRange<CGFloat>) -> (glyphWidth: CGFloat, imageFrame: NSRect) {
        let scale = height / max(size.height, 1)
        return ((ink.upperBound - ink.lowerBound) * scale,
                NSRect(x: -ink.lowerBound * scale, y: 0, width: size.width * scale, height: height))
    }
}

enum CapsHUDGeometry {
    static let width: CGFloat = 148
    // The keys row at the top.
    static let height: CGFloat = 44
    // "No matching app" below the keys row, with room under the text.
    static let statusHeight: CGFloat = 30
    static let statusBottomPadding: CGFloat = 10
    static let cardHeight: CGFloat = 148
    static let cornerRadius: CGFloat = 14

    // One stretchable blur mask, so the window can resize with rounded corners.
    static func roundedMask() -> NSImage {
        let radius = cornerRadius
        let mask = NSImage(size: NSSize(width: radius * 2 + 1, height: radius * 2 + 1), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        return mask
    }

    // A quarter of the way down the screen with the key window, centered, like
    // Spotlight's field. Every stage keeps this top edge and grows downward.
    static func keyFrame() -> NSRect {
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.frame ?? .zero
        return NSRect(x: (screen.midX - width / 2).rounded(),
                      y: (screen.maxY - screen.height * 0.25 - height / 2).rounded(),
                      width: width, height: height)
    }
    static func unmatchedFrame() -> NSRect { extended(to: height + statusHeight) }
    static func cardFrame() -> NSRect { extended(to: cardHeight) }
    private static func extended(to total: CGFloat) -> NSRect {
        let keys = keyFrame()
        return NSRect(x: keys.minX, y: keys.maxY - total, width: keys.width, height: total)
    }
}

// The HUD's contents, laid out once at the card's full size (bottom-up, as AppKit
// expects) in an inner view pinned to the top edge. The window grows or shrinks around
// it, so nothing inside moves with the window; when the window is the short keys HUD,
// the card's lower part is simply outside it.
final class CapsOverlayView: NSVisualEffectView {
    enum Stage { case keys, app, confirming }
    private let stageView = NSView(frame: NSRect(x: 0, y: 0, width: CapsHUDGeometry.width,
                                                 height: CapsHUDGeometry.cardHeight))

    private let symbolView = NSImageView()
    private let keysLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "No matching app")
    // The icon is a plain layer in a layer-hosting view: its center and size animate in
    // one Core Animation transaction, so it moves in a straight line. As an NSImageView
    // its frame animation curved while the icon grew and moved up.
    private let iconHost = NSView()
    private let iconLayer = CALayer()
    private var iconImage: NSImage?
    private let nameLabel = NSTextField(labelWithString: "")
    private let cancelKey = NSTextField(labelWithString: "⎋ Cancel")
    private let openKey = NSTextField(labelWithString: "↩ Open")

    static let transition: TimeInterval = 0.18
    private static let keysFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    private static let keysGap: CGFloat = 6
    private static let symbolSize: CGFloat = 18
    private static let statusLabelHeight: CGFloat = 14
    // "Visual Studio Code" at 13 pt is about as wide as a 124 pt label; 8 pt leaves
    // headroom for names that long.
    private static let labelInset: CGFloat = 8
    private static let cornerKeyInset: CGFloat = 9
    private static let cornerKeyBottom: CGFloat = 9
    private static let returnGlyphOffset: CGFloat = -2
    // The ⇪ glyph's drawn extent, measured once.
    private lazy var symbolInk: ClosedRange<CGFloat> = symbolView.image?.inkHorizontalRange() ?? 0...Self.symbolSize

    private(set) var stage: Stage = .keys

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: CapsHUDGeometry.width, height: CapsHUDGeometry.cardHeight))
        // Layer-backed so stage changes animate, also inside the modal session.
        wantsLayer = true
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        autoresizingMask = [.width, .height]
        maskImage = CapsHUDGeometry.roundedMask()
        // Keeps its distance to the top edge while the window's height changes.
        stageView.autoresizingMask = [.minYMargin]
        addSubview(stageView)

        symbolView.image = NSImage(systemSymbolName: "capslock", accessibilityDescription: "Caps Lock")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        symbolView.imageScaling = .scaleProportionallyUpOrDown
        symbolView.contentTintColor = .labelColor
        keysLabel.maximumNumberOfLines = 1
        keysLabel.lineBreakMode = .byClipping

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.maximumNumberOfLines = 1
        let width = CapsHUDGeometry.width, card = CapsHUDGeometry.cardHeight
        // The keys HUD's bottom edge, in the card's coordinates, plus the padding.
        let statusY = card - CapsHUDGeometry.height - CapsHUDGeometry.statusHeight + CapsHUDGeometry.statusBottomPadding
        statusLabel.frame = NSRect(x: Self.labelInset, y: statusY,
                                   width: width - Self.labelInset * 2, height: Self.statusLabelHeight)

        let hostLayer = CALayer()
        iconHost.layer = hostLayer          // set before wantsLayer: layer-hosting
        iconHost.wantsLayer = true
        iconHost.frame = stageView.bounds
        iconLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        iconLayer.contentsGravity = .resizeAspect
        // Smooth when drawn smaller than the rendered size (64 and 72 pt).
        iconLayer.minificationFilter = .trilinear
        hostLayer.addSublayer(iconLayer)
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
        // The ↩ glyph sits high next to the text; lower just that character.
        let rightAligned = NSMutableParagraphStyle()
        rightAligned.alignment = .right
        let returnGlyph = NSMutableAttributedString(string: "↩ Open", attributes: [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: rightAligned])
        returnGlyph.addAttribute(.baselineOffset, value: Self.returnGlyphOffset, range: NSRange(location: 0, length: 1))
        openKey.attributedStringValue = returnGlyph
        // Sized to their text and pinned to the card's bottom corners. The lowered ↩
        // makes the right label taller at the bottom, so it moves down by that much to
        // keep both labels' text on the same baseline.
        cancelKey.sizeToFit()
        openKey.sizeToFit()
        let cancelSize = cancelKey.frame.size, openSize = openKey.frame.size
        cancelKey.frame = NSRect(x: Self.cornerKeyInset, y: Self.cornerKeyBottom,
                                 width: cancelSize.width, height: cancelSize.height)
        openKey.frame = NSRect(x: width - Self.cornerKeyInset - openSize.width,
                               y: Self.cornerKeyBottom - max(0, openSize.height - cancelSize.height),
                               width: openSize.width, height: openSize.height)

        [iconHost, nameLabel, cancelKey, openKey, statusLabel, symbolView, keysLabel].forEach { stageView.addSubview($0) }
        setStage(.keys, animated: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var icon: NSImage? {
        get { iconImage }
        set {
            iconImage = newValue
            updateIconContents()
        }
    }
    private func updateIconContents() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Rendered once at the largest size the icon is shown, in pixels, and only ever
        // scaled down. App icons from NSWorkspace are 32 pt images whose own layer
        // contents were enlarged, and blurred, at 64 to 88 pt.
        if let image = iconImage, let rendered = Self.render(image, pixels: Self.largestIcon * scale) {
            iconLayer.contents = rendered
            iconLayer.contentsScale = scale
        } else {
            iconLayer.contents = nil
        }
        CATransaction.commit()
    }
    private static let largestIcon: CGFloat = 88
    // Drawing into a bitmap of this many pixels picks the image's best representation
    // for that size (app icons carry them up to 1024 px).
    private static func render(_ image: NSImage, pixels: CGFloat) -> CGImage? {
        let side = Int(pixels.rounded(.up))
        guard side > 0, let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                                      bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero,
                   operation: .sourceOver, fraction: 1)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateIconContents()
    }
    var name: String {
        get { nameLabel.stringValue }
        set { nameLabel.stringValue = newValue }
    }
    // "M W", shown after ⇪ on top. Empty hides the row (the card then shows a larger icon).
    private(set) var keys = ""
    func setKeys(_ keys: String) {
        guard keys != self.keys else { return }
        self.keys = keys
        // Each space between keys is widened to the gap after ⇪.
        let line = NSMutableAttributedString(string: keys, attributes: [.font: Self.keysFont, .foregroundColor: NSColor.labelColor])
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: Self.keysFont]).width
        for (offset, unit) in keys.utf16.enumerated() where unit == 32 {
            line.addAttribute(.kern, value: Self.keysGap - spaceWidth, range: NSRange(location: offset, length: 1))
        }
        keysLabel.attributedStringValue = line
        keysLabel.sizeToFit()
        // ⇪ and the keys as one centered line, laid out by the drawn glyph so the gap
        // after ⇪ equals the gaps between keys.
        let width = CapsHUDGeometry.width, size = Self.symbolSize
        let glyph = symbolView.image.map { $0.glyphLayout(height: size, ink: symbolInk) }
            ?? (glyphWidth: size, imageFrame: NSRect(x: 0, y: 0, width: size, height: size))
        let symbolWidth = glyph.glyphWidth.rounded()
        let textWidth = min(keysLabel.frame.width, max(0, width - Self.labelInset * 2 - symbolWidth - Self.keysGap))
        let x = ((width - symbolWidth - Self.keysGap - textWidth) / 2).rounded()
        // The middle of the top row, measured from the card's bottom.
        let midY = CapsHUDGeometry.cardHeight - CapsHUDGeometry.height / 2
        let textHeight = keysLabel.frame.height
        symbolView.frame = glyph.imageFrame.offsetBy(dx: x, dy: (midY - size / 2).rounded())
        keysLabel.frame = NSRect(x: x + symbolWidth + Self.keysGap, y: (midY - textHeight / 2).rounded(),
                                 width: textWidth, height: textHeight)
    }

    // Always through the animator, also when not animated, so a change replaces one
    // still running instead of being overwritten when it finishes.
    func setStage(_ stage: Stage, animated: Bool) {
        self.stage = stage
        let width = CapsHUDGeometry.width
        let confirming = stage == .confirming
        // With keys on top, the card's icon is smaller to leave the row room.
        let showsKeys = !confirming && !keys.isEmpty
        let iconSize: CGFloat = confirming ? 72 : showsKeys ? 64 : 88
        let iconY: CGFloat = confirming ? 56 : showsKeys ? 44 : 42
        let iconCenter = CGPoint(x: width / 2, y: iconY + iconSize / 2)
        let nameFrame = NSRect(x: Self.labelInset, y: confirming ? 30 : 14,
                               width: width - Self.labelInset * 2, height: 18)
        let keysAlpha: CGFloat = showsKeys ? 1 : 0
        let statusAlpha: CGFloat = stage == .keys ? 1 : 0
        let appAlpha: CGFloat = stage == .keys ? 0 : 1
        let cornerAlpha: CGFloat = confirming ? 1 : 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? Self.transition : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = animated
            self.nameLabel.animator().frame = nameFrame
            self.symbolView.animator().alphaValue = keysAlpha
            self.keysLabel.animator().alphaValue = keysAlpha
            self.statusLabel.animator().alphaValue = statusAlpha
            self.nameLabel.animator().alphaValue = appAlpha
            self.cancelKey.animator().alphaValue = cornerAlpha
            self.openKey.animator().alphaValue = cornerAlpha
        }
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(animated ? Self.transition : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        iconLayer.bounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
        iconLayer.position = iconCenter
        iconLayer.opacity = Float(appAlpha)
        CATransaction.commit()
    }
}

// Owns the one HUD window. The key handler reports what it wants (the matched app, and
// the keys pressed) synchronously from the tap; the window is updated once afterwards,
// so the app changing and the keys changing in the same key press become one transition.
// The window's alpha always stays 1: behind-window blur is not drawn reliably while a
// window is partly transparent, or when it is ordered in at alpha 0, which showed the
// material's flat dark tint until the next redraw. So it appears and disappears at
// once, like Spotlight, and only its contents animate.
final class CapsOverlay {
    // The app path last requested by the key handler. `app` is set synchronously in the
    // tap callback, so each key press compares against it without waiting for the UI.
    var target: String? { app?.path }

    private enum Mode { case hidden, keys, app, confirming }
    private var mode: Mode = .hidden
    private var app: AppShortcut?
    private var shownPath: String?
    private var pillKeys: String?
    private var cardKeys = ""
    private var hideImmediately = false
    private var renderScheduled = false
    // Bumped by each hide, so only the latest pending hide orders the window out.
    private var hideGeneration = 0
    private let content = CapsOverlayView()
    private let panel = LaunchConfirmationPanel(contentRect: CapsHUDGeometry.unmatchedFrame(),
                                                styleMask: [.borderless, .nonactivatingPanel],
                                                backing: .buffered, defer: true)

    init() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.alphaValue = 1
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = content
    }

    // The app releasing Caps would open, or nil.
    func setApp(_ binding: AppShortcut?) {
        app = binding
        setNeedsRender()
    }
    // The keys pressed, with no app matching: the small HUD with "No matching app".
    func showKeys(_ keys: String) {
        pillKeys = keys
        setNeedsRender()
    }
    // The keys pressed, shown on top of the app card.
    func showAppKeys(_ keys: String) {
        cardKeys = keys
        pillKeys = nil
        setNeedsRender()
    }
    // No keys to show. `immediately` hides it within this key event (the Folders panel takes over).
    func hideKeys(immediately: Bool = false) {
        pillKeys = nil
        if immediately { hideImmediately = true }
        setNeedsRender()
    }
    // Everything off at once (the key tap is going away).
    func reset() {
        guard mode != .confirming else { return }
        app = nil
        pillKeys = nil
        hideNow()
    }

    private func setNeedsRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        performOnMainRunLoop { [weak self] in
            guard let self = self else { return }
            self.renderScheduled = false
            self.render()
        }
    }

    private func render() {
        // The confirmation owns the window until it ends.
        guard mode != .confirming else { return }
        let desired: Mode = app != nil ? .app : pillKeys != nil ? .keys : .hidden
        let immediate = hideImmediately
        hideImmediately = false
        if desired == .hidden {
            guard mode != .hidden else { return }
            if immediate { hideNow() } else { hideAfterKeyEvent() }
            return
        }
        if let app = app, app.path != shownPath {
            shownPath = app.path
            content.icon = NSWorkspace.shared.icon(forFile: app.path)
            content.name = app.name
        }
        content.setKeys(desired == .app ? cardKeys : pillKeys ?? "")
        let stage: CapsOverlayView.Stage = desired == .app ? .app : .keys
        let frame = desired == .app ? CapsHUDGeometry.cardFrame() : CapsHUDGeometry.unmatchedFrame()
        if mode == .hidden || !panel.isVisible {
            // Appears at once, already at its size.
            content.setStage(stage, animated: false)
            setFrame(frame, animated: false)
            if !panel.isVisible {
                panel.orderFrontRegardless()
                redrawBackdrop()
            }
        } else if mode != desired {
            // Keys ⇄ app card: the same window grows or shrinks.
            content.setStage(stage, animated: true)
            setFrame(frame, animated: true)
        } else {
            content.setStage(stage, animated: true)
        }
        mode = desired
    }

    private func setFrame(_ frame: NSRect, animated: Bool) {
        let panel = self.panel
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animated ? CapsOverlayView.transition : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            panel.invalidateShadow()
            self?.redrawBackdrop()
        })
    }
    // Redraws the blur now and once more after the window server has the window on
    // screen: a window just ordered in could keep showing the material's dark tint
    // until something else redrew it (the second key press).
    private func redrawBackdrop() {
        content.needsDisplay = true
        panel.display()
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.panel.isVisible else { return }
            self.content.needsDisplay = true
            self.panel.display()
            self.panel.invalidateShadow()
        }
    }
    // Ordered out once the work queued for this key event has run: releasing Caps on an
    // app that is not running starts the confirmation from that same event, and it
    // takes over the card still on screen instead of the window blinking out and in.
    private func hideAfterKeyEvent() {
        mode = .hidden
        hideGeneration += 1
        let generation = hideGeneration
        DispatchQueue.main.async { [weak self] in
            // Shown again (or taken over by the confirmation) in the meantime: it stays.
            guard let self = self, self.mode == .hidden, self.hideGeneration == generation else { return }
            self.panel.orderOut(nil)
        }
    }
    private func hideNow() {
        mode = .hidden
        hideGeneration += 1
        panel.orderOut(nil)
    }

    // After Caps is released on an app that is not running: the card on screen (or a
    // fresh one in its place) animates on to its second stage, smaller icon with
    // "⎋ Cancel" / "↩ Open", in the same window. Returns whether to open the app.
    func confirm(appName: String, icon: NSImage) -> Bool {
        let previousFocus = PreviousFocus()
        let panel = self.panel
        // The card is still on screen from the Caps release: take it over where it is.
        let continuesCard = panel.isVisible && content.stage == .app
        hideGeneration += 1
        mode = .confirming
        content.icon = icon
        content.name = appName
        shownPath = nil
        if !continuesCard {
            content.setKeys("")
            content.setStage(.app, animated: false)
            setFrame(CapsHUDGeometry.cardFrame(), animated: false)
        }
        panel.resetOutsideClick()
        panel.ignoresMouseEvents = false
        NSApp.activateFromBackground()
        let wasVisible = panel.isVisible
        panel.makeKeyAndOrderFront(nil)
        if !wasVisible { redrawBackdrop() }
        content.setStage(.confirming, animated: true)

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

        panel.ignoresMouseEvents = true
        hideNow()
        // Whatever the key handler asked for during the confirmation is stale now.
        app = nil
        pillKeys = nil
        if !confirmed, !panel.dismissedByOutsideClick {
            previousFocus.restore()
        }
        return confirmed
    }
}
