import Foundation
import Observation

/// Demo-hulpjes voor Android via adb: scherm aan houden, aanrakingen tonen en een schone statusbalk.
///
/// Oorspronkelijke instellingen worden bewaard en teruggezet bij uitzetten, bij sluiten van het
/// venster (`restoreAll`) en — via `ADBCleanup` — bij afsluiten van de app.
@MainActor
@Observable
final class AndroidDemoMode {
    private(set) var stayAwake = false
    private(set) var showTouches = false
    private(set) var cleanStatusBar = false
    private(set) var lastError: String?

    let serial: String
    @ObservationIgnored private let adb: ADBClient
    @ObservationIgnored private var originalStayOn: String?
    @ObservationIgnored private var originalShowTouches: String?
    @ObservationIgnored private var restoreKey: UUID?

    init(adb: ADBClient, serial: String) {
        self.adb = adb
        self.serial = serial
    }

    // MARK: - Schakelaars

    func setStayAwake(_ on: Bool) async {
        await perform {
            if on {
                if self.originalStayOn == nil {
                    let current = try await self.shell(["settings", "get", "global", "stay_on_while_plugged_in"])
                    self.originalStayOn = Self.normalized(current)
                }
                // 7 = aan blijven op AC, USB en draadloos laden.
                try await self.shell(["settings", "put", "global", "stay_on_while_plugged_in", "7"])
            } else {
                try await self.shell(["settings", "put", "global", "stay_on_while_plugged_in", self.originalStayOn ?? "0"])
                self.originalStayOn = nil
            }
            self.stayAwake = on
        }
    }

    func setShowTouches(_ on: Bool) async {
        await perform {
            if on {
                if self.originalShowTouches == nil {
                    let current = try await self.shell(["settings", "get", "system", "show_touches"])
                    self.originalShowTouches = Self.normalized(current)
                }
                try await self.shell(["settings", "put", "system", "show_touches", "1"])
            } else {
                try await self.shell(["settings", "put", "system", "show_touches", self.originalShowTouches ?? "0"])
                self.originalShowTouches = nil
            }
            self.showTouches = on
        }
    }

    func setCleanStatusBar(_ on: Bool) async {
        await perform {
            for command in on ? Self.cleanStatusBarCommands : [Self.exitDemoCommand] {
                try await self.shell(command)
            }
            self.cleanStatusBar = on
        }
    }

    /// Alles terugzetten (bij sluiten van het venster).
    func restoreAll() async {
        if stayAwake { await setStayAwake(false) }
        if showTouches { await setShowTouches(false) }
        if cleanStatusBar { await setCleanStatusBar(false) }
    }

    // MARK: - Commando's (puur, getest)

    /// Android "demo mode": tijd 9:41, volle batterij, volle wifi/mobiel, geen meldingen.
    nonisolated static let cleanStatusBarCommands: [[String]] = [
        ["settings", "put", "global", "sysui_demo_allowed", "1"],
        demo(["command", "enter"]),
        demo(["command", "clock", "hhmm", "0941"]),
        demo(["command", "battery", "level", "100", "plugged", "false"]),
        demo(["command", "network", "wifi", "show", "level", "4"]),
        demo(["command", "network", "mobile", "show", "datatype", "none", "level", "4"]),
        demo(["command", "notifications", "visible", "false"]),
    ]

    nonisolated static let exitDemoCommand: [String] = demo(["command", "exit"])

    /// `am broadcast -a com.android.systemui.demo -e <sleutel> <waarde> …`
    nonisolated static func demo(_ pairs: [String]) -> [String] {
        var arguments = ["am", "broadcast", "-a", "com.android.systemui.demo"]
        var index = 0
        while index + 1 < pairs.count {
            arguments += ["-e", pairs[index], pairs[index + 1]]
            index += 2
        }
        return arguments
    }

    /// `settings get` geeft "null" als de instelling nooit gezet is.
    nonisolated static func normalized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty || trimmed == "null") ? "0" : trimmed
    }

    /// Commando's om terug te zetten wat nu aan staat (voor afsluiten van de app).
    var restoreCommands: [[String]] {
        var commands: [[String]] = []
        if stayAwake { commands.append(["settings", "put", "global", "stay_on_while_plugged_in", originalStayOn ?? "0"]) }
        if showTouches { commands.append(["settings", "put", "system", "show_touches", originalShowTouches ?? "0"]) }
        if cleanStatusBar { commands.append(Self.exitDemoCommand) }
        return commands
    }

    // MARK: - Intern

    private func perform(_ work: () async throws -> Void) async {
        do {
            try await work()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            print("[AndroidDemoMode] \(error.localizedDescription)")
        }
        updateRestoreRegistration()
    }

    @discardableResult
    private func shell(_ arguments: [String]) async throws -> String {
        try await adb.run(["-s", serial, "shell"] + arguments)
    }

    private func updateRestoreRegistration() {
        if let restoreKey {
            ADBCleanup.shared.unregisterRestore(restoreKey)
            self.restoreKey = nil
        }
        let commands = restoreCommands
        if !commands.isEmpty {
            restoreKey = ADBCleanup.shared.registerRestore(adbPath: adb.path, serial: serial, shellCommands: commands)
        }
    }
}
