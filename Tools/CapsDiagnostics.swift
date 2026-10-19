import Cocoa
import Carbon
import IOKit.hidsystem

_ = NSApplication.shared

// Observe only Caps/F18 and modifier transitions. Never read typed characters,
// window titles, file names, or clipboard contents; never post keyboard events.
func summary(_ event: CGEvent) -> String? {
    switch event.type {
    case .keyDown, .keyUp, .flagsChanged:
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if code == 57 || code == 79 {
            return "\(code == 57 ? "Caps" : "F18") type=\(event.type.rawValue)"
        }
        return event.type == .flagsChanged ? "modifier-change" : nil
    default:
        guard event.type.rawValue == 14, let native = NSEvent(cgEvent: event),
              native.subtype.rawValue == NX_SUBTYPE_AUX_CONTROL_BUTTONS,
              (native.data1 >> 16) == NX_KEYTYPE_CAPS_LOCK else { return nil }
        return "Caps-system transition=\((native.data1 >> 8) & 0xff) repeat=\(native.data1 & 1)"
    }
}

if CommandLine.arguments.contains("--self-test") {
    let ordinary = CGEvent(source: nil)!
    ordinary.type = .keyDown
    ordinary.setIntegerValueField(.keyboardEventKeycode, value: 0)
    precondition(summary(ordinary) == nil, "Do not log ordinary typing")
    for code: CGKeyCode in [57, 79] {
        let key = CGEvent(source: nil)!
        key.type = .keyDown
        key.setIntegerValueField(.keyboardEventKeycode, value: Int64(code))
        precondition(summary(key) != nil)
    }
    let caps = NSEvent.otherEvent(with: .systemDefined, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
        subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
        data1: (Int(NX_KEYTYPE_CAPS_LOCK) << 16) | (Int(NX_KEYDOWN) << 8), data2: -1)!.cgEvent!
    precondition(summary(caps) != nil)
    print("PASS: Caps/F18 included; ordinary typing excluded; no events posted")
    exit(0)
}

func inputSourceID() -> String {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "unknown" }
    return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
}

let started = ProcessInfo.processInfo.systemUptime
func log(_ message: String) {
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    print(String(format: "%8.3f", elapsed), message)
    fflush(stdout)
}

// Two observation points distinguish events entering the app's session tap from
// events surviving it. Listen-only taps cannot consume or transform any input.
let mask = [CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue,
            CGEventType.flagsChanged.rawValue, UInt32(14)]
    .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1) }
var taps: [CFMachPort] = []
var sources: [CFRunLoopSource] = []
for (index, location) in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap].enumerated() {
    guard let tap = CGEvent.tapCreate(tap: location, place: .tailAppendEventTap,
        options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                DispatchQueue.main.async {
                    log("Observation stopped by macOS; rerun the diagnostic.")
                    CFRunLoopStop(CFRunLoopGetMain())
                }
                return Unmanaged.passUnretained(event)
            }
            if let description = summary(event) {
                let stage = context == nil ? "HID" : "session"
                let flags = String(event.flags.rawValue, radix: 16)
                let replay = event.getIntegerValueField(.eventSourceUserData) == 0x4879706572436170
                let timestamp = event.timestamp
                DispatchQueue.main.async {
                    let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
                    log("\(stage) \(description) flags=0x\(flags) replay=\(replay) eventTime=\(timestamp) app=\(app) source=\(inputSourceID())")
                }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: index == 0 ? nil : UnsafeMutableRawPointer(bitPattern: 1)),
          let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
        fputs("Cannot observe keyboard events. Allow your terminal in System Settings > Privacy & Security > Input Monitoring, then rerun.\n", stderr)
        exit(1)
    }
    taps.append(tap)
    sources.append(source)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
}
let observer = DistributedNotificationCenter.default().addObserver(
    forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
    object: nil, queue: .main) { _ in log("input-source-changed source=\(inputSourceID())") }
log("Recording for 90 seconds. Compare HyperCaps Folders rename with HyperCaps disabled, then enabled. Ctrl-C stops early.")
log("initial source=\(inputSourceID())")
let timer = Timer.scheduledTimer(withTimeInterval: 90, repeats: false) { _ in CFRunLoopStop(CFRunLoopGetMain()) }
CFRunLoopRun()
timer.invalidate()
DistributedNotificationCenter.default().removeObserver(observer)
for tap in taps { CFMachPortInvalidate(tap) }
log("Finished.")
