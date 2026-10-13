import Foundation

/// Sleutels voor app-brede instellingen in UserDefaults (ook gebruikt met `@AppStorage`).
enum AppSettingsKey {
    static let autoOpenWindows = "autoOpenWindows"
    static let copyScreenshotToClipboard = "copyScreenshotToClipboard"
    static let androidQuality = "androidQuality"
}

/// Beeldkwaliteit van de Android-stream (bitrate en framerate voor scrcpy-server).
enum AndroidQuality: String, CaseIterable, Identifiable, Sendable {
    case high
    case normal
    case low

    var id: String { rawValue }

    var name: String {
        switch self {
        case .high: return "Hoog (16 Mbit/s, 60 fps)"
        case .normal: return "Normaal (8 Mbit/s, 60 fps)"
        case .low: return "Laag (4 Mbit/s, 30 fps) — voor oudere toestellen of kabels"
        }
    }

    var bitRate: Int {
        switch self {
        case .high: return 16_000_000
        case .normal: return 8_000_000
        case .low: return 4_000_000
        }
    }

    var maxFPS: Int {
        switch self {
        case .high, .normal: return 60
        case .low: return 30
        }
    }

    /// De huidige keuze uit de instellingen (standaard: normaal).
    static func current(_ defaults: UserDefaults = .standard) -> AndroidQuality {
        defaults.string(forKey: AppSettingsKey.androidQuality).flatMap(AndroidQuality.init(rawValue:)) ?? .normal
    }
}
