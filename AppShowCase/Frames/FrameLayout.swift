import CoreGraphics

/// Berekent alle rechthoeken van een toestelframe voor een gegeven schermmaat en beschikbare ruimte.
///
/// Er wordt altijd in **staande** coördinaten gerekend (het "canvas"). Bij een liggend beeld wordt
/// het canvas 90° tegen de klok in gedraaid getoond: de bovenkant van het toestel komt links.
/// `displaySize` en `displayScreenRect` zijn de maten na die draaiing.
struct FrameLayout: Equatable {
    enum Shape: Equatable {
        case capsule
        case circle
        case ring
        case roundedRect(cornerRadius: CGFloat)
        /// Inkeping: alleen de onderhoeken afgerond.
        case notch(cornerRadius: CGFloat)
    }

    struct Element: Equatable {
        let rect: CGRect
        let shape: Shape
    }

    let isLandscape: Bool
    /// Schermbreedte (staand) in punten; alle stijlmaten worden hiermee vermenigvuldigd.
    let scale: CGFloat
    let canvasSize: CGSize
    let bodyRect: CGRect
    let bodyCornerRadius: CGFloat
    let rimWidth: CGFloat
    let screenRect: CGRect
    let screenCornerRadius: CGFloat
    let cutout: Element?
    let decorations: [Element]
    let buttons: [Element]

    /// Maat van het geheel zoals getoond (na eventuele draaiing).
    var displaySize: CGSize {
        isLandscape ? CGSize(width: canvasSize.height, height: canvasSize.width) : canvasSize
    }

    /// Plek van het videobeeld zoals getoond (na eventuele draaiing).
    var displayScreenRect: CGRect {
        isLandscape ? Self.rotateToLandscape(screenRect, canvasWidth: canvasSize.width) : screenRect
    }

    init(style: DeviceFrameStyle, screenSize: CGSize, fitting available: CGSize) {
        let landscape = screenSize.width > screenSize.height
        let shortSide = max(min(screenSize.width, screenSize.height), 1)
        let longSide = max(max(screenSize.width, screenSize.height), 1)
        let heightPerWidth = longSide / shortSide

        // Knoppen steken iets buiten de behuizing uit.
        let buttonDepth: CGFloat = style.buttons.isEmpty ? 0 : 0.012

        // Afmetingen in eenheden van de schermbreedte.
        let unitWidth = 1 + 2 * style.sideBezel + 2 * buttonDepth
        let unitHeight = heightPerWidth + style.topBezel + style.bottomBezel

        let fit: CGFloat
        if landscape {
            fit = min(available.width / unitHeight, available.height / unitWidth)
        } else {
            fit = min(available.width / unitWidth, available.height / unitHeight)
        }
        let s = max(fit, 0)

        isLandscape = landscape
        scale = s

        let side = style.sideBezel * s
        let top = style.topBezel * s
        let bottom = style.bottomBezel * s
        let depth = buttonDepth * s
        let screenHeight = heightPerWidth * s

        let body = CGRect(x: depth, y: 0, width: s + 2 * side, height: screenHeight + top + bottom)
        bodyRect = body
        bodyCornerRadius = style.bodyCornerRadius * s
        rimWidth = style.drawsBody ? max(0.008 * s, 1) : 0
        canvasSize = CGSize(width: body.width + 2 * depth, height: body.height)

        let screen = CGRect(x: body.minX + side, y: top, width: s, height: screenHeight)
        screenRect = screen
        screenCornerRadius = style.screenCornerRadius * s

        switch style.cutout {
        case .none:
            cutout = nil
        case let .notch(width, height, radius):
            cutout = Element(
                rect: CGRect(x: screen.midX - width * s / 2, y: screen.minY, width: width * s, height: height * s),
                shape: .notch(cornerRadius: radius * s)
            )
        case let .island(width, height, inset):
            cutout = Element(
                rect: CGRect(x: screen.midX - width * s / 2, y: screen.minY + inset * s, width: width * s, height: height * s),
                shape: .capsule
            )
        case let .punchHole(diameter, inset):
            cutout = Element(
                rect: CGRect(x: screen.midX - diameter * s / 2, y: screen.minY + inset * s, width: diameter * s, height: diameter * s),
                shape: .circle
            )
        }

        let slotHeight = 0.022 * s
        decorations = style.decorations.map { decoration in
            switch decoration {
            case .topSpeaker(let width):
                return Element(
                    rect: CGRect(x: body.midX - width * s / 2, y: top / 2 - slotHeight / 2, width: width * s, height: slotHeight),
                    shape: .capsule
                )
            case .bottomSpeaker(let width):
                return Element(
                    rect: CGRect(x: body.midX - width * s / 2, y: screen.maxY + bottom / 2 - slotHeight / 2, width: width * s, height: slotHeight),
                    shape: .capsule
                )
            case let .topCamera(diameter, x):
                return Element(
                    rect: CGRect(x: body.minX + x * body.width - diameter * s / 2, y: top / 2 - diameter * s / 2, width: diameter * s, height: diameter * s),
                    shape: .circle
                )
            case .homeButton(let diameter):
                return Element(
                    rect: CGRect(x: body.midX - diameter * s / 2, y: screen.maxY + bottom / 2 - diameter * s / 2, width: diameter * s, height: diameter * s),
                    shape: .ring
                )
            }
        }

        buttons = style.buttons.map { button in
            let x = button.side == .left ? body.minX - depth : body.maxX - depth / 2
            return Element(
                rect: CGRect(x: x, y: body.minY + button.position * body.height, width: depth * 1.5, height: button.length * body.height),
                shape: .roundedRect(cornerRadius: depth * 0.6)
            )
        }
    }

    /// Zet een rechthoek uit het staande canvas om naar de tegen de klok in gedraaide weergave.
    static func rotateToLandscape(_ rect: CGRect, canvasWidth: CGFloat) -> CGRect {
        CGRect(x: rect.minY, y: canvasWidth - rect.maxX, width: rect.height, height: rect.width)
    }
}
