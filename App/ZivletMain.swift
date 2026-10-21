import AppKit

/// AppKit entry point (14 §3.1): an accessory app with a status item, no Dock icon (`LSUIElement`).
@main
enum ZivletMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
