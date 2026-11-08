import AppKit

/// A panel that can take keyboard focus without activating the app (so the app you're presenting stays in front),
/// is always hidden from capture, and handles the standard editing shortcuts itself (the app has no visible menu bar).
final class KeyablePanel: NSPanel {
    var onEscape: (() -> Void)?
    var acceptsKey = true

    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        HiddenWindowGuard.protect(self)
    }

    override var canBecomeKey: Bool { acceptsKey }

    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func orderFront(_ sender: Any?) {
        HiddenWindowGuard.protect(self)
        super.orderFront(sender)
    }

    override func orderFrontRegardless() {
        HiddenWindowGuard.protect(self)
        super.orderFrontRegardless()
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        HiddenWindowGuard.protect(self)
        super.makeKeyAndOrderFront(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option) else {
            return super.performKeyEquivalent(with: event)
        }
        let shift = flags.contains(.shift)
        let action: Selector? = switch (event.charactersIgnoringModifiers?.lowercased(), shift) {
        case ("c", false): #selector(NSText.copy(_:))
        case ("v", _): #selector(NSText.paste(_:))
        case ("x", false): #selector(NSText.cut(_:))
        case ("a", false): #selector(NSText.selectAll(_:))
        case ("z", false): Selector(("undo:"))
        case ("z", true): Selector(("redo:"))
        default: nil
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}
