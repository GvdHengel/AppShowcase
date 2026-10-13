import Foundation

/// Fouten bij het aanroepen van adb.
enum ADBError: LocalizedError {
    case launchFailed(String)
    case commandFailed(command: String, status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let reason):
            return "Kan adb niet starten: \(reason)"
        case .commandFailed(let command, let status, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "adb \(command) mislukte (code \(status))" + (detail.isEmpty ? "." : ":\n\(detail)")
        }
    }
}

/// Dunne wrapper om de adb-binary.
struct ADBClient: Sendable {
    let path: String

    /// Voert een adb-commando uit en geeft stdout terug.
    @discardableResult
    func run(_ arguments: [String]) async throws -> String {
        let path = self.path
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.standardInput = FileHandle.nullDevice
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ADBError.launchFailed(error.localizedDescription))
                    return
                }

                // stdout en stderr tegelijk leeglezen, zodat een volle pipe het proces niet blokkeert.
                // Zelfde QoS als deze thread: voorkomt een prioriteitsinversie-waarschuwing.
                let errorBox = DataBox()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    errorBox.data = stderr.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()

                let output = String(decoding: outData, as: UTF8.self)
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let errorText = String(decoding: errorBox.data, as: UTF8.self)
                    continuation.resume(throwing: ADBError.commandFailed(
                        command: arguments.filter { $0 != "-s" }.prefix(3).joined(separator: " "),
                        status: process.terminationStatus,
                        output: errorText.isEmpty ? output : errorText
                    ))
                }
            }
        }
    }

    /// Start een langlopend adb-proces (bijv. `track-devices` of de scrcpy-server).
    /// De uitvoer wordt continu gelezen; anders loopt het proces vast op een volle pipe.
    func launch(_ arguments: [String],
                onOutput: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                onOutput(String(decoding: data, as: UTF8.self))
            }
        }
        process.terminationHandler = { finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            ADBCleanup.shared.unregister(finished)
            onExit(finished.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            throw ADBError.launchFailed(error.localizedDescription)
        }
        ADBCleanup.shared.register(process)
        return process
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// Houdt bij welke adb-processen en tunnels wij gestart hebben, zodat we die bij afsluiten opruimen.
/// Bewust GEEN `adb kill-server`: Android Studio kan dezelfde adb-server gebruiken.
final class ADBCleanup: @unchecked Sendable {
    static let shared = ADBCleanup()

    private struct Forward {
        let adbPath: String
        let serial: String
        let port: UInt16
    }

    private struct Restore {
        let adbPath: String
        let serial: String
        let shellCommands: [[String]]
    }

    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]
    private var forwards: [UUID: Forward] = [:]
    private var restores: [UUID: Restore] = [:]

    func register(_ process: Process) {
        lock.withLock { processes[ObjectIdentifier(process)] = process }
    }

    func unregister(_ process: Process) {
        _ = lock.withLock { processes.removeValue(forKey: ObjectIdentifier(process)) }
    }

    func registerForward(adbPath: String, serial: String, port: UInt16) -> UUID {
        let key = UUID()
        lock.withLock { forwards[key] = Forward(adbPath: adbPath, serial: serial, port: port) }
        return key
    }

    func unregisterForward(_ key: UUID) {
        _ = lock.withLock { forwards.removeValue(forKey: key) }
    }

    /// Instellingen die bij afsluiten teruggezet moeten worden (bijv. Android-demomodus).
    func registerRestore(adbPath: String, serial: String, shellCommands: [[String]]) -> UUID {
        let key = UUID()
        lock.withLock { restores[key] = Restore(adbPath: adbPath, serial: serial, shellCommands: shellCommands) }
        return key
    }

    func unregisterRestore(_ key: UUID) {
        _ = lock.withLock { restores.removeValue(forKey: key) }
    }

    /// Synchroon opruimen; bedoeld voor `applicationWillTerminate`.
    func cleanUpEverything() {
        let (running, tunnels, pendingRestores) = lock.withLock {
            (Array(processes.values), Array(forwards.values), Array(restores.values))
        }
        for restore in pendingRestores {
            for command in restore.shellCommands {
                Self.runSync(adbPath: restore.adbPath, arguments: ["-s", restore.serial, "shell"] + command)
            }
        }
        running.forEach { $0.terminate() }
        for tunnel in tunnels {
            Self.runSync(adbPath: tunnel.adbPath, arguments: ["-s", tunnel.serial, "forward", "--remove", "tcp:\(tunnel.port)"])
        }
        lock.withLock {
            processes.removeAll()
            forwards.removeAll()
            restores.removeAll()
        }
    }

    private static func runSync(adbPath: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
