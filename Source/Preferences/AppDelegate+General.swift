import Cocoa
import ServiceManagement
import ApplicationServices

extension AppDelegate {
    // macOS 12 has no SMAppService, so Launch on Login installs this LaunchAgent there.
    static let launchAgentLabel = "local.maxvoid.Clutch.login"
    var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(Self.launchAgentLabel).plist")
    }
    var launchAgentExists: Bool { FileManager.default.fileExists(atPath: launchAgentURL.path) }
    // On macOS 13+, a LaunchAgent left from macOS 12 also launches Clutch at login,
    // so it counts as enabled until it is removed.
    var loginLaunchEnabled: Bool {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            if status == .enabled || status == .requiresApproval { return true }
        }
        return launchAgentExists
    }
    func syncPreferences() {
        toggleButton?.state = wantsEnabled ? .on : .off
        loginCheckbox?.state = loginLaunchEnabled ? .on : .off
        hideCheckbox?.state = UserDefaults.standard.bool(forKey: DefaultsKey.hideStatusBarIcon) ? .on : .off
        let hideNotice = !(wantsEnabled && tap == nil && !AXIsProcessTrusted())
        accessibilityNoticeRow?.isHidden = hideNotice
    }
    @objc func changeLoginLaunch(_ sender: NSButton) {
        do {
            if #available(macOS 13.0, *) {
                let service = SMAppService.mainApp
                if sender.state == .on {
                    try service.register()
                    if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
                } else if service.status == .enabled || service.status == .requiresApproval {
                    try service.unregister()
                }
                // One login mechanism only: a leftover LaunchAgent would start a second
                // instance at login, which would then open Preferences in the first.
                if launchAgentExists { try FileManager.default.removeItem(at: launchAgentURL) }
            } else if sender.state == .on {
                guard let executable = Bundle.main.executableURL else { throw ToolError(message: "Could not locate Clutch.") }
                let plist: [String: Any] = ["Label": Self.launchAgentLabel, "ProgramArguments": [executable.path], "RunAtLoad": true]
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try FileManager.default.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: launchAgentURL, options: .atomic)
            } else if launchAgentExists {
                try FileManager.default.removeItem(at: launchAgentURL)
            }
        } catch { showError(error) }
        syncPreferences()
    }
    @objc func changeStatusIcon(_ sender: NSButton) {
        let hidden = sender.state == .on
        UserDefaults.standard.set(hidden, forKey: DefaultsKey.hideStatusBarIcon)
        item.isVisible = !hidden
    }
    @objc func openPermissions() {
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
