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
            refreshControls()
            logStatus("Waiting for Accessibility access. Clutch will enable automatically.")
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
        refreshControls()
        logStatus("Enabled.")
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
        capsOverlay.reset()
        refreshControls()
        do { try mapping.restore() } catch { return error }
        logStatus("Disabled. The original Caps Lock mapping has been restored.")
        return nil
    }
    // Cleans up, then reports the original failure. When restoring Caps Lock fails
    // too, stop() shows that error instead: it is the one the user must act on.
    func failKeyboard(error: Error? = nil, status: String? = nil) {
        wantsEnabled = false
        guard stop() else { return }
        if let error = error { showError(error) }
        else if let status = status { logStatus(status) }
    }
    // The KeyRecorder in Preferences that is recording a shortcut, if any.
    var activeRecorder: KeyRecorder? {
        guard let recorder = window?.firstResponder as? KeyRecorder, recorder.recording else { return nil }
        return recorder
    }
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
        if activeRecorder != nil { return .shortcutRecording }
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
            performOnMainRunLoop { [weak self] in
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
        var panel: FolderPanel?
        let input: KeyboardState.Input
        switch keyboardContext {
        case .launchConfirmation, .shortcutRecording, .folderEditing: input = .inactive
        case .folders(let activePanel): input = .folderPicker; panel = activePanel
        case .shortcuts: input = .shortcuts
        }
        let shortcutsEnabled = input == .shortcuts
        let otherModifier = !event.flags.intersection([.maskControl, .maskAlternate]).isEmpty
        let commandModifier = event.flags.contains(.maskCommand)
        // What a fresh key-down while Caps is held could mean. The shortcut itself is
        // looked up when Caps is released.
        let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let eligible = shortcutsEnabled && type == .keyDown && state.held && key != KeyCode.hyper && key != KeyCode.space && !repeated
        let windowKey = eligible && windowShortcuts.command(for: key) != nil
        // The app keys so far plus this one (Caps + M, then Caps + M + W, …). A window
        // key takes precedence only as the first key; later it is an ordinary key.
        let pendingKeys = state.pendingKeys ?? []
        let candidate = pendingKeys + [key]
        let appKey = eligible && (!pendingKeys.isEmpty || !windowKey)
        // App List, Folders and Websites shortcuts share one set of keys.
        let bound = appKey && shortcutTarget(for: candidate) != nil
        let prefix = appKey && shortcutExtends(candidate)
        let capsWasHeld = state.held
        let result: KeyboardState.Result
        if type == .flagsChanged {
            let pressed = KeyboardState.modifierPressed(key: key, flags: event.flags.rawValue)
            result = state.modifierChanged(key: key, otherModifier: otherModifier, commandModifier: commandModifier,
                                           input: input, pressed: pressed)
        } else {
            result = state.route(key: key, down: type == .keyDown,
                                 repeated: repeated, bound: bound, prefix: prefix,
                                 windowKey: windowKey,
                                 otherModifier: otherModifier, commandModifier: commandModifier,
                                 input: input,
                                 // Rows shown, so a search with no matches opens nothing.
                                 folderCount: folderList?.table.numberOfRows ?? folders.count)
        }
        updateLaunchHint(shortcutsEnabled: shortcutsEnabled)
        // While a field records, Caps is input to the field, not a Caps Lock toggle.
        let recorder = activeRecorder
        updateCapsHUD(shortcutsEnabled: shortcutsEnabled, recording: recorder != nil, openingFolders: result.showFolders)
        if routeCapsRecording(type, key: key, to: recorder, capsWasHeld: capsWasHeld, repeated: repeated, flags: event.flags) {
            return nil
        }
        if result.showFolders {
            performOnMainRunLoop { [weak self] in self?.showFolders() }
        }
        if result.tap && recorder == nil {
            performOnMainRunLoop { [weak self] in
                guard let self = self else { return }
                do { try self.replayCapsTap() }
                catch { self.failKeyboard(error: error) }
            }
        }
        switch result.launchKeys.flatMap({ shortcutTarget(for: $0) }) {
        case .app(let app)?: performOnMainRunLoop { [weak self] in self?.activate(app) }
        case .folder(let folder)?: performOnMainRunLoop { [weak self] in self?.openFolderShortcut(folder) }
        case .website(let site)?: performOnMainRunLoop { [weak self] in self?.openWebsiteShortcut(site) }
        case nil: break
        }
        if let previewKey = result.windowPreview, let command = windowShortcuts.command(for: previewKey) {
            performOnMainRunLoop { [weak self] in self?.previewWindowCommand(command) }
        }
        if result.window != nil {
            performOnMainRunLoop { [weak self] in self?.commitWindowPreview() }
        } else if let session = windowPreview, !session.commitRequested, !state.windowPreviewActive {
            // Escape, another key, a modifier, a focus change, or Caps released without
            // a window shortcut: drop the preview.
            performOnMainRunLoop { [weak self] in self?.cancelWindowPreview() }
        }
        if panel != nil, key == KeyCode.hyper, type == .keyDown, !capsWasHeld {
            performOnMainRunLoop { [weak self] in self?.folderList?.resetCapsJump() }
        }
        if let panel = panel, result.folderNumber != nil || result.folderJump != nil || result.openFolderSelection {
            performOnMainRunLoop { [weak self, weak panel] in
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
    func updateCapsHUD(shortcutsEnabled: Bool, recording: Bool, openingFolders: Bool) {
        // The launch confirmation needs no Caps hint, the open Folders panel has its
        // search field where the pill would be, and a window action shows its own preview.
        let hidden = recording || showingLaunchConfirmation || folderWindow?.isVisible == true || state.windowGesture
        if openingFolders {
            capsOverlay.hideKeys(immediately: true)
        } else if !hidden && shortcutsEnabled && state.showsKeyHint {
            // The overlay updates its one window after the key event, together with
            // the app from updateLaunchHint.
            capsOverlay.showKeys(state.pressedKeys.map { keyName($0) ?? "?" }.joined(separator: " "))
        } else {
            capsOverlay.hideKeys()
        }
    }
    // App List fields are recorded the way shortcuts are used: keys pressed while Caps
    // is held go to the recording field (and not to the window), and releasing Caps
    // saves them. Returns true when the event is consumed.
    func routeCapsRecording(_ type: CGEventType, key: UInt16, to recorder: KeyRecorder?, capsWasHeld: Bool,
                            repeated: Bool, flags: CGEventFlags) -> Bool {
        guard type == .keyDown || type == .keyUp, let recorder = recorder else {
            // Releases are only owned while recording; later ones pass through.
            recordingCapsKeys.removeAll()
            return false
        }
        if key == KeyCode.hyper {
            if type == .keyDown && !capsWasHeld && !repeated {
                performOnMainRunLoop { [weak recorder] in recorder?.capsPressed() }
            } else if type == .keyUp && capsWasHeld {
                performOnMainRunLoop { [weak recorder] in recorder?.capsReleased() }
            }
            return false
        }
        if type == .keyUp { return recordingCapsKeys.remove(key) != nil }
        guard capsWasHeld,
              flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand]).isEmpty else { return false }
        recordingCapsKeys.insert(key)
        // Caps + Return saves the field now; keys later in this hold must not run a
        // shortcut once the field stops recording.
        if KeyCode.isReturn(key) && !repeated { state.endHold() }
        if !repeated {
            performOnMainRunLoop { [weak recorder] in recorder?.capsKeyPressed(key) }
        }
        return true
    }
}
