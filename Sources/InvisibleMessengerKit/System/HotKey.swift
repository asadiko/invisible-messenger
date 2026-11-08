import Carbon.HIToolbox
import Foundation

/// A system-wide shortcut registered with Carbon (works without Accessibility permission).
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var eventHandlerInstalled = false
    private static let signature: OSType = 0x494D_7367 // "IMsg"

    private var ref: EventHotKeyRef?
    private let id: UInt32

    /// Returns nil if the shortcut can't be registered (for example, another app already owns it).
    init?(spec: HotKeySpec, handler: @escaping () -> Void) {
        Self.installEventHandler()
        id = Self.nextID
        Self.nextID += 1
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            spec.keyCode,
            spec.modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else { return nil }
        ref = hotKeyRef
        Self.handlers[id] = handler
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.handlers[id] = nil
    }

    private static func installEventHandler() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            let id = hotKeyID.id
            MainActor.assumeIsolated { HotKey.handlers[id]?() }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}
