import AVFoundation
import CoreImage
import SwiftUI

enum RecorderError: LocalizedError {
    case cannotRecord
    case noFrames
    case noImage

    var errorDescription: String? {
        switch self {
        case .cannotRecord: return "De opname kon niet gestart of afgerond worden."
        case .noFrames: return "Er zijn geen beelden opgenomen."
        case .noImage: return "Er is nog geen beeld om op te nemen."
        }
    }
}

/// Neemt het live beeld op mét toestelframe, als H.264 `.mov`.
///
/// Per frame wordt met Core Image samengesteld: achtergrond + behuizing (vooraf gerenderd),
/// het videobeeld in de schermrechthoek met afgeronde hoeken, en notch/eiland erover.
/// Draait het toestel tijdens de opname, dan worden de lagen opnieuw gerenderd (in dezelfde uitvoermaat).
final class FramedRecorder: @unchecked Sendable {
    /// Vooraf gerenderde lagen voor één schermmaat (in Core Image-coördinaten, oorsprong linksonder).
    struct Layers: @unchecked Sendable {
        let screenSize: CGSize
        let under: CIImage
        let over: CIImage?
        let mask: CIImage
        let screenRect: CGRect
    }

    let url: URL
    let outputSize: CGSize

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let makeLayers: @MainActor (CGSize) -> Layers?
    private let queue = DispatchQueue(label: "nl.gvdhengel.AppShowCase.recorder", qos: .userInitiated)
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    // Alleen op `queue`.
    private var layers: Layers?
    private var requestedSize: CGSize?
    private var started = false

    // Onder `lock`.
    private let lock = NSLock()
    private var busy = false
    private var finished = false

    init(url: URL, outputSize: CGSize, initialLayers: Layers, makeLayers: @escaping @MainActor (CGSize) -> Layers?) throws {
        self.url = url
        self.outputSize = outputSize
        self.makeLayers = makeLayers
        layers = initialLayers

        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 12_000_000,
                AVVideoExpectedSourceFrameRateKey: 60,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(outputSize.width),
            kCVPixelBufferHeightKey as String: Int(outputSize.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        guard writer.canAdd(input) else { throw RecorderError.cannotRecord }
        writer.add(input)
    }

    /// Vanaf elke thread aan te roepen. Als het vorige frame nog verwerkt wordt, wordt dit frame overgeslagen.
    func append(_ pixelBuffer: CVPixelBuffer) {
        let skip = lock.withLock { () -> Bool in
            if busy || finished { return true }
            busy = true
            return false
        }
        guard !skip else { return }
        queue.async { [self] in
            process(pixelBuffer)
            lock.withLock { busy = false }
        }
    }

    func finish(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        lock.withLock { finished = true }
        queue.async { [self] in
            guard started else {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: url)
                completion(.failure(RecorderError.noFrames))
                return
            }
            input.markAsFinished()
            writer.finishWriting { [self] in
                if writer.status == .completed {
                    completion(.success(url))
                } else {
                    completion(.failure(writer.error ?? RecorderError.cannotRecord))
                }
            }
        }
    }

    // MARK: - Per frame (op queue)

    private func process(_ pixelBuffer: CVPixelBuffer) {
        guard !lock.withLock({ finished }) else { return }

        let video = PixelBufferConverter.visibleImage(pixelBuffer)
        let size = video.extent.size

        guard let layers, layers.screenSize == size else {
            requestLayers(for: size)
            return
        }

        let now = CMClockGetTime(CMClockGetHostTimeClock())
        if !started {
            guard writer.startWriting() else {
                print("[FramedRecorder] starten mislukt: \(writer.error?.localizedDescription ?? "?")")
                lock.withLock { finished = true }
                return
            }
            writer.startSession(atSourceTime: now)
            started = true
        }

        guard input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else { return }
        var output: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &output)
        guard let output else { return }

        let rect = layers.screenRect
        let placed = video
            .transformed(by: CGAffineTransform(scaleX: rect.width / size.width, y: rect.height / size.height))
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
        var composed = placed.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: layers.under,
            kCIInputMaskImageKey: layers.mask,
        ])
        if let over = layers.over {
            composed = over.composited(over: composed)
        }

        PixelBufferConverter.context.render(
            composed, to: output,
            bounds: CGRect(origin: .zero, size: outputSize),
            colorSpace: colorSpace
        )
        adaptor.append(output, withPresentationTime: now)
    }

    /// Nieuwe schermmaat (bijv. toestel gedraaid): lagen op de main thread opnieuw renderen.
    private func requestLayers(for size: CGSize) {
        guard requestedSize != size else { return }
        requestedSize = size
        let make = makeLayers
        DispatchQueue.main.async { [weak self] in
            let newLayers = MainActor.assumeIsolated { make(size) }
            self?.queue.async { self?.layers = newLayers }
        }
    }
}

/// Rendert de vaste lagen voor de opname.
@MainActor
enum RecordingLayers {
    static func make(style: DeviceFrameStyle, background: Color, outputSize: CGSize,
                     padding: CGFloat, screenSize: CGSize) -> FramedRecorder.Layers? {
        let canvas = FramedCanvas(style: style, screenSize: screenSize, outputSize: outputSize, padding: padding)

        guard let under = FramedImageRenderer.render(
            canvas: canvas, style: style, screenSize: screenSize,
            background: background, parts: [.body], screen: Color.black
        ) else { return nil }

        var over: CIImage?
        if style.cutout != .none,
           let cutout = FramedImageRenderer.render(
               canvas: canvas, style: style, screenSize: screenSize,
               background: .clear, parts: [.cutout], screen: Color.clear
           ) {
            over = CIImage(cgImage: cutout)
        }

        let topLeftRect = canvas.screenRect
        let ciRect = CGRect(x: topLeftRect.minX, y: outputSize.height - topLeftRect.maxY,
                            width: topLeftRect.width, height: topLeftRect.height)
        guard let mask = maskImage(size: outputSize, rect: ciRect, radius: canvas.layout.screenCornerRadius) else {
            return nil
        }

        return FramedRecorder.Layers(
            screenSize: screenSize,
            under: CIImage(cgImage: under),
            over: over,
            mask: mask,
            screenRect: ciRect
        )
    }

    /// Wit afgerond scherm op zwart: bepaalt waar het videobeeld zichtbaar is.
    private static func maskImage(size: CGSize, rect: CGRect, radius: CGFloat) -> CIImage? {
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(gray: 1, alpha: 1)
        let safeRadius = max(0, min(radius, rect.width / 2 - 0.01, rect.height / 2 - 0.01))
        context.addPath(CGPath(roundedRect: rect, cornerWidth: safeRadius, cornerHeight: safeRadius, transform: nil))
        context.fillPath()
        return context.makeImage().map { CIImage(cgImage: $0) }
    }
}
