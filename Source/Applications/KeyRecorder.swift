import Cocoa

// A shortcut field drawn like Rectangle's shortcut recorders (MASShortcut): an opaque
// round-rect field with the shortcut centered (⇪ M W, evenly spaced), and at its right
// edge ✕ to clear the shortcut or, while recording, ⎋ to cancel.
// It records exactly as shortcuts are used: click it, hold Caps, press the key(s),
// release Caps. The event tap delivers those keys through capsKeyPressed and
// capsReleased; keys typed without Caps are not recorded.
final class KeyRecorder: NSButton {
    static let emptyTitle = "Record Shortcut"
    static let recordingPrompt = "Hold \(capsSymbol) to start…"
    static let fieldHeight: CGFloat = 20
    private static let fontSize: CGFloat = 11
    // The ✕ / ⎋ area at the right edge.
    private static let hintWidth: CGFloat = 23
    private static let clearGlyph = "\u{2715}"   // ✕
    private static let escapeGlyph = "\u{238B}"  // ⎋

    // What the field shows: a line of text (the empty field, a prompt), or ⇪ and keys,
    // with "…" while more keys may follow. `title` always says the same, for
    // accessibility: "Record Shortcut", "⇪M W", "⇪M…".
    private enum Content {
        case text(String)
        case keys([UInt16], more: Bool)

        // A saved shortcut, or the empty field.
        static func saved(_ keys: [UInt16]) -> Content {
            shortcutName(keys) == nil ? .text(KeyRecorder.emptyTitle) : .keys(keys, more: false)
        }
        var title: String {
            switch self {
            case .text(let text): return text
            case .keys(let keys, let more): return capsSymbol + (shortcutName(keys) ?? "") + (more ? "…" : "")
            }
        }
    }
    private var content = Content.text(KeyRecorder.emptyTitle) {
        didSet {
            title = content.title
            needsDisplay = true
        }
    }
    var recording = false { didSet { if recording != oldValue { needsDisplay = true } } }
    weak var selectionTable: NSTableView?
    var onStart: (() -> Void)?
    // Called on Caps release with the keys pressed, in order (1 to `maxKeys` of them).
    var onKeys: (([UInt16]) -> Bool)?
    // Called by the ✕; without it the field shows no ✕.
    var onClear: (() -> Void)? { didSet { needsDisplay = true } }
    // KeyboardState.maxShortcutKeys for App List (⇪M W E), 1 for window actions.
    var maxKeys = 1
    // False while Clutch cannot see Caps (disabled, or no Accessibility access).
    var capsAvailable: (() -> Bool)?
    // The saved shortcut, shown while not recording.
    var shortcutKeys: [UInt16] = [] {
        didSet { content = .saved(shortcutKeys) }
    }
    var hasShortcut: Bool { shortcutName(shortcutKeys) != nil }
    private var recordedKeys: [UInt16] = []
    private var hintArea: NSTrackingArea?
    private var hintHovered = false { didSet { if hintHovered != oldValue { needsDisplay = true } } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }
    private func configure() {
        title = Self.emptyTitle
        font = Self.textFont
        // Keep the field's light Aqua appearance on the list surface.
        appearance = NSAppearance(named: .aqua)
    }
    override var acceptsFirstResponder: Bool { true }

    // MARK: Drawing

    private static let textFont = NSFont.systemFont(ofSize: KeyRecorder.fontSize)
    private static let cornerRadius: CGFloat = 5
    // The same visible gap after ⇪ and between keys ("⇪ M W"), measured between the
    // drawn glyphs, so letters of different widths still look evenly spaced.
    private static let keyGap: CGFloat = 4
    // Opaque, so a selected row's color never shows through the field.
    private static let fieldColor = NSColor.white
    private static let pressedColor = NSColor(calibratedWhite: 0.88, alpha: 1)
    private static let borderColor = NSColor(calibratedWhite: 0.66, alpha: 1)

    private var hintRect: NSRect {
        NSRect(x: bounds.maxX - Self.hintWidth, y: bounds.minY, width: Self.hintWidth, height: bounds.height)
    }
    private var textRect: NSRect {
        NSRect(x: bounds.minX, y: bounds.minY, width: max(0, bounds.width - Self.hintWidth), height: bounds.height)
    }
    private var showsClear: Bool { !recording && hasShortcut && onClear != nil }
    private var hintGlyph: String? { recording ? Self.escapeGlyph : (showsClear ? Self.clearGlyph : nil) }
    private func roundedPath(_ rect: NSRect) -> NSBezierPath {
        NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
    }
    override func draw(_ dirtyRect: NSRect) {
        let outer = roundedPath(bounds)
        let glyph = hintGlyph
        (glyph == nil && recording ? Self.pressedColor : Self.fieldColor).setFill()
        outer.fill()
        Self.borderColor.setStroke()
        outer.lineWidth = 1
        let textArea = glyph == nil ? bounds : textRect
        if let glyph = glyph {
            // The text part is its own box (pressed in while recording), with ✕ or ⎋ beside it.
            let inner = roundedPath(textRect)
            (recording ? Self.pressedColor : Self.fieldColor).setFill()
            inner.fill()
            inner.lineWidth = 1
            inner.stroke()
            drawText(glyph, in: hintRect, color: hintHovered ? .labelColor : .secondaryLabelColor)
        }
        outer.stroke()
        if recording, hintHovered {
            // While recording, pointing at ⎋ says what clicking it does.
            drawText(hasShortcut ? "Use Old Shortcut" : "Cancel", in: textArea, color: .secondaryLabelColor)
            return
        }
        switch content {
        case .text(let text):
            drawText(text, in: textArea, color: .secondaryLabelColor)
        case .keys(let keys, let more):
            // ["⇪", "M", "W", "…"]
            var tokens: [String] = [capsSymbol]
            tokens += keys.map { keyName($0) ?? "?" }
            if more { tokens.append("…") }
            drawKeys(tokens, in: textArea, color: .labelColor)
        }
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { roundedPath(bounds).fill() }

    // One line of text, vertically centered in `rect`, then raised by `textRaise`.
    private static let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: textFont))
    private static let textRaise: CGFloat = 1
    private func lineRect(in rect: NSRect) -> NSRect {
        let height = Self.lineHeight
        let centered = (rect.midY - height / 2).rounded()
        return NSRect(x: rect.minX, y: centered + (isFlipped ? -Self.textRaise : Self.textRaise),
                      width: rect.width, height: height)
    }
    // Plain text (a prompt, ✕, ⎋), centered and cut off at the end when too long.
    private func drawText(_ text: String, in rect: NSRect, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let line = lineRect(in: rect.insetBy(dx: 4, dy: 0))
        NSAttributedString(string: text, attributes: [.font: Self.textFont, .foregroundColor: color, .paragraphStyle: paragraph])
            .draw(with: line, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
    // ⇪ and the keys, centered, with `keyGap` between the drawn glyphs.
    private func drawKeys(_ tokens: [String], in rect: NSRect, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.textFont, .foregroundColor: color]
        let pieces = tokens.map { NSAttributedString(string: $0, attributes: attributes) }
        let unbounded = NSSize(width: 10_000, height: 10_000)
        let inks = pieces.map { $0.boundingRect(with: unbounded, options: [.usesLineFragmentOrigin, .usesDeviceMetrics]) }
        let inkWidth = inks.reduce(CGFloat(0)) { $0 + $1.width }
        let total = inkWidth + Self.keyGap * CGFloat(max(0, pieces.count - 1))
        let line = lineRect(in: rect)
        var x = rect.midX - total / 2
        for (piece, ink) in zip(pieces, inks) {
            let advance = piece.size().width
            piece.draw(with: NSRect(x: x - ink.minX, y: line.minY, width: advance + 20, height: line.height),
                       options: [.usesLineFragmentOrigin])
            x += ink.width + Self.keyGap
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = hintArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: hintRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        hintArea = area
    }
    override func mouseEntered(with event: NSEvent) {
        if let area = hintArea, event.trackingArea === area { hintHovered = true } else { super.mouseEntered(with: event) }
    }
    override func mouseExited(with event: NSEvent) {
        if let area = hintArea, event.trackingArea === area { hintHovered = false } else { super.mouseExited(with: event) }
    }

    // MARK: Recording

    override func mouseDown(with event: NSEvent) {
        if !event.modifierFlags.intersection([.command, .shift]).isEmpty,
           let table = selectionTable {
            cancelRecording()
            guard window?.makeFirstResponder(table) == true else { return }
            table.mouseDown(with: event)
            return
        }
        // ⎋ cancels recording; ✕ clears the shortcut.
        if hintGlyph != nil && hintRect.contains(convert(event.locationInWindow, from: nil)) {
            if recording {
                cancelRecording()
            } else if let clear = onClear {
                clear()
            }
            return
        }
        guard window?.makeFirstResponder(self) == true else { return }
        if !recording { recording = true; onStart?() }
        recordedKeys = []
        content = .text(prompt)
    }
    var prompt: String {
        if capsAvailable?() == false { return "Turn on Clutch" }
        return Self.recordingPrompt
    }
    // Keys arrive here only when Caps is not held: the prompt already says what to do.
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == KeyCode.escape { cancelRecording(); return }
        NSSound.beep()
    }
    // Caps went down: show that the field is listening for the key(s).
    func capsPressed() {
        guard recording, capsAvailable?() != false else { return }
        recordedKeys = []
        showRecordedKeys()
    }
    // A key pressed while Caps is held, in press order.
    func capsKeyPressed(_ code: UInt16) {
        guard recording else { return }
        if code == KeyCode.escape { cancelRecording(); return }
        // Caps + Return saves the keys pressed so far, as releasing Caps does.
        // Return itself is never recorded.
        if KeyCode.isReturn(code) {
            guard !recordedKeys.isEmpty else { NSSound.beep(); return }
            saveRecordedKeys()
            return
        }
        // Caps + Delete takes back the last key pressed. A one-key field (a window
        // action) has nothing to take back, so there it records Delete.
        if code == KeyCode.delete && maxKeys > 1 {
            guard !recordedKeys.isEmpty else { NSSound.beep(); return }
            recordedKeys.removeLast()
            showRecordedKeys()
            return
        }
        // Space and Tab are reserved, like Return (and Delete above): they never show up in the field.
        guard code != KeyCode.space, code != KeyCode.tab, keyName(code) != nil else { NSSound.beep(); return }
        guard recordedKeys.count < maxKeys else { NSSound.beep(); return }
        recordedKeys.append(code)
        showRecordedKeys()
    }
    // "⇪…" before any key, "⇪T…" while another key may follow, "⇪T H E" once no more can.
    private func showRecordedKeys() {
        content = .keys(recordedKeys, more: recordedKeys.count < maxKeys)
    }
    // Releasing Caps saves what was pressed; Caps alone records nothing.
    func capsReleased() {
        guard recording, onKeys != nil else { return }
        guard !recordedKeys.isEmpty else { content = .text(prompt); return }
        saveRecordedKeys()
    }
    private func saveRecordedKeys() {
        guard let onKeys = onKeys else { return }
        let keys = recordedKeys
        recordedKeys = []
        if onKeys(keys) {
            finishRecording()
        } else if recording {
            content = .text(prompt)
        }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        // Leave Command-S (toggle) and Command-W (close) to the menu.
        if event.modifierFlags.contains(.command), [KeyCode.s, KeyCode.w].contains(event.keyCode) { return false }
        keyDown(with: event)
        return true
    }
    private func finishRecording() {
        recording = false
        recordedKeys = []
        window?.makeFirstResponder(nil)
    }
    func cancelRecording() {
        recordedKeys = []
        if recording { content = .saved(shortcutKeys); recording = false }
    }
    override func resignFirstResponder() -> Bool {
        cancelRecording()
        return super.resignFirstResponder()
    }
}
