import Cocoa
import IOKit.hidsystem

enum CapsReplay {
    static let marker: Int64 = 0x4879706572436170
    // A replayed short press: macOS switches input sources (or, if Caps Lock happens to
    // be on, turns it off). Long enough to look like a real tap (a zero-length press
    // made Electron apps switch the input source and switch it back), far below a
    // long press. Clutch never turns Caps Lock on: disable Clutch to use Caps Lock.
    static let tapDuration: TimeInterval = 0.1

    // Caps uses an auxiliary system-key event, rather than an ordinary letter
    // key event. Leave input-source selection and Caps state to macOS.
    static func events() throws -> [CGEvent] {
        try [NX_KEYDOWN, NX_KEYUP].map { transition in
            let payload = (Int(NX_KEYTYPE_CAPS_LOCK) << 16) | (Int(transition) << 8)
            guard let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                // 0xa00 / 0xb00, matching data1. The bare transition (0x0a / 0x0b)
                // would set device left-Shift/Command/Control modifier bits.
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(transition) << 8),
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0, context: nil,
                subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
                data1: payload, data2: -1)?.cgEvent else {
                throw ToolError(message: "Could not create a Caps Lock system event.")
            }
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            return event
        }
    }
    static func post(_ event: CGEvent) {
        // Stamp at posting time, so the release carries the real press duration.
        event.timestamp = CGEventTimestamp(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
        event.post(tap: .cghidEventTap)
    }
}

extension AppDelegate {
    // Caps pressed and released alone: a Caps tap for macOS.
    func replayCapsTap() throws {
        guard tap != nil, wantsEnabled else { return }
        // Construct both transitions before posting so failure cannot leave a
        // synthetic key-down without its matching release.
        let events = try CapsReplay.events()
        guard let down = events.first, let up = events.last else { return }
        CapsReplay.post(down)
        // The release is always posted, even if Clutch is disabled meanwhile.
        // Common run-loop modes keep it on time during menus and modal panels.
        let release = Timer(timeInterval: CapsReplay.tapDuration, repeats: false) { _ in CapsReplay.post(up) }
        RunLoop.main.add(release, forMode: .common)
    }
}
