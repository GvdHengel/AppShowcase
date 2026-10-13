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

/// Past eigenschappen van het onderliggende `NSWindow` aan die SwiftUI zelf niet biedt.
struct WindowConfigurator: NSViewRepresentable {
    let transparent: Bool

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
        window.isOpaque = !transparent
        window.backgroundColor = transparent ? .clear : .windowBackgroundColor
        window.titlebarAppearsTransparent = transparent
        // Bij transparant is er geen achtergrond om aan te slepen: sleep dan aan het toestel zelf.
        window.isMovableByWindowBackground = transparent
        window.hasShadow = !transparent
        window.invalidateShadow()
    }
}
