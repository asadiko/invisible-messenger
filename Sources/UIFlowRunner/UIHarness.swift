import AppKit
import CryptoKit
import Foundation
import SwiftUI
@testable import InvisibleMessengerKit
@testable import MessengerCore

struct UITimeout: Error, CustomStringConvertible {
    let what: String
    var description: String { "timed out waiting for \(what)" }
}

/// Drives the real SwiftUI/AppKit views in an off-screen window: presses buttons through accessibility,
/// clicks into text fields and types with real key events. Nothing touches the user's mouse or keyboard.
final class UIHarness {
    let model: AppModel
    let window: KeyablePanel

    init(model: AppModel, size: CGSize = CGSize(width: 660, height: 520)) {
        self.model = model
        window = KeyablePanel(
            contentRect: NSRect(x: -6000, y: -6000, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        window.contentView = NSHostingView(rootView: PanelContent(model: model, chrome: ChatChrome(
            onClose: {}, onTogglePin: {}, isPinned: false, topInset: 0
        )))
        window.orderFrontRegardless()
        model.chatVisible = true
        render()
        Self.announceAccessibility()
    }

    func close() {
        model.chatVisible = false
        window.orderOut(nil)
    }

    /// Suspends the test so the main run loop can render SwiftUI and deliver network callbacks.
    /// (Never runs the run loop nested: that can end Swift Testing's own run loop early.)
    func pump(_ seconds: Double = 0.05) async {
        try? await Task.sleep(for: .seconds(seconds))
        render()
    }

    /// Brings SwiftUI's views (and their accessibility tree) up to date.
    func render() {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    /// SwiftUI builds the accessibility tree of existing views when assistive access is switched on.

    func waitUntil(_ what: String, timeout: Double = 8, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { throw UITimeout(what: what) }
            await pump(0.05)
        }
    }

    // MARK: Accessibility tree

    /// SwiftUI only builds its accessibility tree once an assistive client asks for it.
    /// SwiftUI builds the accessibility tree of existing views when assistive access is switched on,
    /// which is how this runner finds and presses controls.
    static func announceAccessibility() {
        let app = NSApplication.shared
        let set = Selector(("accessibilitySetValue:forAttribute:"))
        app.perform(set, with: NSNumber(value: false), with: "AXEnhancedUserInterface")
        app.perform(set, with: NSNumber(value: true), with: "AXEnhancedUserInterface")
    }

    func elements() -> [AnyObject] {
        var out: [AnyObject] = []
        func walk(_ node: AnyObject, depth: Int) {
            guard depth < 80 else { return }
            out.append(node)
            for child in (node.accessibilityChildren?() ?? nil) ?? [] { walk(child as AnyObject, depth: depth + 1) }
        }
        if let root = window.contentView { walk(root, depth: 0) }
        return out
    }

    func label(_ element: AnyObject) -> String {
        let label = (element.accessibilityLabel?() ?? nil) ?? ""
        if !label.isEmpty { return label }
        return (element.accessibilityTitle?() ?? nil) ?? ""
    }

    func value(_ element: AnyObject) -> String {
        let selector = NSSelectorFromString("accessibilityValue")
        guard let object = element as? NSObject, object.responds(to: selector) else { return "" }
        return object.perform(selector)?.takeUnretainedValue() as? String ?? ""
    }

    /// Every label currently on screen, to make failures readable.
    var labels: [String] {
        elements().map { "\(label($0))=\(value($0))" }.filter { $0 != "=" }
    }

    func element(_ text: String) -> AnyObject? {
        elements().first { label($0) == text }
    }

    func has(_ text: String) -> Bool {
        elements().contains { label($0) == text || value($0) == text || label($0).contains(text) }
    }

    /// Presses the control with this label; `last` picks the last one when several share it
    /// (for example a "Remove" button and its "Remove" confirmation).
    func press(_ text: String, last: Bool = false) async throws {
        await pump()
        let matches = elements().filter { label($0) == text }
        guard let target = last ? matches.last : matches.first else { throw UITimeout(what: "a control labelled “\(text)” (on screen: \(labels))") }
        _ = target.accessibilityPerformPress?()
        await pump(0.15)
    }

    // MARK: Typing

    func views<T: NSView>(of type: T.Type) -> [T] {
        var out: [T] = []
        func walk(_ view: NSView) {
            if let match = view as? T { out.append(match) }
            view.subviews.forEach(walk)
        }
        if let root = window.contentView { walk(root) }
        return out
    }

    /// Clicks into the n-th editable text field (makes it first responder, as a click does) and types.
    func type(_ text: String, intoField index: Int = 0) async throws {
        await pump()
        let fields = views(of: NSTextField.self).filter { $0.isEditable }
        guard index < fields.count else { throw UITimeout(what: "text field #\(index) (found \(fields.count))") }
        window.makeFirstResponder(fields[index])
        await pump()
        await typeKeys(text)
    }

    /// Types into the message box, then presses Return if asked.
    func typeMessage(_ text: String, send: Bool = true) async throws {
        guard let composer = views(of: ComposerTextView.self).first else { throw UITimeout(what: "the message box") }
        window.makeFirstResponder(composer)
        await typeKeys(text)
        if send { await key("\r", code: 36) }
    }

    func typeKeys(_ text: String) async {
        for ch in text { await key(String(ch), code: 0) }
        await pump(0.1)
    }

    func key(_ chars: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) async {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: chars,
                charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code
            ) else { continue }
            window.sendEvent(event)
        }
        await pump(0.01)
    }

    func submit() async { await key("\r", code: 36) }
}

/// A full app model on a loopback directory, with its own temp data, keys and preferences.
func makeTestModel(name: String) throws -> (AppModel, StaticDirectory) {
    let suite = "im-uitest-\(name)-\(UUID().uuidString)"
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    let store = try ChatStore(directory: dir, sealer: DataSealer(key: SymmetricKey(size: .bits256)))
    let defaults = UserDefaults(suiteName: suite)!
    defaults.set(name, forKey: "displayName")
    defaults.set(dir.appendingPathComponent("Saved").path, forKey: "saveFolder")
    let directory = StaticDirectory()
    let model = AppModel(
        profile: Profile(name: suite),
        settings: AppSettings(defaults: defaults),
        secrets: InMemorySecretStore(),
        identity: .generate(),
        store: store,
        directory: directory
    )
    return (model, directory)
}
