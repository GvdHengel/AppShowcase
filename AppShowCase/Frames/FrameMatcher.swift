import CoreGraphics

/// Kiest automatisch een passend frame op basis van platform en schermresolutie.
enum FrameMatcher {
    /// Lange zijde (px) van iPhones met eiland: 14 Pro/15/16 (2556), 16 Pro/17/17 Pro (2622),
    /// Air (2736), 14 Pro Max/15 Plus/15 Pro Max/16 Plus (2796), 16 Pro Max/17 Pro Max (2868).
    static let islandLongSides: Set<Int> = [2556, 2622, 2736, 2796, 2868]

    static func automaticStyle(platform: Platform, screenSize: CGSize?) -> DeviceFrameStyle {
        guard let size = screenSize, size.width > 0, size.height > 0 else {
            return platform == .iOS ? .iPhoneNotch : .androidPunchHole
        }
        let shortSide = min(size.width, size.height)
        let longSide = max(size.width, size.height)
        let ratio = shortSide / longSide

        if ratio > 0.6 {
            return .tablet
        }
        let isSixteenByNine = abs(ratio - 9.0 / 16.0) < 0.012

        switch platform {
        case .iOS:
            if isSixteenByNine { return .iPhoneHomeButton }
            // Kleine afwijkingen opvangen (de capture levert soms 1 px opvulling).
            let long = Int(longSide.rounded())
            let hasIsland = islandLongSides.contains { abs($0 - long) <= 2 }
            return hasIsland ? .iPhoneIsland : .iPhoneNotch
        case .android:
            return isSixteenByNine ? .androidClassic : .androidPunchHole
        }
    }
}
