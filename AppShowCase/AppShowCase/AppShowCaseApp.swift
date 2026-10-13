import SwiftUI
import AppKit

@main
struct AppShowcaseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "AppShowcase")
            
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Toon AppShowcase", action: #selector(bringToFront), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Stop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            
            statusItem?.menu = menu
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up ADB server to prevent zombie processes
        // This uses a fresh ADBManager just for cleanup since
        // we can't easily access the one in ContentView
        let cleanup = ADBManager()
        cleanup.killADBServer()
    }
    
    @objc func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
