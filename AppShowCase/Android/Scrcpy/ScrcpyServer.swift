import Foundation

enum ScrcpyError: LocalizedError {
    case forwardFailed(String)
    case serverStopped(String)
    case connectFailed
    case unsupportedCodec(UInt32)
    case brokenStream

    var errorDescription: String? {
        switch self {
        case .forwardFailed(let output):
            return "Kan geen adb-tunnel naar het toestel opzetten.\n\(output)"
        case .serverStopped(let log):
            let tail = log.trimmingCharacters(in: .whitespacesAndNewlines)
            return "De scrcpy-server op het toestel is gestopt." + (tail.isEmpty ? "" : "\n\n\(tail)")
        case .connectFailed:
            return "Kan geen verbinding maken met de scrcpy-server op het toestel. Ontgrendel het toestel en probeer opnieuw."
        case .unsupportedCodec(let codec):
            return "Onverwachte videocodec van het toestel (0x\(String(codec, radix: 16)))."
        case .brokenStream:
            return "De videostream van het toestel is beschadigd. Probeer opnieuw."
        }
    }
}

/// Zet scrcpy-server klaar op een Android-toestel en start hem.
///
/// - Eigen bestandsnaam en eigen `scid` (socketnaam), zodat we niet botsen met
///   een gewone scrcpy-installatie of een tweede toestel.
/// - Ruimt alleen zijn eigen tunnel op; nooit `kill-server` of `--remove-all`.
actor ScrcpyServer {
    static let remotePath = "/data/local/tmp/appshowcase-scrcpy-server.jar"

    let adb: ADBClient
    let serial: String
    let serverPath: String
    let version: String
    let quality: AndroidQuality
    /// 31-bit willekeurig id; bepaalt de socketnaam op het toestel.
    let scid = UInt32.random(in: 1...0x7FFF_FFFF)

    private var port: UInt16?
    private var forwardKey: UUID?
    private var process: Process?
    private var isStopped = false
    private let logTail = LogTail()

    init(adb: ADBClient, serial: String, serverPath: String, version: String, quality: AndroidQuality = .normal) {
        self.adb = adb
        self.serial = serial
        self.serverPath = serverPath
        self.version = version
        self.quality = quality
    }

    var socketName: String { String(format: "scrcpy_%08x", scid) }

    /// Pusht en start de server; geeft de lokale TCP-poort van de tunnel terug.
    func start(onExit: @escaping @Sendable (String) -> Void) async throws -> UInt16 {
        try await adb.run(["-s", serial, "push", serverPath, Self.remotePath])
        try abortIfStopped()

        let output = try await adb.run(["-s", serial, "forward", "tcp:0", "localabstract:\(socketName)"])
        guard let port = Self.parseForwardPort(output) else {
            throw ScrcpyError.forwardFailed(output)
        }
        self.port = port
        forwardKey = ADBCleanup.shared.registerForward(adbPath: adb.path, serial: serial, port: port)
        try abortIfStopped()

        let logTail = self.logTail
        process = try adb.launch(
            serverArguments,
            onOutput: { chunk in logTail.append(chunk) },
            onExit: { _ in onExit(logTail.text) }
        )
        return port
    }

    func stop() async {
        isStopped = true
        await tearDown()
    }

    // MARK: - Intern

    private var serverArguments: [String] {
        Self.serverArguments(serial: serial, scid: scid, version: version, quality: quality)
    }

    /// De volledige `adb shell`-aanroep voor scrcpy-server (puur, getest).
    static func serverArguments(serial: String, scid: UInt32, version: String, quality: AndroidQuality) -> [String] {
        [
            "-s", serial, "shell",
            "CLASSPATH=\(remotePath)",
            "app_process", "/", "com.genymobile.scrcpy.Server", version,
            String(format: "scid=%08x", scid),
            "log_level=info",
            "tunnel_forward=true",
            "audio=false",
            "control=false",
            "video_codec=h264",
            "max_fps=\(quality.maxFPS)",
            "video_bit_rate=\(quality.bitRate)",
            // send_dummy_byte, send_device_meta, send_codec_meta en send_frame_meta staan standaard aan.
        ]
    }

    private func abortIfStopped() throws {
        if isStopped {
            // Kan na een await gebeuren; tearDown wordt dan door stop() al (deels) gedaan.
            Task { await self.tearDown() }
            throw CancellationError()
        }
    }

    private func tearDown() async {
        process?.terminate()
        process = nil
        if let forwardKey {
            ADBCleanup.shared.unregisterForward(forwardKey)
            self.forwardKey = nil
        }
        if let port {
            self.port = nil
            _ = try? await adb.run(["-s", serial, "forward", "--remove", "tcp:\(port)"])
        }
    }

    /// `adb forward tcp:0 …` print het gekozen poortnummer.
    static func parseForwardPort(_ output: String) -> UInt16? {
        UInt16(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Bewaart de laatste regels serveruitvoer (voor foutmeldingen) en logt ze naar de console.
final class LogTail: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private let maxLines = 12

    func append(_ chunk: String) {
        let newLines = chunk.split(whereSeparator: \.isNewline).map(String.init)
        for line in newLines { print("[scrcpy] \(line)") }
        lock.withLock {
            lines.append(contentsOf: newLines)
            if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        }
    }

    var text: String {
        lock.withLock { lines.joined(separator: "\n") }
    }
}
