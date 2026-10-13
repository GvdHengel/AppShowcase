import Foundation
import AVFoundation
import CoreMedia
import VideoToolbox
import Combine

// MARK: - ScrcpyClient

class ScrcpyClient: ObservableObject {

    // MARK: Published state
    @Published var isConnected = false
    @Published var errorMessage: String?
    @Published var videoSize: CGSize = .zero

    // Referentie naar de mirror view voor frame delivery
    weak var mirrorView: AndroidMirrorNSView?

    // MARK: Private
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var decompressionSession: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?

    private var spsData: [UInt8] = []
    private var ppsData: [UInt8] = []

    private let sessionQueue = DispatchQueue(label: "com.appshowcase.scrcpy", qos: .userInteractive)

    private var retryCount = 0
    private let maxRetries = 5
    private var retryTimer: DispatchSourceTimer?

    // MARK: - Verbinden

    func connect(port: UInt16 = 27183) {
        sessionQueue.async { [weak self] in
            self?.openStreams(port: port)
        }
    }

    func disconnect() {
        retryTimer?.cancel()
        retryTimer = nil
        inputStream?.close()
        outputStream?.close()
        inputStream = nil
        outputStream = nil
        decompressionSession = nil
        formatDescription = nil
        spsData = []
        ppsData = []
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
        }
    }

    // MARK: - Stream opening

    private func openStreams(port: UInt16) {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?

        CFStreamCreatePairWithSocketToHost(
            kCFAllocatorDefault,
            "127.0.0.1" as CFString,
            UInt32(port),
            &readStream,
            &writeStream
        )

        guard let input = readStream?.takeRetainedValue(),
              let output = writeStream?.takeRetainedValue() else {
            scheduleRetry(port: port)
            return
        }

        inputStream = input as InputStream
        outputStream = output as OutputStream

        inputStream?.open()
        outputStream?.open()

        // Wacht kort zodat de TCP verbinding tot stand komt
        Thread.sleep(forTimeInterval: 0.3)

        guard inputStream?.streamStatus == .open else {
            scheduleRetry(port: port)
            return
        }

        print("[ScrcpyClient] ✅ Verbonden op poort \(port)")

        DispatchQueue.main.async { [weak self] in
            self?.isConnected = true
            self?.errorMessage = nil
        }

        readMetadataAndStartParsing(port: port)
    }

    // MARK: - Scrcpy v3 Protocol Handshake

    private func readMetadataAndStartParsing(port: UInt16) {
        // Stap 1: Lees 1 dummy byte
        var dummy = [UInt8](repeating: 0, count: 1)
        guard readExact(into: &dummy, count: 1) else {
            print("[ScrcpyClient] ❌ Kan dummy byte niet lezen")
            scheduleRetry(port: port)
            return
        }

        // Stap 2: Lees 64 bytes device naam
        var nameBytes = [UInt8](repeating: 0, count: 64)
        guard readExact(into: &nameBytes, count: 64) else {
            print("[ScrcpyClient] ❌ Kan device naam niet lezen")
            scheduleRetry(port: port)
            return
        }
        let deviceName = String(bytes: nameBytes.prefix(while: { $0 != 0 }), encoding: .utf8) ?? "Unknown"
        print("[ScrcpyClient] 📱 Device: \(deviceName)")

        // Stap 3: Lees 4 bytes codec ID
        var codecBytes = [UInt8](repeating: 0, count: 4)
        guard readExact(into: &codecBytes, count: 4) else {
            print("[ScrcpyClient] ❌ Kan codec niet lezen")
            scheduleRetry(port: port)
            return
        }
        let codecID = String(bytes: codecBytes, encoding: .ascii) ?? "????"
        print("[ScrcpyClient] 🎬 Codec: \(codecID)")

        // Stap 4: Lees breedte (4 bytes, big-endian)
        var widthBytes = [UInt8](repeating: 0, count: 4)
        guard readExact(into: &widthBytes, count: 4) else { return }
        let width = UInt32(bigEndian: widthBytes.withUnsafeBytes { $0.load(as: UInt32.self) })

        // Stap 5: Lees hoogte (4 bytes, big-endian)
        var heightBytes = [UInt8](repeating: 0, count: 4)
        guard readExact(into: &heightBytes, count: 4) else { return }
        let height = UInt32(bigEndian: heightBytes.withUnsafeBytes { $0.load(as: UInt32.self) })

        print("[ScrcpyClient] 📐 Resolutie: \(width)×\(height)")

        DispatchQueue.main.async { [weak self] in
            self?.videoSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        }

        // Start de packet read loop
        readPacketLoop(port: port)
    }

    // MARK: - Packet Loop

    private func readPacketLoop(port: UInt16) {
        while inputStream?.streamStatus == .open {
            // Lees 12-byte header
            var header = [UInt8](repeating: 0, count: 12)
            guard readExact(into: &header, count: 12) else {
                print("[ScrcpyClient] ⚠️ Stream onderbroken")
                break
            }

            // PTS = eerste 8 bytes (big-endian int64, in microseconden)
            // packetSize = laatste 4 bytes (big-endian uint32)
            let packetSize = UInt32(bigEndian: header[8...11].withUnsafeBytes { $0.load(as: UInt32.self) })

            guard packetSize > 0, packetSize < 10_000_000 else {
                print("[ScrcpyClient] ⚠️ Ongeldig packet size: \(packetSize)")
                continue
            }

            // Lees packet data
            var packetData = [UInt8](repeating: 0, count: Int(packetSize))
            guard readExact(into: &packetData, count: Int(packetSize)) else {
                print("[ScrcpyClient] ⚠️ Onvolledig packet")
                break
            }

            processPacket(packetData)
        }

        // Stream gesloten — probeer opnieuw
        scheduleRetry(port: port)
    }

    // MARK: - H.264 Packet verwerken

    private func processPacket(_ data: [UInt8]) {
        let nalUnits = parseNALUnits(from: data)
        guard !nalUnits.isEmpty else { return }

        var avccSlices: [UInt8] = []
        var isKeyframe = false

        for nal in nalUnits {
            let nalType = nal.type

            switch nalType {
            case 7: // SPS
                spsData = nal.data
                print("[ScrcpyClient] 🔑 SPS ontvangen: \(spsData.count) bytes")
                rebuildFormatDescription()

            case 8: // PPS
                ppsData = nal.data
                print("[ScrcpyClient] 🔑 PPS ontvangen: \(ppsData.count) bytes")
                rebuildFormatDescription()

            case 5: // IDR keyframe
                isKeyframe = true
                avccSlices += makeAVCC(from: nal.data)

            case 1: // Non-IDR frame
                avccSlices += makeAVCC(from: nal.data)

            default:
                break
            }
        }

        // Encodeer frame als we slices hebben en een format description
        guard !avccSlices.isEmpty, formatDescription != nil else { return }
        enqueueFrame(avccSlices, isKeyframe: isKeyframe)
    }

    // MARK: - NAL Parser

    private struct NALUnit {
        let type: UInt8
        let data: [UInt8]
    }

    private func parseNALUnits(from packet: [UInt8]) -> [NALUnit] {
        var result: [NALUnit] = []
        var i = 0

        while i < packet.count - 4 {
            // Zoek 4-byte start code: 0x00 0x00 0x00 0x01
            if packet[i] == 0x00 && packet[i+1] == 0x00 && packet[i+2] == 0x00 && packet[i+3] == 0x01 {
                let nalStart = i + 4
                // Zoek het einde van deze NAL unit
                var nalEnd = packet.count
                var j = nalStart
                while j < packet.count - 3 {
                    if packet[j] == 0x00 && packet[j+1] == 0x00 && packet[j+2] == 0x00 && packet[j+3] == 0x01 {
                        nalEnd = j
                        break
                    }
                    // Check ook 3-byte start code
                    if packet[j] == 0x00 && packet[j+1] == 0x00 && packet[j+2] == 0x01 {
                        nalEnd = j
                        break
                    }
                    j += 1
                }

                if nalStart < nalEnd {
                    let nalData = Array(packet[nalStart..<nalEnd])
                    let nalType = nalData[0] & 0x1F
                    result.append(NALUnit(type: nalType, data: nalData))
                }
                i = nalEnd
            } else if packet[i] == 0x00 && packet[i+1] == 0x00 && packet[i+2] == 0x01 {
                // 3-byte start code
                let nalStart = i + 3
                var nalEnd = packet.count
                var j = nalStart
                while j < packet.count - 3 {
                    if (packet[j] == 0x00 && packet[j+1] == 0x00 && packet[j+2] == 0x00 && packet[j+3] == 0x01) ||
                       (packet[j] == 0x00 && packet[j+1] == 0x00 && packet[j+2] == 0x01) {
                        nalEnd = j
                        break
                    }
                    j += 1
                }

                if nalStart < nalEnd {
                    let nalData = Array(packet[nalStart..<nalEnd])
                    let nalType = nalData[0] & 0x1F
                    result.append(NALUnit(type: nalType, data: nalData))
                }
                i = nalEnd
            } else {
                i += 1
            }
        }
        return result
    }

    // MARK: - AVCC conversie (NAL start code → 4-byte length prefix)

    private func makeAVCC(from nalData: [UInt8]) -> [UInt8] {
        let len = nalData.count
        return [
            UInt8((len >> 24) & 0xFF),
            UInt8((len >> 16) & 0xFF),
            UInt8((len >> 8)  & 0xFF),
            UInt8(len & 0xFF)
        ] + nalData
    }

    // MARK: - Format Description

    private func rebuildFormatDescription() {
        guard !spsData.isEmpty, !ppsData.isEmpty else { return }

        // KRITIEK: Gebruik tijdelijke pointers die geldig zijn tijdens de call
        var newFormat: CMVideoFormatDescription?

        let status = spsData.withUnsafeBytes { spsPtr in
            ppsData.withUnsafeBytes { ppsPtr in
                guard let spsBase = spsPtr.baseAddress,
                      let ppsBase = ppsPtr.baseAddress else { return kCMFormatDescriptionError_InvalidParameter }

                let paramSetPointers: [UnsafePointer<UInt8>] = [
                    spsBase.assumingMemoryBound(to: UInt8.self),
                    ppsBase.assumingMemoryBound(to: UInt8.self)
                ]
                let paramSetSizes: [Int] = [spsData.count, ppsData.count]

                return paramSetPointers.withUnsafeBufferPointer { ptrBuf in
                    paramSetSizes.withUnsafeBufferPointer { sizeBuf in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: ptrBuf.baseAddress!,
                            parameterSetSizes: sizeBuf.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &newFormat
                        )
                    }
                }
            }
        }

        if status == noErr, let fmt = newFormat {
            formatDescription = fmt
            print("[ScrcpyClient] ✅ FormatDescription aangemaakt")

            // Herbouw ook de decompression session
            rebuildDecompressionSession(format: fmt)
        } else {
            print("[ScrcpyClient] ❌ FormatDescription mislukt: \(status)")
        }
    }

    // MARK: - VTDecompressionSession

    private func rebuildDecompressionSession(format: CMVideoFormatDescription) {
        // Oude session opruimen
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }

        // KRITIEK: Forceer BGRA output om YUV→RGB kleurruimte problemen te vermijden
        let imageAttrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
        ]

        var callbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: nil, // Niet nodig — we gebruiken direct enqueue
            decompressionOutputRefCon: nil
        )

        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: format,
            decoderSpecification: nil,
            imageBufferAttributes: imageAttrs as CFDictionary,
            outputCallback: &callbackRecord,
            decompressionSessionOut: &session
        )

        if status == noErr {
            decompressionSession = session
            print("[ScrcpyClient] ✅ VTDecompressionSession aangemaakt")
        } else {
            print("[ScrcpyClient] ❌ VTDecompressionSession mislukt: \(status)")
        }
    }

    // MARK: - Frame enqueueing (KRITIEKE FIX)

    private func enqueueFrame(_ avccData: [UInt8], isKeyframe: Bool) {
        guard let formatDesc = formatDescription else { return }

        // ─── FIX 1: Heap-owned copy — GEEN dangling pointer ───
        // Gebruik een NSData als eigenaar van de data zodat ARC het NIET vrijgeeft
        // totdat CoreMedia klaar is.
        let dataCopy = NSMutableData(bytes: avccData, length: avccData.count)

        var blockBuffer: CMBlockBuffer?

        // CMBlockBufferCreateWithMemoryBlock met eigen allocator
        // zodat CoreMedia de lifetime beheert
        let blockStatus = dataCopy.bytes.withMemoryRebound(to: UInt8.self, capacity: avccData.count) { _ in
            // Gebruik een retain trick: maak een custom block source die de NSData vasthoudt
            return createBlockBuffer(owning: dataCopy, blockBufferOut: &blockBuffer)
        }

        guard blockStatus == noErr, let bb = blockBuffer else {
            print("[ScrcpyClient] ❌ CMBlockBuffer fout: \(blockStatus)")
            return
        }

        // ─── Timing: gebruik .invalid voor directe weergave ───
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .invalid,
            decodeTimeStamp: .invalid
        )

        var sampleSize = avccData.count
        var sampleBuffer: CMSampleBuffer?

        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: bb,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleStatus == noErr, let sb = sampleBuffer else {
            print("[ScrcpyClient] ❌ CMSampleBuffer fout: \(sampleStatus)")
            return
        }

        // ─── Attachments via CFDictionary ───
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true) {
            let dict = unsafeBitCast(
                CFArrayGetValueAtIndex(attachments, 0),
                to: CFMutableDictionary.self
            )

            // DisplayImmediately = true
            CFDictionarySetValue(
                dict,
                Unmanaged.passRetained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passRetained(kCFBooleanTrue).toOpaque()
            )

            // DependsOnOthers = false voor keyframes
            if isKeyframe {
                CFDictionarySetValue(
                    dict,
                    Unmanaged.passRetained(kCMSampleAttachmentKey_DependsOnOthers).toOpaque(),
                    Unmanaged.passRetained(kCFBooleanFalse).toOpaque()
                )
            }
        }

        // ─── Push naar mirror view op main thread ───
        DispatchQueue.main.async { [weak self] in
            self?.mirrorView?.enqueue(sb)
        }
    }

    // MARK: - CMBlockBuffer helper (lifetime-safe)

    private func createBlockBuffer(owning data: NSMutableData, blockBufferOut: inout CMBlockBuffer?) -> OSStatus {
        // Gebruik een Unmanaged reference als custom block source
        // zodat de NSData in leven blijft totdat CoreMedia de buffer vrijgeeft
        let dataLength = data.length

        // Custom block source die de NSData retaint
        var customBlockSource = CMBlockBufferCustomBlockSource(
            version: kCMBlockBufferCustomBlockSourceVersion,
            AllocateBlock: nil,
            FreeBlock: { (refcon, doomedMemoryBlock, blockLength) in
                // Release de NSData die we via refcon doorgeven
                guard let refcon = refcon else { return }
                Unmanaged<NSMutableData>.fromOpaque(refcon).release()
            },
            refCon: Unmanaged.passRetained(data).toOpaque()
        )

        return CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: data.mutableBytes,
            blockLength: dataLength,
            blockAllocator: kCFAllocatorNull,  // NULL = wij beheren de lifetime via customBlockSource
            customBlockSource: &customBlockSource,
            offsetToData: 0,
            dataLength: dataLength,
            flags: 0,
            blockBufferOut: &blockBufferOut
        )
    }

    // MARK: - Socket lees helper

    /// Leest exact `count` bytes uit de inputStream, met fragmentatie-ondersteuning
    private func readExact(into buffer: inout [UInt8], count: Int) -> Bool {
        guard count > 0, let stream = inputStream else { return false }

        var totalRead = 0
        while totalRead < count {
            let remaining = count - totalRead
            let chunkSize = min(remaining, 65536)

            let bytesRead = buffer.withUnsafeMutableBytes { ptr in
                stream.read(
                    ptr.baseAddress!.advanced(by: totalRead).assumingMemoryBound(to: UInt8.self),
                    maxLength: chunkSize
                )
            }

            if bytesRead <= 0 {
                if stream.streamStatus != .open { return false }
                Thread.sleep(forTimeInterval: 0.001) // kort wachten bij leeg buffer
                continue
            }
            totalRead += bytesRead
        }
        return true
    }

    // MARK: - Retry logica

    private func scheduleRetry(port: UInt16) {
        guard retryCount < maxRetries else {
            DispatchQueue.main.async { [weak self] in
                self?.isConnected = false
                self?.errorMessage = "Kan geen verbinding maken na \(self?.maxRetries ?? 5) pogingen. Controleer USB-verbinding."
            }
            return
        }

        retryCount += 1
        print("[ScrcpyClient] 🔄 Retry \(retryCount)/\(maxRetries) over 2 seconden...")

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            self.sessionQueue.async {
                self.openStreams(port: port)
            }
        }
    }
}
