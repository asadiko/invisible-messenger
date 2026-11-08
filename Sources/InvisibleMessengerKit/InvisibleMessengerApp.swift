import AppKit

/// Starts the app (used by the InvisibleMessenger executable).
public enum InvisibleMessengerApp {
    private static var delegate: AppDelegate?

    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.mainMenu = AppDelegate.makeMainMenu()
        HiddenWindowGuard.install()
        app.run()
    }
}
