import SwiftUI

/// Welke lagen `DeviceFrameView` tekent (de opname rendert ze los).
struct DeviceFrameParts: OptionSet, Sendable {
    let rawValue: Int
    static let body = DeviceFrameParts(rawValue: 1 << 0)
    static let screen = DeviceFrameParts(rawValue: 1 << 1)
    static let cutout = DeviceFrameParts(rawValue: 1 << 2)
    static let all: DeviceFrameParts = [.body, .screen, .cutout]
}

/// Tekent een toestelframe rond het live beeld.
///
/// Drie lagen: behuizing (onder), beeld (midden), uitsparing zoals notch of eiland (boven).
/// Behuizing en uitsparing worden staand getekend en bij liggend beeld samen gedraaid;
/// het beeld zelf komt al liggend binnen en wordt alleen op de juiste plek gezet.
struct DeviceFrameView<Screen: View>: View {
    let style: DeviceFrameStyle
    /// Pixelafmetingen van het beeld; bepaalt beeldverhouding en staand/liggend.
    let screenSize: CGSize
    var parts: DeviceFrameParts = .all
    @ViewBuilder let screen: () -> Screen

    var body: some View {
        GeometryReader { geometry in
            let layout = FrameLayout(style: style, screenSize: screenSize, fitting: geometry.size)
            let screenRect = layout.displayScreenRect

            ZStack(alignment: .topLeading) {
                if style.drawsBody && parts.contains(.body) {
                    rotated(layout) { FrameBodyCanvas(style: style, layout: layout) }
                        .shadow(color: .black.opacity(0.35), radius: layout.scale * 0.03, y: layout.scale * 0.015)
                }

                if parts.contains(.screen) {
                    screen()
                        .frame(width: screenRect.width, height: screenRect.height)
                        .clipShape(RoundedRectangle(cornerRadius: layout.screenCornerRadius, style: .continuous))
                        .offset(x: screenRect.minX, y: screenRect.minY)
                }

                if layout.cutout != nil && parts.contains(.cutout) {
                    rotated(layout) { CutoutCanvas(layout: layout) }
                        .allowsHitTesting(false)
                }
            }
            .frame(width: layout.displaySize.width, height: layout.displaySize.height, alignment: .topLeading)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    /// Plaatst een staand getekende laag, bij liggend beeld 90° tegen de klok in gedraaid.
    private func rotated<Content: View>(_ layout: FrameLayout, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
            .rotationEffect(.degrees(layout.isLandscape ? -90 : 0))
            .frame(width: layout.displaySize.width, height: layout.displaySize.height)
    }
}

/// Behuizing, rand, knoppen, luidsprekers, camera en thuisknop.
private struct FrameBodyCanvas: View {
    let style: DeviceFrameStyle
    let layout: FrameLayout

    var body: some View {
        Canvas { context, _ in
            // Knoppen eerst: de behuizing bedekt het deel dat "erin" zit.
            for button in layout.buttons {
                context.fill(path(for: button), with: .color(style.rimColor))
            }

            // Metalen rand + behuizing.
            context.fill(
                Path(roundedRect: layout.bodyRect, cornerRadius: layout.bodyCornerRadius, style: .continuous),
                with: .color(style.rimColor)
            )
            let inner = layout.bodyRect.insetBy(dx: layout.rimWidth, dy: layout.rimWidth)
            context.fill(
                Path(roundedRect: inner, cornerRadius: max(layout.bodyCornerRadius - layout.rimWidth, 0), style: .continuous),
                with: .linearGradient(
                    Gradient(colors: [style.bodyColor.opacity(0.85), style.bodyColor]),
                    startPoint: CGPoint(x: inner.minX, y: inner.minY),
                    endPoint: CGPoint(x: inner.maxX, y: inner.maxY)
                )
            )

            // Zwarte ondergrond onder het scherm (zichtbaar tot het eerste frame binnen is).
            context.fill(
                Path(roundedRect: layout.screenRect, cornerRadius: layout.screenCornerRadius, style: .continuous),
                with: .color(.black)
            )

            for decoration in layout.decorations {
                switch decoration.shape {
                case .ring:
                    context.stroke(
                        Circle().path(in: decoration.rect),
                        with: .color(Color(white: 0.3)),
                        lineWidth: max(layout.scale * 0.006, 1)
                    )
                case .circle:
                    // Camera: donkere lens met een vleugje blauw.
                    context.fill(Circle().path(in: decoration.rect), with: .color(Color(white: 0.16)))
                    let lens = decoration.rect.insetBy(dx: decoration.rect.width * 0.28, dy: decoration.rect.height * 0.28)
                    context.fill(Circle().path(in: lens), with: .color(Color(red: 0.08, green: 0.1, blue: 0.2)))
                default:
                    context.fill(path(for: decoration), with: .color(Color(white: 0.18)))
                }
            }
        }
    }
}

/// Notch, eiland of camera-gaatje, over het beeld heen.
private struct CutoutCanvas: View {
    let layout: FrameLayout

    var body: some View {
        Canvas { context, _ in
            guard let cutout = layout.cutout else { return }
            context.fill(path(for: cutout), with: .color(.black))
            // Subtiele cameralens in eiland of gaatje.
            if case .circle = cutout.shape {
                let lens = cutout.rect.insetBy(dx: cutout.rect.width * 0.3, dy: cutout.rect.height * 0.3)
                context.fill(Circle().path(in: lens), with: .color(Color(red: 0.06, green: 0.08, blue: 0.16)))
            }
        }
    }
}

private func path(for element: FrameLayout.Element) -> Path {
    switch element.shape {
    case .capsule:
        return Capsule().path(in: element.rect)
    case .circle, .ring:
        return Circle().path(in: element.rect)
    case .roundedRect(let radius):
        return Path(roundedRect: element.rect, cornerRadius: radius, style: .continuous)
    case .notch(let radius):
        return UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: radius,
            bottomTrailingRadius: radius,
            topTrailingRadius: 0,
            style: .continuous
        ).path(in: element.rect)
    }
}
