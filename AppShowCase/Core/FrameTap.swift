import CoreMedia
import CoreVideo
import Foundation

/// Tapt frames af van een `MirrorSession`: bewaart het laatste frame (voor schermafbeeldingen)
/// en geeft frames door aan een optionele afnemer (bijv. de opname).
///
/// Thread-safe: frames komen binnen op de queue van de beeldbron.
final class FrameTap: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var consumer: (@Sendable (CVPixelBuffer) -> Void)?

    func receive(_ sampleBuffer: CMSampleBuffer) {
        guard let image = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let currentConsumer = lock.withLock { () -> (@Sendable (CVPixelBuffer) -> Void)? in
            latest = image
            return consumer
        }
        currentConsumer?(image)
    }

    /// Het laatst getoonde frame, of `nil` als er nog geen beeld is.
    var latestPixelBuffer: CVPixelBuffer? {
        lock.withLock { latest }
    }

    func setConsumer(_ newConsumer: (@Sendable (CVPixelBuffer) -> Void)?) {
        lock.withLock { consumer = newConsumer }
    }

    func clear() {
        lock.withLock {
            latest = nil
            consumer = nil
        }
    }
}
