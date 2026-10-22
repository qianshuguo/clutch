import Cocoa

// A small pill in the upper part of the screen, where Spotlight's field sits, showing
// the keys pressed while Caps is held: ⇪ followed by the first two keys ("⇪ M W"),
// centered, evenly spaced. It is the only Caps HUD on screen: when the keys select an
// app, the app card (with the keys on top) takes its place. Caps held alone shows
// nothing; the keyboard light shows Caps Lock. Caps + Space hides it as the Folders
// panel opens.
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
    static let height: CGFloat = 44
    static let cornerRadius: CGFloat = 14

    // A quarter of the way down the screen with the key window, centered, as wide as
    // the app card, like Spotlight's field.
    static func keyFrame() -> NSRect {
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.frame ?? .zero
        let width = LaunchHUD.size.width
        return NSRect(x: (screen.midX - width / 2).rounded(),
                      y: (screen.maxY - screen.height * 0.25 - height / 2).rounded(),
                      width: width, height: height)
    }
}

final class CapsHUDView: NSVisualEffectView {
    private let symbolView = NSImageView()
    private let textLabel = NSTextField(labelWithString: "")
    private static let inset: CGFloat = 10
    private static let symbolSize: CGFloat = 18
    private static let spacing: CGFloat = 6
    private static let textFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    // The ⇪ glyph's drawn extent, measured once.
    private lazy var symbolInk: ClosedRange<CGFloat> = symbolView.image?.inkHorizontalRange() ?? 0...Self.symbolSize

    init() {
        super.init(frame: NSRect(origin: .zero, size: CapsHUDGeometry.keyFrame().size))
        wantsLayer = true
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        autoresizingMask = [.width, .height]
        // Rounded corners for the behind-window blur.
        let radius = CapsHUDGeometry.cornerRadius
        let mask = NSImage(size: NSSize(width: radius * 2 + 1, height: radius * 2 + 1), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        maskImage = mask
        symbolView.image = NSImage(systemSymbolName: "capslock", accessibilityDescription: "Caps Lock")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        symbolView.imageScaling = .scaleProportionallyUpOrDown
        symbolView.contentTintColor = .labelColor
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.maximumNumberOfLines = 1
        [symbolView, textLabel].forEach { addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // ⇪ and the keys as one centered line, laid out by the drawn glyph so the gap after
    // ⇪ equals the gaps between keys.
    override func layout() {
        super.layout()
        let width = bounds.width, height = bounds.height, size = Self.symbolSize
        textLabel.sizeToFit()
        let glyph = symbolView.image.map { $0.glyphLayout(height: size, ink: symbolInk) }
            ?? (glyphWidth: size, imageFrame: NSRect(x: 0, y: 0, width: size, height: size))
        let symbolWidth = glyph.glyphWidth.rounded()
        let textWidth = min(textLabel.frame.width, max(0, width - Self.inset * 2 - symbolWidth - Self.spacing))
        let symbolX = ((width - symbolWidth - Self.spacing - textWidth) / 2).rounded()
        symbolView.frame = glyph.imageFrame.offsetBy(dx: symbolX, dy: ((height - size) / 2).rounded())
        let textHeight = textLabel.frame.height
        textLabel.frame = NSRect(x: symbolX + symbolWidth + Self.spacing, y: ((height - textHeight) / 2).rounded(),
                                 width: textWidth, height: textHeight)
    }
    func showKeys(_ keys: String) {
        // Each space between keys is widened to the gap after ⇪.
        let line = NSMutableAttributedString(string: keys, attributes: [.font: Self.textFont, .foregroundColor: NSColor.labelColor])
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: Self.textFont]).width
        for (offset, unit) in keys.utf16.enumerated() where unit == 32 {
            line.addAttribute(.kern, value: Self.spacing - spaceWidth, range: NSRange(location: offset, length: 1))
        }
        textLabel.attributedStringValue = line
        needsLayout = true
    }
}

final class CapsHUD {
    static let fade: TimeInterval = 0.12
    private var panel: NSPanel?
    private let content = CapsHUDView()

    func showKeys(_ keys: String) {
        content.showKeys(keys)
        show()
    }
    func hide(animated: Bool = true) {
        guard let panel = panel, panel.isVisible else { return }
        guard animated else {
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fade
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            if let panel = panel, panel.alphaValue == 0 { panel.orderOut(nil) }
        })
    }
    // Appears at once, without fading in.
    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(CapsHUDGeometry.keyFrame(), display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
        setOpaque(panel)
    }
    // A zero-length animation replaces a fade-out still running from this same
    // run-loop pass, which would otherwise finish and order the panel out.
    private func setOpaque(_ panel: NSPanel) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
    }
    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CapsHUDGeometry.keyFrame(),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = content
        return panel
    }
}
