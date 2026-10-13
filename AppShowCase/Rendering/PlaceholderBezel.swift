import SwiftUI

/// Eenvoudig tijdelijk toestelframe tot de echte frames in fase 3 komen.
/// Houdt de beeldverhouding van het scherm aan, dus werkt ook liggend.
struct PlaceholderBezel<Screen: View>: View {
    let screenAspectRatio: CGFloat
    let platform: Platform
    @ViewBuilder let screen: () -> Screen

    private var screenCornerRadius: CGFloat { platform == .iOS ? 34 : 14 }
    private var bezelWidth: CGFloat { platform == .iOS ? 12 : 16 }

    var body: some View {
        screen()
            .aspectRatio(screenAspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous))
            .padding(bezelWidth)
            .background(
                RoundedRectangle(cornerRadius: screenCornerRadius + bezelWidth, style: .continuous)
                    .fill(Color(white: 0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: screenCornerRadius + bezelWidth, style: .continuous)
                            .strokeBorder(Color(white: 0.35), lineWidth: 2)
                    )
            )
            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
    }
}
