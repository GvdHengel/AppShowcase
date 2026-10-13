import CoreMedia
import Foundation

/// Gebeurtenissen die een beeldbron meldt (op een willekeurige queue).
enum SourceEvent: Sendable, Equatable {
    /// De bron is gestart; frames kunnen nu binnenkomen.
    case started
    /// De afmetingen van het beeld zijn (voor het eerst of na draaien) bekend/veranderd.
    case videoSizeChanged(CGSize)
    /// Er ging iets mis; de tekst is bedoeld voor de gebruiker.
    case failed(String)
}

/// Gemeenschappelijke interface voor iOS- en Android-beeldbronnen.
///
/// Elke bron levert `CMSampleBuffer`s met een gedecodeerde `CVImageBuffer`.
/// Weergave, toestelframe, screenshot en opname werken daardoor voor beide platforms hetzelfde.
protocol FrameSource: AnyObject {
    /// Wordt per frame aangeroepen, op een achtergrond-queue van de bron.
    var frameHandler: (@Sendable (CMSampleBuffer) -> Void)? { get set }
    /// Wordt aangeroepen bij statuswijzigingen, op een willekeurige queue.
    var eventHandler: (@Sendable (SourceEvent) -> Void)? { get set }

    func start()
    func stop()
}

enum SampleBufferTools {
    /// Laat `AVSampleBufferDisplayLayer` het frame direct tonen, zonder op tijdstempels te wachten.
    static func markDisplayImmediately(_ sampleBuffer: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
              CFArrayGetCount(attachments) > 0 else { return }
        let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(
            dictionary,
            Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue!).toOpaque()
        )
    }
}
