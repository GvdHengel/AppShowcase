import AppKit
import SwiftUI

enum ScreenshotError: LocalizedError {
    case noImage
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .noImage: return "Er is nog geen beeld om vast te leggen."
        case .renderFailed: return "De schermafbeelding kon niet gemaakt worden."
        }
    }
}

/// Maakt een schermafbeelding mét toestelframe, bewaart die als PNG en zet hem op het klembord.
@MainActor
enum ScreenshotService {
    /// - Returns: de locatie van het PNG-bestand in `~/Pictures/AppShowCase`.
    static func capture(pixelBuffer: CVPixelBuffer,
                        style: DeviceFrameStyle,
                        background: WindowBackground,
                        deviceName: String) throws -> URL {
        guard let screenImage = PixelBufferConverter.cgImage(from: pixelBuffer) else {
            throw ScreenshotError.noImage
        }
        let screenSize = CGSize(width: screenImage.width, height: screenImage.height)
        let natural = FramedCanvas.naturalOutputSize(style: style, screenSize: screenSize,
                                                     paddingFraction: 0.06, maxLongSide: 4000)
        let canvas = FramedCanvas(style: style, screenSize: screenSize, outputSize: natural.size, padding: natural.padding)

        guard let framed = FramedImageRenderer.render(
            canvas: canvas,
            style: style,
            screenSize: screenSize,
            background: background.color, // transparant blijft transparant in de PNG
            parts: .all,
            screen: Image(decorative: screenImage, scale: 1).resizable()
        ),
            let png = NSBitmapImageRep(cgImage: framed).representation(using: .png, properties: [:])
        else { throw ScreenshotError.renderFailed }

        let name = "\(OutputFolders.safeName(deviceName)) \(OutputFolders.timestamp()).png"
        let url = try OutputFolders.fileURL(in: .picturesDirectory, fileName: name)
        try png.write(to: url)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        return url
    }
}
