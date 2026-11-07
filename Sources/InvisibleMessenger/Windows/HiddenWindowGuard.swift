import AppKit

/// Keeps every window of the app out of screenshots, screen recordings and screen sharing.
enum HiddenWindowGuard {
    /// Development only: a DEBUG build launched with IM_DEV_CAPTURABLE=1 can be screenshotted.
    static var capturable: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["IM_DEV_CAPTURABLE"] == "1"
        #else
        return false
        #endif
    }

    private static var observers: [NSObjectProtocol] = []

    static func install() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSApplication.didUpdateNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didUpdateNotification,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { protectAll() }
            }
        }
    }

    static func protectAll() {
        NSApp.windows.forEach(protect)
    }

    static func protect(_ window: NSWindow) {
        let target: NSWindow.SharingType = capturable ? .readOnly : .none
        if window.sharingType != target { window.sharingType = target }
    }
}
