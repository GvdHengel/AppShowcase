import SwiftUI

/// Beschrijving van een (generiek) toestelframe.
///
/// Alle maten zijn **fracties van de schermbreedte in staande stand**, zodat het frame op elke
/// venstergrootte klopt. Knopposities zijn fracties van de hoogte van de behuizing.
/// De frames zijn eigen, generieke tekeningen (geen logo's of merkkenmerken), zodat ze in de repo mogen.
struct DeviceFrameStyle: Identifiable, Equatable, Sendable {
    enum Cutout: Equatable, Sendable {
        case none
        /// Inkeping aan de bovenrand van het scherm (iPhone X t/m 14).
        case notch(width: CGFloat, height: CGFloat, cornerRadius: CGFloat)
        /// Pilvormig eiland, los van de rand (iPhone 14 Pro en nieuwer).
        case island(width: CGFloat, height: CGFloat, topInset: CGFloat)
        /// Rond camera-gaatje (moderne Android-toestellen).
        case punchHole(diameter: CGFloat, topInset: CGFloat)
    }

    enum Decoration: Equatable, Sendable {
        /// Luidsprekersleuf, gecentreerd in de bovenrand.
        case topSpeaker(width: CGFloat)
        /// Luidsprekersleuf, gecentreerd in de onderrand.
        case bottomSpeaker(width: CGFloat)
        /// Frontcamera in de bovenrand; `x` als fractie van de breedte van de behuizing.
        case topCamera(diameter: CGFloat, x: CGFloat)
        /// Ronde thuisknop, gecentreerd in de onderrand.
        case homeButton(diameter: CGFloat)
    }

    struct SideButton: Equatable, Sendable {
        enum Side: Sendable { case left, right }
        let side: Side
        /// Bovenkant van de knop als fractie van de hoogte van de behuizing.
        let position: CGFloat
        let length: CGFloat
    }

    let id: String
    let name: String
    /// Platform waarvoor dit frame bedoeld is; `nil` = beide.
    let platform: Platform?
    let sideBezel: CGFloat
    let topBezel: CGFloat
    let bottomBezel: CGFloat
    let screenCornerRadius: CGFloat
    let bodyCornerRadius: CGFloat
    let cutout: Cutout
    let decorations: [Decoration]
    let buttons: [SideButton]
    let bodyColor: Color
    let rimColor: Color

    /// "Geen frame" tekent alleen het beeld.
    var drawsBody: Bool { id != DeviceFrameStyle.none.id }
}

// MARK: - Catalogus

extension DeviceFrameStyle {
    /// Waarde in de instellingen voor "kies automatisch".
    static let automaticID = "auto"

    private static let graphite = Color(white: 0.09)
    private static let titanium = Color(white: 0.42)
    private static let darkRim = Color(white: 0.20)

    /// iPhone met inkeping, zoals iPhone X / Xs / 11 Pro.
    static let iPhoneNotch = DeviceFrameStyle(
        id: "iphone-notch",
        name: "iPhone met notch",
        platform: .iOS,
        sideBezel: 0.045, topBezel: 0.045, bottomBezel: 0.045,
        screenCornerRadius: 0.105, bodyCornerRadius: 0.15,
        cutout: .notch(width: 0.56, height: 0.082, cornerRadius: 0.05),
        decorations: [],
        buttons: [
            .init(side: .left, position: 0.14, length: 0.05),
            .init(side: .left, position: 0.22, length: 0.09),
            .init(side: .left, position: 0.33, length: 0.09),
            .init(side: .right, position: 0.26, length: 0.14),
        ],
        bodyColor: graphite,
        rimColor: titanium
    )

    /// iPhone met eiland, zoals iPhone 15 / 16 Pro.
    static let iPhoneIsland = DeviceFrameStyle(
        id: "iphone-island",
        name: "iPhone met eiland",
        platform: .iOS,
        sideBezel: 0.034, topBezel: 0.034, bottomBezel: 0.034,
        screenCornerRadius: 0.14, bodyCornerRadius: 0.175,
        cutout: .island(width: 0.32, height: 0.094, topInset: 0.028),
        decorations: [],
        buttons: [
            .init(side: .left, position: 0.15, length: 0.05),
            .init(side: .left, position: 0.23, length: 0.08),
            .init(side: .left, position: 0.33, length: 0.08),
            .init(side: .right, position: 0.26, length: 0.12),
            .init(side: .right, position: 0.62, length: 0.07),
        ],
        bodyColor: graphite,
        rimColor: titanium
    )

    /// iPhone met thuisknop en brede randen, zoals iPhone 8 / SE.
    static let iPhoneHomeButton = DeviceFrameStyle(
        id: "iphone-home",
        name: "iPhone met thuisknop",
        platform: .iOS,
        sideBezel: 0.065, topBezel: 0.28, bottomBezel: 0.28,
        screenCornerRadius: 0, bodyCornerRadius: 0.17,
        cutout: .none,
        decorations: [
            .topSpeaker(width: 0.2),
            .topCamera(diameter: 0.035, x: 0.5 - 0.17),
            .homeButton(diameter: 0.17),
        ],
        buttons: [
            .init(side: .left, position: 0.13, length: 0.04),
            .init(side: .left, position: 0.2, length: 0.07),
            .init(side: .left, position: 0.29, length: 0.07),
            .init(side: .right, position: 0.2, length: 0.08),
        ],
        bodyColor: graphite,
        rimColor: titanium
    )

    /// Android met dikke randen boven en onder, zoals Pixel 2 (16:9-scherm).
    static let androidClassic = DeviceFrameStyle(
        id: "android-classic",
        name: "Android met randen",
        platform: .android,
        sideBezel: 0.05, topBezel: 0.2, bottomBezel: 0.2,
        screenCornerRadius: 0.012, bodyCornerRadius: 0.13,
        cutout: .none,
        decorations: [
            .topSpeaker(width: 0.34),
            .topCamera(diameter: 0.05, x: 0.2),
            .bottomSpeaker(width: 0.34),
        ],
        buttons: [
            .init(side: .right, position: 0.28, length: 0.08),
            .init(side: .right, position: 0.4, length: 0.16),
        ],
        bodyColor: Color(white: 0.06),
        rimColor: darkRim
    )

    /// Android met camera-gaatje en smalle randen (moderne toestellen).
    static let androidPunchHole = DeviceFrameStyle(
        id: "android-punchhole",
        name: "Android met camera-gaatje",
        platform: .android,
        sideBezel: 0.032, topBezel: 0.04, bottomBezel: 0.045,
        screenCornerRadius: 0.08, bodyCornerRadius: 0.11,
        cutout: .punchHole(diameter: 0.04, topInset: 0.03),
        decorations: [],
        buttons: [
            .init(side: .right, position: 0.22, length: 0.15),
            .init(side: .right, position: 0.42, length: 0.07),
        ],
        bodyColor: Color(white: 0.06),
        rimColor: darkRim
    )

    /// Tablet (iPad of Android-tablet).
    static let tablet = DeviceFrameStyle(
        id: "tablet",
        name: "Tablet",
        platform: nil,
        sideBezel: 0.06, topBezel: 0.06, bottomBezel: 0.06,
        screenCornerRadius: 0.035, bodyCornerRadius: 0.075,
        cutout: .none,
        decorations: [],
        buttons: [
            .init(side: .right, position: 0.06, length: 0.06),
        ],
        bodyColor: graphite,
        rimColor: Color(white: 0.5)
    )

    /// Alleen het beeld, zonder frame.
    static let none = DeviceFrameStyle(
        id: "none",
        name: "Geen frame",
        platform: nil,
        sideBezel: 0, topBezel: 0, bottomBezel: 0,
        screenCornerRadius: 0, bodyCornerRadius: 0,
        cutout: .none,
        decorations: [],
        buttons: [],
        bodyColor: .clear,
        rimColor: .clear
    )

    static let all: [DeviceFrameStyle] = [
        .iPhoneIsland, .iPhoneNotch, .iPhoneHomeButton,
        .androidPunchHole, .androidClassic,
        .tablet, .none,
    ]

    static func style(id: String) -> DeviceFrameStyle? {
        all.first { $0.id == id }
    }

    /// Keuzelijst: eerst frames van het eigen platform, dan de rest, "Geen frame" als laatste.
    static func choices(for platform: Platform?) -> [DeviceFrameStyle] {
        let framed = all.filter(\.drawsBody)
        let own = framed.filter { $0.platform == platform }
        let shared = framed.filter { $0.platform == nil }
        let others = framed.filter { $0.platform != nil && $0.platform != platform }
        return own + shared + others + [.none]
    }
}
