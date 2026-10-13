import CoreMedia
import Foundation
import Network

/// Beeldbron voor een Android-toestel via scrcpy-server.
///
/// Stroom: server starten → TCP via adb-tunnel → `ScrcpyStreamParser` → `H264Decoder` → frames.
/// `start`/`stop` worden op de main thread aangeroepen; al het netwerk- en decodeerwerk
/// gebeurt op één eigen seriële queue. Daardoor veilig te delen tussen threads (`@unchecked Sendable`).
final class AndroidScrcpySource: FrameSource, @unchecked Sendable {
    var frameHandler: (@Sendable (CMSampleBuffer) -> Void)?
    var eventHandler: (@Sendable (SourceEvent) -> Void)?

    private let adb: ADBClient
    private let serial: String
    private let serverPath: String
    private let serverVersion: String

    // Alleen op de main thread gebruikt.
    private var server: ScrcpyServer?
    private var startTask: Task<Void, Never>?

    // Alleen op `queue` gebruikt.
    private let queue: DispatchQueue
    private var connection: NWConnection?
    private var parser = ScrcpyStreamParser()
    private let decoder: H264Decoder
    private var receivedDummyByte = false
    private var lastSize: CGSize = .zero
    private var stopped = false

    /// Zo vaak proberen we te verbinden voordat de server luistert (× 250 ms ≈ 10 s).
    private let maxConnectAttempts = 40

    init(adb: ADBClient, serial: String, serverPath: String, serverVersion: String) {
        self.adb = adb
        self.serial = serial
        self.serverPath = serverPath
        self.serverVersion = serverVersion
        queue = DispatchQueue(label: "nl.gvdhengel.AppShowCase.android.\(serial)", qos: .userInteractive)
        decoder = H264Decoder(deliveryQueue: queue)
        decoder.onFrame = { [weak self] sampleBuffer, size in
            self?.deliver(sampleBuffer, size: size)
        }
    }

    func start() {
        let server = ScrcpyServer(adb: adb, serial: serial, serverPath: serverPath, version: serverVersion)
        self.server = server

        startTask = Task { [weak self] in
            do {
                let port = try await server.start(onExit: { [weak self] log in
                    self?.queue.async { self?.serverExited(log: log) }
                })
                self?.queue.async { self?.connect(port: port, attempt: 0) }
            } catch is CancellationError {
                // gestopt tijdens het starten
            } catch {
                self?.eventHandler?(.failed(Self.message(for: error)))
            }
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        if let server {
            Task { await server.stop() }
        }
        server = nil

        queue.async { [self] in
            stopped = true
            connection?.cancel()
            connection = nil
            decoder.invalidate()
        }
    }

    // MARK: - Verbinding (op queue)

    private func connect(port: UInt16, attempt: Int) {
        guard !stopped, let endpointPort = NWEndpoint.Port(rawValue: port) else { return }

        parser = ScrcpyStreamParser()
        receivedDummyByte = false

        let newConnection = NWConnection(host: "127.0.0.1", port: endpointPort, using: .tcp)
        connection = newConnection
        newConnection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .failed = state {
                self.connectionEnded(newConnection, port: port, attempt: attempt)
            }
        }
        newConnection.start(queue: queue)
        receive(on: newConnection, port: port, attempt: attempt)
    }

    private func receive(on current: NWConnection, port: UInt16, attempt: Int) {
        current.receive(minimumIncompleteLength: 1, maximumLength: 1 << 17) { [weak self] data, _, isComplete, error in
            guard let self, !self.stopped, current === self.connection else { return }
            if let data, !data.isEmpty {
                self.consume(data)
            }
            if isComplete || error != nil {
                self.connectionEnded(current, port: port, attempt: attempt)
            } else if current === self.connection {
                self.receive(on: current, port: port, attempt: attempt)
            }
        }
    }

    /// De verbinding sloot. Vóór de dummy-byte betekent dat: server luistert nog niet → opnieuw.
    private func connectionEnded(_ ended: NWConnection, port: UInt16, attempt: Int) {
        guard !stopped, ended === connection else { return }
        ended.cancel()
        connection = nil

        if receivedDummyByte {
            fail(ScrcpyError.serverStopped("De videostream is beëindigd."))
        } else if attempt + 1 < maxConnectAttempts {
            queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.connect(port: port, attempt: attempt + 1)
            }
        } else {
            fail(ScrcpyError.connectFailed)
        }
    }

    private func consume(_ data: Data) {
        do {
            for event in try parser.feed(data) {
                switch event {
                case .dummyByte:
                    receivedDummyByte = true
                    eventHandler?(.started)
                case .deviceName(let name):
                    print("[AndroidScrcpySource] verbonden met \(name)")
                case .codecMeta(let codec, let width, let height):
                    print("[AndroidScrcpySource] codec 0x\(String(codec, radix: 16)) \(width)×\(height)")
                    guard codec == ScrcpyStreamParser.codecH264 else {
                        fail(ScrcpyError.unsupportedCodec(codec))
                        return
                    }
                case .packet(let packet):
                    decoder.decode(packet)
                }
            }
        } catch {
            fail(ScrcpyError.brokenStream)
        }
    }

    private func serverExited(log: String) {
        guard !stopped else { return }
        fail(ScrcpyError.serverStopped(log))
    }

    private func fail(_ error: Error) {
        guard !stopped else { return }
        stopped = true
        connection?.cancel()
        connection = nil
        eventHandler?(.failed(Self.message(for: error)))
    }

    // MARK: - Frames (op queue)

    private func deliver(_ sampleBuffer: CMSampleBuffer, size: CGSize) {
        guard !stopped else { return }
        if size != lastSize {
            lastSize = size
            eventHandler?(.videoSizeChanged(size))
        }
        frameHandler?(sampleBuffer)
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
