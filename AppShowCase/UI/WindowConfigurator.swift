import AppKit
import SwiftUI

/// Achtergrond van een toestelvenster.
enum WindowBackground: String, CaseIterable, Identifiable {
    case dark
    case light
    /// Alleen het toestel zweeft op het bureaublad (zoals Bezel).
    case transparent

    var id: String { rawValue }

    var name: String {
        switch self {
        case .dark: return "Donker"
        case .light: return "Licht"
        case .transparent: return "Transparant"
        }
    }

    var color: Color {
        switch self {
        case .dark: return Color(white: 0.13)
        case .light: return Color(white: 0.93)
        case .transparent: return .clear
        }
    }
}

/// Zwakke verwijzing naar het `NSWindow` van een SwiftUI-view (bijv. om het formaat te zetten).
final class WindowReference {
    weak var window: NSWindow?
}

/// Vaste venstergroottes; de waarde is de lange zijde van het scherm in punten.
enum WindowSizePreset: String, CaseIterable, Identifiable {
    case small, medium, large, actual

    var id: String { rawValue }

    var name: String {
        switch self {
        case .small: return "Klein"
        case .medium: return "Middel"
        case .large: return "Groot"
        case .actual: return "Ware grootte (1 pixel = 1 pixel)"
        }
    }

    func screenLongSide(pixelLongSide: CGFloat, backingScale: CGFloat) -> CGFloat {
        switch self {
        case .small: return 480
        case .medium: return 680
        case .large: return 880
        case .actual: return pixelLongSide / max(backingScale, 1)
        }
    }
}

/// Past eigenschappen van het onderliggende `NSWindow` aan die SwiftUI zelf niet biedt.
struct WindowConfigurator: NSViewRepresentable {
    let transparent: Bool
    var floating: Bool = false
    var reference: WindowReference?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: view.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        reference?.window = window
        window.level = floating ? .floating : .normal
        window.isOpaque = !transparent
        window.backgroundColor = transparent ? .clear : .windowBackgroundColor
        window.titlebarAppearsTransparent = transparent
        // Bij transparant is er geen achtergrond om aan te slepen: sleep dan aan het toestel zelf.
        window.isMovableByWindowBackground = transparent
        window.hasShadow = !transparent
        window.invalidateShadow()
    }
}
