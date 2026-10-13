import AppKit
import Foundation
import Observation

/// Volgt via adb welke Android-toestellen zijn aangesloten en meldt ze aan de `DeviceRegistry`.
@MainActor
@Observable
final class AndroidDiscovery {
    enum Status: Equatable {
        case starting
        case running
        case adbMissing
        case failed(String)
    }

    private(set) var status: Status = .starting
    /// Pad naar de gebruikte adb (handig voor diagnose).
    let adbPath: String?

    @ObservationIgnored private let registry: DeviceRegistry
    @ObservationIgnored private let adb: ADBClient?
    @ObservationIgnored private var trackProcess: Process?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var isTerminating = false
    @ObservationIgnored private var terminateToken: NSObjectProtocol?

    init(registry: DeviceRegistry) {
        self.registry = registry
        let path = ADBLocator.locate()
        adbPath = path
        adb = path.map(ADBClient.init(path:))
        print("[AndroidDiscovery] adb: \(path ?? "niet gevonden")")

        terminateToken = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutDown() }
        }
        startTracking()
    }

    /// Maakt een beeldbron voor een Android-toestel.
    func makeSource(serial: String) throws -> AndroidScrcpySource {
        guard let adb else { throw AndroidSetupError.adbMissing }
        guard let serverPath = Bundle.main.path(forResource: "scrcpy-server", ofType: nil) else {
            throw AndroidSetupError.serverMissing
        }
        return AndroidScrcpySource(
            adb: adb, serial: serial, serverPath: serverPath,
            serverVersion: Self.scrcpyVersion, quality: AndroidQuality.current()
        )
    }

    /// Demo-hulpjes (scherm aan, aanrakingen, statusbalk) voor een Android-toestel.
    func makeDemoMode(serial: String) -> AndroidDemoMode? {
        adb.map { AndroidDemoMode(adb: $0, serial: serial) }
    }

    /// Versie van de meegeleverde scrcpy-server (moet exact overeenkomen met wat we de server vertellen).
    static var scrcpyVersion: String {
        guard let url = Bundle.main.url(forResource: "scrcpy-server", withExtension: "version"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "3.3.1" }
        let version = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? "3.3.1" : version
    }

    // MARK: - Volgen

    private func startTracking() {
        guard let adb else {
            status = .adbMissing
            return
        }
        do {
            // track-devices meldt elke wijziging; daarna halen we de volledige lijst op.
            trackProcess = try adb.launch(
                ["track-devices"],
                onOutput: { [weak self] _ in
                    Task { @MainActor in self?.scheduleRefresh() }
                },
                onExit: { [weak self] _ in
                    Task { @MainActor in self?.trackingEnded() }
                }
            )
            status = .running
            scheduleRefresh()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func trackingEnded() {
        trackProcess = nil
        guard !isTerminating else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.startTracking()
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func refresh() async {
        guard let adb else { return }
        do {
            let output = try await adb.run(["devices", "-l"])
            let entries = ADBDeviceListParser.parse(output)
            registry.replaceDevices(of: .android, with: entries.map(\.deviceInfo))
        } catch {
            print("[AndroidDiscovery] devices -l mislukt: \(error.localizedDescription)")
        }
    }

    private func shutDown() {
        isTerminating = true
        trackProcess?.terminate()
        ADBCleanup.shared.cleanUpEverything()
    }
}

enum AndroidSetupError: LocalizedError {
    case adbMissing
    case serverMissing

    var errorDescription: String? {
        switch self {
        case .adbMissing:
            return "adb niet gevonden. Installeer Android Studio of draai ./scripts/fetch-deps.sh en bouw opnieuw."
        case .serverMissing:
            return "scrcpy-server ontbreekt in de app. Draai ./scripts/fetch-deps.sh en bouw opnieuw."
        }
    }
}
