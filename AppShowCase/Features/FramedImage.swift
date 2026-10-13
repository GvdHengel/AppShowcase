import AppKit
import CoreImage
import SwiftUI

/// Omzetten van pixelbuffers naar Core Image / CGImage, met alleen het zichtbare deel.
enum PixelBufferConverter {
    /// Gedeelde Core Image-context (thread-safe, GPU).
    static let context = CIContext(options: [.cacheIntermediates: false])

    /// Het zichtbare deel van een frame als CIImage met oorsprong (0,0).
    static func visibleImage(_ pixelBuffer: CVPixelBuffer) -> CIImage {
        let full = CIImage(cvPixelBuffer: pixelBuffer)
        let crop = visibleRect(bufferSize: full.extent.size, cleanSize: CVImageBufferGetCleanRect(pixelBuffer).size)
        return full
            .cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
    }

    /// H.264 snijdt opvulling rechts en onder af; in Core Image ligt (0,0) linksonder.
    static func visibleRect(bufferSize: CGSize, cleanSize: CGSize) -> CGRect {
        guard cleanSize.width > 0, cleanSize.height > 0,
              cleanSize.width <= bufferSize.width, cleanSize.height <= bufferSize.height
        else { return CGRect(origin: .zero, size: bufferSize) }
        return CGRect(x: 0, y: bufferSize.height - cleanSize.height, width: cleanSize.width, height: cleanSize.height)
    }

    static func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let image = visibleImage(pixelBuffer)
        return context.createCGImage(image, from: image.extent)
    }
}

/// Een uitvoerbeeld met toestelframe: maat, marge en waar het scherm precies ligt.
struct FramedCanvas: Equatable {
    let outputSize: CGSize
    let padding: CGFloat
    let layout: FrameLayout

    init(style: DeviceFrameStyle, screenSize: CGSize, outputSize: CGSize, padding: CGFloat) {
        self.outputSize = outputSize
        self.padding = padding
        layout = FrameLayout(
            style: style,
            screenSize: screenSize,
            fitting: CGSize(width: outputSize.width - 2 * padding, height: outputSize.height - 2 * padding)
        )
    }

    /// Linkerbovenhoek van het toestel (zoals `DeviceFrameView` het centreert).
    var deviceOrigin: CGPoint {
        CGPoint(
            x: padding + (outputSize.width - 2 * padding - layout.displaySize.width) / 2,
            y: padding + (outputSize.height - 2 * padding - layout.displaySize.height) / 2
        )
    }

    /// Plek van het videobeeld in het uitvoerbeeld (oorsprong linksboven).
    var screenRect: CGRect {
        layout.displayScreenRect.offsetBy(dx: deviceOrigin.x, dy: deviceOrigin.y)
    }

    /// Uitvoermaat waarbij het scherm op ware pixelgrootte staat, plus marge.
    /// Te grote beelden worden geschaald tot `maxLongSide`; maten zijn even (vereist voor H.264).
    static func naturalOutputSize(style: DeviceFrameStyle, screenSize: CGSize,
                                  paddingFraction: CGFloat, maxLongSide: CGFloat) -> (size: CGSize, padding: CGFloat) {
        let probe = FrameLayout(style: style, screenSize: screenSize, fitting: CGSize(width: 100_000, height: 100_000))
        guard probe.scale > 0 else { return (CGSize(width: 2, height: 2), 0) }
        let factor = min(screenSize.width, screenSize.height) / probe.scale
        let device = CGSize(width: probe.displaySize.width * factor, height: probe.displaySize.height * factor)
        var padding = paddingFraction * min(device.width, device.height)
        var total = CGSize(width: device.width + 2 * padding, height: device.height + 2 * padding)

        let longSide = max(total.width, total.height)
        if longSide > maxLongSide {
            let shrink = maxLongSide / longSide
            total = CGSize(width: total.width * shrink, height: total.height * shrink)
            padding *= shrink
        }
        let even = { (value: CGFloat) -> CGFloat in max(2, (value / 2).rounded(.down) * 2) }
        return (CGSize(width: even(total.width), height: even(total.height)), padding)
    }
}

/// Rendert (delen van) een toestelframe naar een CGImage.
@MainActor
enum FramedImageRenderer {
    static func render<Screen: View>(canvas: FramedCanvas,
                                     style: DeviceFrameStyle,
                                     screenSize: CGSize,
                                     background: Color,
                                     parts: DeviceFrameParts,
                                     screen: Screen) -> CGImage? {
        let view = ZStack {
            background
            DeviceFrameView(style: style, screenSize: screenSize, parts: parts) { screen }
                .padding(canvas.padding)
        }
        .frame(width: canvas.outputSize.width, height: canvas.outputSize.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.cgImage
    }
}

/// Mappen voor schermafbeeldingen en opnames, met leesbare bestandsnamen.
enum OutputFolders {
    static func fileURL(in directory: FileManager.SearchPathDirectory, fileName: String) throws -> URL {
        guard let base = FileManager.default.urls(for: directory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let folder = base.appendingPathComponent("AppShowCase", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }

    /// Bijv. "2026-10-13 om 19.05.12".
    static func timestamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "yyyy-MM-dd 'om' HH.mm.ss"
        return formatter.string(from: date)
    }

    /// Haalt tekens weg die niet in een bestandsnaam horen.
    static func safeName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Toestel" : cleaned
    }
}
