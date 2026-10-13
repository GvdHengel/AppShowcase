import AppKit
import Observation

/// Houdt bij of QuickTime Player draait.
///
/// QuickTime kan het scherm van een aangesloten iPhone "bezet" houden (Nieuwe filmopname met
/// de iPhone als bron). Dan krijgt AppShowCase geen beeld. Het toestelvenster toont in dat geval
/// een duidelijke melding met een knop om QuickTime te sluiten, en verbindt daarna vanzelf opnieuw.
@MainActor
@Observable
final class QuickTimeMonitor {
    nonisolated static let bundleIdentifier = "com.apple.QuickTimePlayerX"

    private(set) var isRunning = false

    @ObservationIgnored private var tokens: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard QuickTimeMonitor.isQuickTime(bundleID: app?.bundleIdentifier) else { return }
                MainActor.assumeIsolated { self?.refresh() }
            }
            tokens.append(token)
        }
    }

    func refresh() {
        isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
    }

    /// Vraagt QuickTime netjes om te stoppen (QuickTime kan nog vragen om iets te bewaren).
    func quit() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier) {
            app.terminate()
        }
    }

    nonisolated static func isQuickTime(bundleID: String?) -> Bool {
        bundleID == bundleIdentifier
    }
}
