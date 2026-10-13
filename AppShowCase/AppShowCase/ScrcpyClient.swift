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
    private var formatDescription: CMVideoFormatDescription?

    private var spsData: [UInt8] = []
    private var ppsData: [UInt8] = []
    
    // Frame grouping state
    private var pendingFrameSlices: [UInt8] = []
    private var pendingIsKeyframe = false
    private var pendingHasVCL = false

    private var frameCount: Int64 = 0
    private var streamBuffer = [UInt8]()

    private let sessionQueue = DispatchQueue(label: "com.appshowcase.scrcpy", qos: .default)

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

        // Wacht iets langer (1 seconde) zodat de TCP verbinding en app_process tot stand komt
        Thread.sleep(forTimeInterval: 1.0)

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

    // MARK: - Annex B Continuous Stream Parser

    private func readMetadataAndStartParsing(port: UInt16) {
        print("[ScrcpyClient] ⏳ Wachten op inkomende videostream (Raw H.264 Annex B)...")
        
        DispatchQueue.main.async { [weak self] in
            // Gebruik een fallback resolutie. De decoder (SPS) zal later de echte resolutie ontdekken.
            self?.videoSize = CGSize(width: 1080, height: 1920)
        }

        var attempts = 0
        while attempts < 150 && inputStream?.hasBytesAvailable == false {
            Thread.sleep(forTimeInterval: 0.1)
            attempts += 1
        }
        
        guard inputStream?.hasBytesAvailable == true else {
            print("[ScrcpyClient] ❌ Geen inkomende frames gedetecteerd na wachtpogingen (\(attempts/10)s)")
            scheduleRetry(port: port)
            return
        }

        // Start direct de packet read loop (pure Annex B parser)
        readPacketLoop(port: port)
    }

    private func readPacketLoop(port: UInt16) {
        let bufferSize = 65536
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while inputStream?.streamStatus == .open {
            let bytesRead = inputStream?.read(&buffer, maxLength: bufferSize) ?? -1
            if bytesRead <= 0 {
                print("[ScrcpyClient] ⚠️ Stream onderbroken of EOF")
                break
            }

            streamBuffer.append(contentsOf: buffer.prefix(bytesRead))
            extractNALUnitsFromBuffer()
        }

        // Stream gesloten — probeer opnieuw
        scheduleRetry(port: port)
    }

    private func extractNALUnitsFromBuffer() {
        while true {
            guard let firstStart = findStartCode(in: streamBuffer, from: 0) else {
                return // Geen start code gevonden, wacht op meer bytes in the socket buffer
            }
            
            let searchStart = firstStart.index + firstStart.length
            guard let nextStart = findStartCode(in: streamBuffer, from: searchStart) else {
                return // Geen uiteinde gevonden voor deze NAL unit, wacht op meer bytes
            }
            
            // We hebben een complete NAL unit gelokaliseerd!
            let nalData = Array(streamBuffer[searchStart..<nextStart.index])
            if !nalData.isEmpty {
                processPacket(nalData)
            }
            
            // Verwijder verwerkte bytes the ringbuffer in (tot het begin van de NAL start code)
            streamBuffer.removeFirst(nextStart.index)
        }
    }

    private func findStartCode(in data: [UInt8], from startIndex: Int) -> (index: Int, length: Int)? {
        guard startIndex + 2 < data.count else { return nil }
        for i in startIndex..<(data.count - 2) {
            if data[i] == 0 && data[i+1] == 0 {
                if data[i+2] == 1 {
                    return (i, 3)
                } else if i + 3 < data.count && data[i+2] == 0 && data[i+3] == 1 {
                    return (i, 4)
                }
            }
        }
        return nil
    }

    // MARK: - H.264 Packet verwerken

    private func flushPendingFrame() {
        let slices = pendingFrameSlices
        let isKey = pendingIsKeyframe
        
        // Reset state
        pendingFrameSlices.removeAll(keepingCapacity: true)
        pendingIsKeyframe = false
        pendingHasVCL = false
        
        guard !slices.isEmpty, formatDescription != nil else { return }
        enqueueFrame(slices, isKeyframe: isKey)
    }

    private func processPacket(_ nalData: [UInt8]) {
        guard !nalData.isEmpty else { return }

        let nalType = nalData[0] & 0x1F

        switch nalType {
        case 7: // SPS
            flushPendingFrame()
            spsData = nalData
            print("[ScrcpyClient] 🔑 SPS ontvangen: \(spsData.count) bytes")
            rebuildFormatDescription()

        case 8: // PPS
            ppsData = nalData
            print("[ScrcpyClient] 🔑 PPS ontvangen: \(ppsData.count) bytes")
            rebuildFormatDescription()

        case 9: // AUD (Access Unit Delimiter)
            flushPendingFrame()

        case 6: // SEI (Supplemental Enhancement Information)
            if pendingHasVCL {
                flushPendingFrame()
            }
            pendingFrameSlices += makeAVCC(from: nalData)

        case 5: // IDR keyframe
            if pendingHasVCL {
                flushPendingFrame()
            }
            pendingIsKeyframe = true
            pendingHasVCL = true
            pendingFrameSlices += makeAVCC(from: nalData)

        case 1: // Non-IDR frame
            if pendingHasVCL {
                flushPendingFrame()
            }
            pendingHasVCL = true
            pendingFrameSlices += makeAVCC(from: nalData)

        default:
            // Genegeerde NAL types (bijv. padding, v1 metadata als die stiekem langskomen)
            break
        }
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
        } else {
            print("[ScrcpyClient] ❌ FormatDescription mislukt: \(status)")
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

        // ─── Timing: valid PTS voor renderer ───
        frameCount += 1
        let ptsTime = CMTime(value: frameCount, timescale: 60)
        
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: ptsTime,
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
            let displayKey = unsafeBitCast(kCMSampleAttachmentKey_DisplayImmediately, to: UnsafeRawPointer.self)
            let displayValue = unsafeBitCast(kCFBooleanTrue, to: UnsafeRawPointer.self)
            CFDictionarySetValue(dict, displayKey, displayValue)

            // DependsOnOthers = false voor keyframes
            if isKeyframe {
                let dependsKey = unsafeBitCast(kCMSampleAttachmentKey_DependsOnOthers, to: UnsafeRawPointer.self)
                let dependsValue = unsafeBitCast(kCFBooleanFalse, to: UnsafeRawPointer.self)
                CFDictionarySetValue(dict, dependsKey, dependsValue)
            } else {
                let notSyncKey = unsafeBitCast(kCMSampleAttachmentKey_NotSync, to: UnsafeRawPointer.self)
                let notSyncValue = unsafeBitCast(kCFBooleanTrue, to: UnsafeRawPointer.self)
                CFDictionarySetValue(dict, notSyncKey, notSyncValue)
            }
        }

        // Log vóór the main thread dispatch zodat we in elk geval IETS in console zien als hij hangt!
        print("[ScrcpyClient] 🎞️ Frame klaar voor main thread: \(avccData.count) bytes (keyframe: \(isKeyframe))")

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
