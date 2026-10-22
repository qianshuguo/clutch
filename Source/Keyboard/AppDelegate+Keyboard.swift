import Cocoa
import ApplicationServices

// Runs work right after the current tap callback, in every mode the tap runs in.
// DispatchQueue.main would defer it while a modal session started from a
// main-queue block (such as the launch confirmation) is running.
func performOnMainRunLoop(_ work: @escaping () -> Void) {
    let mainLoop = CFRunLoopGetMain()
    CFRunLoopPerformBlock(mainLoop, CFRunLoopMode.commonModes.rawValue, work)
    CFRunLoopWakeUp(mainLoop)
}

extension AppDelegate {
    @objc func toggle() {
        if wantsEnabled || tap != nil {
            wantsEnabled = false; UserDefaults.standard.set(false, forKey: DefaultsKey.enabled); stop()
        } else {
            wantsEnabled = true; UserDefaults.standard.set(true, forKey: DefaultsKey.enabled)
            if !AXIsProcessTrusted() {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
            start()
        }
    }
    func start() {
        guard tap == nil, !starting else { return }
        guard AXIsProcessTrusted() else {
            setStatus("Waiting for Accessibility access. Clutch will enable automatically.")
            if permissionTimer == nil {
                permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    if self.wantsEnabled && AXIsProcessTrusted() { self.start() }
                }
            }
            return
        }
        permissionTimer?.invalidate(); permissionTimer = nil
        starting = true; defer { starting = false }
        // Install the F18 mapping before the tap exists, so no event is filtered
        // while the mapping or the state machine is still being prepared.
        do { try mapping.install() } catch { failKeyboard(error: error); return }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context = context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().handle(type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            failKeyboard(status: "Could not monitor the keyboard. Allow Accessibility access and reopen Clutch.")
            updateToggleMenuTitle("Retry Enabling")
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0) else {
            CFMachPortInvalidate(created)
            failKeyboard(status: "Could not start keyboard monitoring.")
            return
        }
        state.reset()
        tap = created
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        setStatus("Enabled.")
    }
    @discardableResult func stop() -> Bool {
        guard let error = teardown() else { return true }
        showError(error)
        return false
    }
    // Removes the tap and restores Caps Lock. Returns the restore error, if any,
    // so callers decide how to report it.
    func teardown() -> Error? {
        permissionTimer?.invalidate(); permissionTimer = nil
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; runLoopSource = nil; state.reset()
        capsHUDActive = false; capsOverlay.reset()
        do { try mapping.restore() } catch { return error }
        setStatus("Disabled. The original Caps Lock mapping has been restored.")
        return nil
    }
    // Report the original failure only after cleanup succeeds. A restore error
    // is already reported by stop(), and must not be overwritten by success text.
    func failKeyboard(error: Error? = nil, status: String? = nil) {
        wantsEnabled = false
        guard stop() else { return }
        if let error = error { showError(error) }
        else if let status = status { setStatus(status) }
    }
    func afterKeyEvent(_ work: @escaping () -> Void) { performOnMainRunLoop(work) }
    var folderSelectionPanel: FolderPanel? {
        guard let panel = folderWindow, panel.isKeyWindow, panel.attachedSheet == nil,
              let table = folderTable else { return nil }
        // The list or its search field (whose field editor has the focus while typing).
        let searching = (panel.firstResponder as? NSTextView).map { editor in
            folderList?.searchField.map { editor.delegate === $0 } ?? false
        } ?? false
        guard panel.firstResponder === table || searching else { return nil }
        return panel
    }
    enum KeyboardContext {
        case shortcuts, launchConfirmation, shortcutRecording, folderEditing
        case folders(FolderPanel)
    }
    var keyboardContext: KeyboardContext {
        if showingLaunchConfirmation { return .launchConfirmation }
        if let panel = folderWindow, panel.isKeyWindow {
            if folderSelectionPanel === panel { return .folders(panel) }
            return .folderEditing
        }
        if let recorder = window?.firstResponder as? KeyRecorder, recorder.recording {
            return .shortcutRecording
        }
        return .shortcuts
    }
    static let hiddenInputGap: TimeInterval = 0.3
    // Hardware key state, independent of what the tap was allowed to see.
    static func isKeyDown(_ key: UInt16) -> Bool {
        CGEventSource.keyState(.hidSystemState, key: CGKeyCode(key))
            || CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(key))
    }
    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout:
            // macOS disables a tap whose callback was late (for example while the main
            // thread was busy). Resume immediately; missed releases are recovered below.
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .tapDisabledByUserInput:
            wantsEnabled = false
            afterKeyEvent { [weak self] in
                self?.failKeyboard(status: "Keyboard monitoring stopped. Caps Lock was restored. Enable Clutch to retry.")
            }
            return Unmanaged.passUnretained(event)
        default:
            break
        }
        if event.getIntegerValueField(.eventSourceUserData) == CapsReplay.marker {
            return Unmanaged.passUnretained(event)
        }
        let key = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        // macOS changing Caps Lock (its light coming on) reports a flags change that is
        // not a modifier key being pressed. It must not count as one, or a long Caps hold
        // would turn into a chord and its Caps Lock would be undone. Caps Lock (57) is not
        // in the modifier table, so this check covers it.
        if type == .flagsChanged && !KeyboardState.isModifierKey(key) {
            return Unmanaged.passUnretained(event)
        }
        // Secure Event Input (password fields, Terminal's Secure Keyboard Entry) hides
        // events, including releases, from the tap. The first event after such a quiet
        // period is checked against the hardware, so a hidden release cannot leave a key
        // swallowed forever or Caps "held" (which would turn typing into app launches).
        // Back-to-back events are not checked: a release that is merely still queued
        // behind them must keep its normal handling.
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastKeyEventUptime > Self.hiddenInputGap {
            state.dropMissedReleases(except: key, isDown: Self.isKeyDown)
            if state.held, key != KeyCode.hyper, !Self.isKeyDown(KeyCode.hyper) {
                state.capsReleaseMissed()
            }
        }
        lastKeyEventUptime = now
        // Context controls only chord actions. Standalone Caps always follows
        // the same state machine and system replay path.
        let panel: FolderPanel?
        let shortcutsEnabled: Bool
        switch keyboardContext {
        case .launchConfirmation, .shortcutRecording, .folderEditing:
            panel = nil
            shortcutsEnabled = false
        case .folders(let activePanel):
            panel = activePanel
            shortcutsEnabled = false
        case .shortcuts:
            panel = nil
            shortcutsEnabled = true
        }
        let otherModifier = !event.flags.intersection([.maskControl, .maskAlternate]).isEmpty
        let commandModifier = event.flags.contains(.maskCommand)
        // What a fresh key-down while Caps is held could mean. The shortcut itself is
        // looked up when Caps is released.
        let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let eligible = shortcutsEnabled && type == .keyDown && state.held && key != KeyCode.hyper && key != KeyCode.space && !repeated
        let windowKey = eligible && windowShortcuts.command(for: key) != nil
        let bound = eligible && !windowKey && bindings.contains(where: { $0.matches(key, nil) })
        let prefix = eligible && !windowKey && bindings.contains(where: { $0.hasShortcut && $0.key == key && $0.secondKey != nil })
        // Second key after the first (Caps + M + W).
        let comboBound = eligible && state.pendingKey.map { first in bindings.contains(where: { $0.matches(first, key) }) } == true
        let capsWasHeld = state.held
        let result: KeyboardState.Result
        if type == .flagsChanged {
            let pressed = KeyboardState.modifierPressed(key: key, flags: event.flags.rawValue)
            result = state.modifierChanged(key: key, otherModifier: otherModifier, commandModifier: commandModifier,
                                           folderSelectionActive: panel != nil, shortcutsEnabled: shortcutsEnabled,
                                           pressed: pressed)
        } else {
            result = state.route(key: key, down: type == .keyDown,
                                 repeated: repeated, bound: bound, prefix: prefix, comboBound: comboBound,
                                 windowKey: windowKey,
                                 otherModifier: otherModifier, commandModifier: commandModifier,
                                 folderSelectionActive: panel != nil,
                                 // Rows shown, so a search with no matches opens nothing.
                                 folderCount: folderList?.table.numberOfRows ?? folders.count,
                                 shortcutsEnabled: shortcutsEnabled)
        }
        updateLaunchHint(shortcutsEnabled: shortcutsEnabled)
        // While a field records, Caps is input to the field, not a Caps Lock toggle.
        let recordingWithCaps = (window?.firstResponder as? KeyRecorder)?.recording == true
        updateCapsHUD(shortcutsEnabled: shortcutsEnabled, recordingWithCaps: recordingWithCaps, openingFolders: result.showFolders)
        if routeCapsRecording(type, key: key, capsWasHeld: capsWasHeld, repeated: repeated, flags: event.flags) == true {
            return nil
        }
        if result.showFolders {
            afterKeyEvent { [weak self] in self?.showFolders() }
        }
        if result.tap && !recordingWithCaps {
            afterKeyEvent { [weak self] in
                guard let self = self else { return }
                do { try self.replayCapsTap() }
                catch { self.failKeyboard(error: error) }
            }
        }
        if let first = result.launch,
           let target = bindings.first(where: { $0.matches(first, result.launchSecond) }) {
            afterKeyEvent { [weak self] in self?.activate(target) }
        }
        if let previewKey = result.windowPreview, let command = windowShortcuts.command(for: previewKey) {
            afterKeyEvent { [weak self] in self?.previewWindowCommand(command) }
        }
        if result.window != nil {
            afterKeyEvent { [weak self] in self?.commitWindowPreview() }
        } else if let session = windowPreview, !session.commitRequested, !state.windowPreviewActive {
            // Escape, another key, a modifier, a focus change, or Caps released without
            // a window shortcut: drop the preview.
            afterKeyEvent { [weak self] in self?.cancelWindowPreview() }
        }
        if panel != nil, key == KeyCode.hyper, type == .keyDown, !capsWasHeld {
            afterKeyEvent { [weak self] in self?.folderList?.resetCapsJump() }
        }
        if let panel = panel, result.folderNumber != nil || result.folderJump != nil || result.openFolderSelection {
            afterKeyEvent { [weak self, weak panel] in
                guard let self = self, let panel = panel, self.folderSelectionPanel === panel else { return }
                if let number = result.folderNumber {
                    self.folderList?.resetCapsJump()
                    panel.selectNumber?(number)
                }
                if let key = result.folderJump { self.folderList?.jumpToFolder(key: key, time: now) }
                if result.openFolderSelection { panel.openSelection?() }
            }
        }
        // Other keys go to the focused view's native navigation and editing commands.
        if result.stripCommandModifier { event.flags.remove(.maskCommand) }
        return result.swallow ? nil : Unmanaged.passUnretained(event)
    }
    // Called for every key event after the launch hint. One HUD window, resizing: the
    // keys pressed so far ("⇪ M W") with "No matching app"; or, when they select an app,
    // grown into the app card (updateLaunchHint) with the keys on top. Caps held
    // alone shows nothing: the keyboard light shows Caps Lock. Caps + Space hides the
    // pill at once as the Folders panel opens.
    func updateCapsHUD(shortcutsEnabled: Bool, recordingWithCaps: Bool, openingFolders: Bool) {
        if openingFolders {
            // The Folders panel replaces the pill at once.
            capsHUDActive = false
            capsOverlay.hideKeys(immediately: true)
            return
        }
        enum Display { case keys(String), app(String), hidden }
        let display: Display
        // The launch confirmation needs no Caps hint, and the open Folders panel has its
        // search field where the pill would be.
        // A window action shows its own preview; the Caps HUD gets out of the way.
        if recordingWithCaps || showingLaunchConfirmation || folderWindow?.isVisible == true || state.windowGesture {
            display = .hidden
        } else if shortcutsEnabled && state.showsKeyHint {
            let keys = state.pressedKeys.map { keyName($0) ?? "?" }.joined(separator: " ")
            // Show the app card for a match; otherwise explicitly say no app matches.
            display = capsOverlay.target != nil ? .app(keys) : .keys(keys)
        } else {
            display = .hidden
        }
        if case .hidden = display {
            guard capsHUDActive else { return }
            capsHUDActive = false
            capsOverlay.hideKeys()
            return
        }
        capsHUDActive = true
        // Only records what to show; the overlay updates its one window after the key
        // event, together with the app from updateLaunchHint.
        switch display {
        case .keys(let keys):
            capsOverlay.showKeys(keys)
        case .app(let keys):
            // The same window grows into the app card and keeps the keys on top.
            capsOverlay.showAppKeys(keys)
        case .hidden:
            break
        }
    }
    // App List fields are recorded the way shortcuts are used: keys pressed while Caps
    // is held go to the recording field (and not to the window), and releasing Caps
    // saves them. Returns true when the event is consumed, nil when not recording.
    func routeCapsRecording(_ type: CGEventType, key: UInt16, capsWasHeld: Bool,
                            repeated: Bool, flags: CGEventFlags) -> Bool? {
        guard type == .keyDown || type == .keyUp,
              let recorder = window?.firstResponder as? KeyRecorder, recorder.recording else {
            // Releases are only owned while recording; later ones pass through.
            recordingCapsKeys.removeAll()
            return nil
        }
        if key == KeyCode.hyper {
            if type == .keyDown && !capsWasHeld && !repeated {
                afterKeyEvent { [weak recorder] in recorder?.capsPressed() }
            } else if type == .keyUp && capsWasHeld {
                afterKeyEvent { [weak recorder] in recorder?.capsReleased() }
            }
            return false
        }
        if type == .keyUp { return recordingCapsKeys.remove(key) != nil }
        guard capsWasHeld,
              flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand]).isEmpty else { return false }
        recordingCapsKeys.insert(key)
        if !repeated {
            afterKeyEvent { [weak recorder] in recorder?.capsKeyPressed(key) }
        }
        return true
    }
}
