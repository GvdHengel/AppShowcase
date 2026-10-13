import SwiftUI
import AppKit

// MARK: - Window Level Modifier
struct FloatingWindowModifier: ViewModifier {
    let isFloating: Bool
    
    func body(content: Content) -> some View {
        content
            .background(WindowAccessor(isFloating: isFloating))
    }
}

extension View {
    func floatingWindow(_ isFloating: Bool = true) -> some View {
        self.modifier(FloatingWindowModifier(isFloating: isFloating))
    }
}

// Struct om de onderliggende NSWindow the benaderen via NSViewRepresentable
struct WindowAccessor: NSViewRepresentable {
    let isFloating: Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.level = isFloating ? .floating : .normal
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                window.level = isFloating ? .floating : .normal
            }
        }
    }
}
