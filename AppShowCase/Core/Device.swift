import Foundation

/// Het platform van een aangesloten toestel.
enum Platform: String, Codable, Hashable, CaseIterable, Sendable {
    case iOS
    case android

    var displayName: String {
        switch self {
        case .iOS: return "iOS"
        case .android: return "Android"
        }
    }

    /// SF Symbol voor lijsten en menu's.
    var symbolName: String {
        switch self {
        case .iOS: return "iphone"
        case .android: return "smartphone"
        }
    }
}

/// Unieke, stabiele sleutel voor een toestel.
/// - iOS: `AVCaptureDevice.uniqueID`
/// - Android: ADB-serienummer
///
/// Codable zodat SwiftUI er per toestel een eigen venster mee kan openen
/// (`WindowGroup(for: DeviceID.self)`) en vensters na herstart herstelt.
struct DeviceID: Hashable, Codable, Sendable, CustomStringConvertible {
    let platform: Platform
    let rawID: String

    var description: String { "\(platform.rawValue):\(rawID)" }
}

/// Wat de app over een aangesloten toestel weet.
struct DeviceInfo: Identifiable, Hashable, Sendable {
    let id: DeviceID
    /// Naam zoals getoond aan de gebruiker, bijv. "iPhone van Gerbrant" of "Pixel 2".
    var name: String
    /// Modelaanduiding indien bekend, bijv. "iPhone11,2" of "Pixel 2".
    var model: String?

    var platform: Platform { id.platform }
}
