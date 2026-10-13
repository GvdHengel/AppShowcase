import CoreMedia
import CoreVideo
import VideoToolbox

/// Hulpfuncties voor H.264 Annex B (start codes) ↔ AVCC (lengte-prefix).
enum AnnexB {
    /// Splitst Annex B-data in NAL-units (zonder start codes). Ondersteunt 3- en 4-byte start codes.
    static func split(_ bytes: [UInt8]) -> [ArraySlice<UInt8>] {
        var starts: [(codeStart: Int, nalStart: Int)] = []
        var index = 0
        let count = bytes.count
        while index + 2 < count {
            if bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 1 {
                let codeStart = (index > 0 && bytes[index - 1] == 0) ? index - 1 : index
                starts.append((codeStart, index + 3))
                index += 3
            } else {
                index += 1
            }
        }

        var units: [ArraySlice<UInt8>] = []
        for (position, start) in starts.enumerated() {
            let end = position + 1 < starts.count ? starts[position + 1].codeStart : count
            if end > start.nalStart {
                units.append(bytes[start.nalStart..<end])
            }
        }
        return units
    }

    /// Zet NAL-units om naar AVCC: elke unit krijgt een 4-byte big-endian lengte ervoor.
    static func toAVCC(_ units: [ArraySlice<UInt8>]) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(units.reduce(0) { $0 + $1.count + 4 })
        for unit in units {
            let length = UInt32(unit.count)
            output.append(UInt8(truncatingIfNeeded: length >> 24))
            output.append(UInt8(truncatingIfNeeded: length >> 16))
            output.append(UInt8(truncatingIfNeeded: length >> 8))
            output.append(UInt8(truncatingIfNeeded: length))
            output.append(contentsOf: unit)
        }
        return output
    }

    static func nalType(_ unit: ArraySlice<UInt8>) -> UInt8? {
        unit.first.map { $0 & 0x1F }
    }
}

/// Decodeert scrcpy-pakketten (H.264) met VideoToolbox (hardware) naar BGRA-pixelbuffers.
///
/// Niet thread-safe: roep `decode` steeds vanaf dezelfde seriële queue aan.
/// Gedecodeerde frames worden op `deliveryQueue` afgeleverd.
final class H264Decoder {
    /// Gedecodeerd frame (klaar voor `AVSampleBufferDisplayLayer`) plus zichtbare afmetingen.
    var onFrame: ((CMSampleBuffer, CGSize) -> Void)?

    private let deliveryQueue: DispatchQueue
    private var sps: [UInt8]?
    private var pps: [UInt8]?
    private var formatDescription: CMVideoFormatDescription?
    private var session: VTDecompressionSession?

    init(deliveryQueue: DispatchQueue) {
        self.deliveryQueue = deliveryQueue
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        formatDescription = nil
    }

    func decode(_ packet: ScrcpyPacket) {
        var frameUnits: [ArraySlice<UInt8>] = []
        var parametersChanged = false

        for unit in AnnexB.split(packet.payload) {
            switch AnnexB.nalType(unit) {
            case 7?: // SPS — verandert o.a. bij draaien van het toestel (nieuwe resolutie)
                let value = Array(unit)
                if value != sps { sps = value; parametersChanged = true }
            case 8?: // PPS
                let value = Array(unit)
                if value != pps { pps = value; parametersChanged = true }
            case 9?: // Access Unit Delimiter: niet nodig
                continue
            default:
                frameUnits.append(unit)
            }
        }

        if parametersChanged || session == nil {
            rebuildSession()
        }

        guard !packet.isConfig, !frameUnits.isEmpty,
              let session, let formatDescription,
              let sample = Self.makeSampleBuffer(avcc: AnnexB.toAVCC(frameUnits), format: formatDescription, pts: packet.pts)
        else { return }

        let status = VTDecompressionSessionDecodeFrame(
            session, sampleBuffer: sample, flags: [], infoFlagsOut: nil
        ) { [weak self] status, _, imageBuffer, _, _ in
            guard status == noErr, let imageBuffer else { return }
            self?.deliver(imageBuffer)
        }

        if status == kVTInvalidSessionErr {
            // Gebeurt o.a. na slaapstand van de Mac; opnieuw opbouwen herstelt het.
            rebuildSession()
        } else if status != noErr {
            print("[H264Decoder] decode-fout \(status)")
        }
    }

    // MARK: - Intern

    private func rebuildSession() {
        guard let sps, let pps else { return }
        invalidate()

        var newFormat: CMVideoFormatDescription?
        let formatStatus = sps.withUnsafeBufferPointer { spsBuffer in
            pps.withUnsafeBufferPointer { ppsBuffer in
                let pointers: [UnsafePointer<UInt8>] = [spsBuffer.baseAddress!, ppsBuffer.baseAddress!]
                let sizes: [Int] = [spsBuffer.count, ppsBuffer.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: pointers,
                    parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &newFormat
                )
            }
        }
        guard formatStatus == noErr, let newFormat else {
            print("[H264Decoder] format description mislukt: \(formatStatus)")
            return
        }

        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [String: Any](),
        ]
        var newSession: VTDecompressionSession?
        let sessionStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: newFormat,
            decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &newSession
        )
        guard sessionStatus == noErr, let newSession else {
            print("[H264Decoder] decoder aanmaken mislukt: \(sessionStatus)")
            return
        }
        VTSessionSetProperty(newSession, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)

        formatDescription = newFormat
        session = newSession
        let dimensions = CMVideoFormatDescriptionGetDimensions(newFormat)
        print("[H264Decoder] decoder klaar: \(dimensions.width)×\(dimensions.height)")
    }

    private static func makeSampleBuffer(avcc: [UInt8], format: CMVideoFormatDescription, pts: UInt64) -> CMSampleBuffer? {
        var blockBuffer: CMBlockBuffer?
        // CoreMedia beheert zelf het geheugen (geen dangling pointers zoals in het prototype).
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: avcc.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avcc.count,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        ) == kCMBlockBufferNoErr, let blockBuffer else { return nil }

        let copyStatus = avcc.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(
                with: raw.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: avcc.count
            )
        }
        guard copyStatus == kCMBlockBufferNoErr else { return nil }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: CMTimeValue(pts), timescale: 1_000_000),
            decodeTimeStamp: .invalid
        )
        var sampleSize = avcc.count
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        ) == noErr else { return nil }
        return sampleBuffer
    }

    /// Verpakt een gedecodeerde pixelbuffer als sample buffer die direct getoond wordt.
    private func deliver(_ imageBuffer: CVImageBuffer) {
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: imageBuffer, formatDescriptionOut: &format
        ) == noErr, let format else { return }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: imageBuffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else { return }

        SampleBufferTools.markDisplayImmediately(sampleBuffer)
        let size = CVImageBufferGetCleanRect(imageBuffer).size

        deliveryQueue.async { [weak self] in
            self?.onFrame?(sampleBuffer, size)
        }
    }
}
