import AppKit
import CoreGraphics

/// Calls `onIdle` when the whole Mac has had no keyboard or mouse input for the chosen time,
/// and when the Mac goes to sleep or the screen locks.
final class IdleMonitor {
    private let settings: AppSettings
    private let onIdle: () -> Void
    private var timer: Timer?
    private var firedForCurrentIdle = false

    init(settings: AppSettings, onIdle: @escaping () -> Void) {
        self.settings = settings
        self.onIdle = onIdle
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(systemWillSleep), name: Notification.Name("com.apple.screenIsLocked"), object: nil
        )
    }

    /// Seconds since the last keyboard/mouse event anywhere on the Mac.
    static var secondsSinceInput: TimeInterval {
        guard let anyInput = CGEventType(rawValue: UInt32.max) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    private func check() {
        guard let minutes = settings.idleLockMinutes else { return }
        let idle = Self.secondsSinceInput
        if idle >= TimeInterval(minutes * 60) {
            if !firedForCurrentIdle {
                firedForCurrentIdle = true
                onIdle()
            }
        } else {
            firedForCurrentIdle = false
        }
    }

    @objc private func systemWillSleep() {
        onIdle()
    }
}
