import AppKit
import Foundation
import Network
@testable import InvisibleMessengerKit
@testable import MessengerCore

/// One running copy of the app: model, its loopback directory and a window showing its UI.
final class TestMac {
    let model: AppModel
    let directory: StaticDirectory
    let ui: UIHarness

    init(_ name: String) async throws {
        (model, directory) = try makeTestModel(name: name)
        model.start()
        ui = UIHarness(model: model)
        try await ui.waitUntil("\(name)'s listener") { model.messenger.listenerPort != nil }
    }

    var id: DeviceID { model.messenger.myID }

    var entry: DiscoveredPeer {
        DiscoveredPeer(
            name: id.rawValue,
            endpoint: .hostPort(host: "127.0.0.1", port: model.messenger.listenerPort!),
            pairingOpen: model.messenger.listener.pairingOpen
        )
    }

    var code: String? {
        if case .showingCode(let code, _)? = model.pairingState { return code }
        return nil
    }

    func stop() {
        ui.close()
        model.messenger.stop()
    }
}

/// Lets each Mac see the other on the "network", including whether it is showing a code.
func link(_ a: TestMac, _ b: TestMac) {
    a.directory.peers = [b.entry]
    b.directory.peers = [a.entry]
}

/// Keeps the user's clipboard intact around tests that copy or paste.
func withSavedClipboard(_ body: () async throws -> Void) async rethrows {
    let board = NSPasteboard.general
    let saved = board.pasteboardItems?.map { item -> NSPasteboardItem in
        let copy = NSPasteboardItem()
        for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
        return copy
    } ?? []
    defer {
        board.clearContents()
        if !saved.isEmpty { board.writeObjects(saved) }
    }
    try await body()
}

/// Pairs two Macs entirely through their UIs and returns them connected.
func pairThroughUI(_ a: TestMac, _ b: TestMac) async throws {
    try await a.ui.press("Add contact")
    try await a.ui.waitUntil("A's code") { a.code != nil }
    let code = try require(a.code)
    expect(a.ui.has(PairingCode.display(code)), #"a.ui.has(PairingCode.display(code))"#)
    link(a, b)

    try await b.ui.press("Add contact")
    try await b.ui.press("Enter code")
    expect(b.code == nil, #"b.code == nil"#)
    try await b.ui.type(code.lowercased(), intoField: 0)
    try await b.ui.press("Connect")

    try await a.ui.waitUntil("both to compare emoji") {
        if case .verify? = a.model.pairingState, case .verify? = b.model.pairingState { return true }
        return false
    }
    guard case .verify(let emojiA, _)? = a.model.pairingState, case .verify(let emojiB, _)? = b.model.pairingState else { return }
    expect(emojiA == emojiB, #"emojiA == emojiB"#)
    expect(a.ui.has("Do you both see the same emoji?"), #"a.ui.has("Do you both see the same emoji?")"#)
    expect(b.ui.has("Do you both see the same emoji?"), #"b.ui.has("Do you both see the same emoji?")"#)

    try await a.ui.press("They match")
    try await b.ui.press("They match")
    try await a.ui.waitUntil("both to finish pairing") {
        if case .done? = a.model.pairingState, case .done? = b.model.pairingState { return true }
        return false
    }
    expect(a.ui.has("Bob added"), #"a.ui.has("Bob added")"#)
    expect(b.ui.has("Alice added"), #"b.ui.has("Alice added")"#)
    try await a.ui.press("Start chatting")
    try await b.ui.press("Start chatting")
    expect(a.model.screen == .chat, #"a.model.screen == .chat"#)
    expect(!a.model.messenger.listener.pairingOpen, #"!a.model.messenger.listener.pairingOpen"#)

    link(a, b)
    try await a.ui.waitUntil("A and B to connect") { a.model.isOnline(b.id) && b.model.isOnline(a.id) }
}

struct UIFlows {
    /// The reported crash: clicking into the code box and typing.
    func typingTheCodeDoesNotCrash() async throws {
        let (model, _) = try makeTestModel(name: "Bob")
        let ui = UIHarness(model: model)
        defer { ui.close() }
        try await ui.press("Add contact")
        try await ui.press("Enter code")
        try await ui.type("k7q4m2xp")
        try await ui.waitUntil("the code to be formatted") { ui.views(of: NSTextField.self).contains { $0.stringValue == "K7Q4-M2XP" } }
    }

    func pairChatCodeBlocksFilesAndImagesThroughTheUI() async throws {
        let a = try await TestMac("Alice"), b = try await TestMac("Bob")
        defer { a.stop(); b.stop() }
        try await pairThroughUI(a, b)

        // Text, typed and sent with Return.
        try await b.ui.typeMessage("hello from Bob")
        try await a.ui.waitUntil("Alice to receive Bob's text") {
            a.model.messages.contains { $0.body == .text("hello from Bob") }
        }
        try await b.ui.waitUntil("Bob's message to show ✓✓") {
            b.model.messages.first { $0.body == .text("hello from Bob") }?.status == .delivered
        }
        expect(a.ui.has("Message: hello from Bob"), #"a.ui.has("Message: hello from Bob")"#)
        expect(a.model.contact(b.id)?.unreadCount == 0, #"a.model.contact(b.id)?.unreadCount == 0"#)

        // A multi-line code block (Shift-Return makes new lines), then its Copy button on the other Mac.
        try await a.ui.typeMessage("```swift", send: false)
        await a.ui.key("\r", code: 36, modifiers: .shift)
        await a.ui.typeKeys("let x = 1")
        await a.ui.key("\r", code: 36, modifiers: .shift)
        await a.ui.typeKeys("```")
        await a.ui.submit()
        try await b.ui.waitUntil("Bob to receive the code block") {
            b.model.messages.contains { $0.body == .text("```swift\nlet x = 1\n```") }
        }
        try await withSavedClipboard {
            try await b.ui.press("Copy")
            expect(NSPasteboard.general.string(forType: .string) == "let x = 1", #"NSPasteboard.general.string(forType: .string) == "let x = 1""#)
        }

        // A file and an image, pasted into the message box.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID().uuidString).txt")
        try Data("meeting notes".utf8).write(to: file)
        let composer = try require(a.ui.views(of: ComposerTextView.self).first)
        try await withSavedClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([file as NSURL])
            composer.paste(nil)
            let image = NSImage(size: NSSize(width: 40, height: 30), flipped: false) { rect in
                NSColor.systemTeal.setFill(); rect.fill(); return true
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            composer.paste(nil)
        }
        try await b.ui.waitUntil("Bob to receive the file and the image") {
            let names = b.model.messages.compactMap { m -> String? in
                if case .attachment(let info) = m.body { return info.fileName } else { return nil }
            }
            return names.contains(file.lastPathComponent) && names.contains("Pasted image.png")
        }
        await b.ui.pump(0.3)
        try await b.ui.press("Save")
        let saved = b.model.settings.saveFolder.appendingPathComponent(file.lastPathComponent)
        try await b.ui.waitUntil("the file to be saved") { FileManager.default.fileExists(atPath: saved.path) }
        let savedText = try String(contentsOf: saved, encoding: .utf8)
        expect(savedText == "meeting notes", "saved file contains the notes")
        try await b.ui.press("Open image Pasted image.png")
        expect(ImageViewerController.shared.isOpen, #"ImageViewerController.shared.isOpen"#)
        ImageViewerController.shared.close()

        // Delete a message through its accessibility action.
        let row = try require(a.ui.element("Message: hello from Bob"))
        let delete = try require((row.accessibilityCustomActions?() ?? nil)?.first { $0.name == "Delete message" })
        _ = delete.handler?()
        await a.ui.pump(0.2)
        expect(!a.model.messages.contains { $0.body == .text("hello from Bob") }, #"!a.model.messages.contains { $0.body == .text("hello from Bob") }"#)
    }

    func messagesWaitWhileTheOtherMacIsOffline() async throws {
        let a = try await TestMac("Alice"), b = try await TestMac("Bob")
        defer { a.stop(); b.stop() }
        try await pairThroughUI(a, b)
        b.model.messenger.stop()
        try await a.ui.waitUntil("Alice to see Bob offline") { !a.model.isOnline(b.id) }
        expect(a.ui.has("Bob is offline · messages will be sent when they're back"), #"a.ui.has("Bob is offline · messages will be sent when they're back")"#)
        try await a.ui.typeMessage("are you there?")
        expect(a.model.messages.last?.status == .sending, #"a.model.messages.last?.status == .sending"#)
        b.model.start()
        try await b.ui.waitUntil("Bob's listener") { b.model.messenger.listenerPort != nil }
        link(a, b)
        try await a.ui.waitUntil("the queued message to be delivered", timeout: 12) {
            a.model.messages.last?.status == .delivered
        }
        expect(b.model.messages.contains { $0.body == .text("are you there?") }, #"b.model.messages.contains { $0.body == .text("are you there?") }"#)
    }

    func everySettingWorksThroughTheUI() async throws {
        let a = try await TestMac("Alice"), b = try await TestMac("Bob")
        defer { a.stop(); b.stop() }
        try await pairThroughUI(a, b)
        try await a.ui.typeMessage("first")
        try await a.ui.waitUntil("a message to exist") { a.model.messages.count == 1 }
        let ui = a.ui, settings = a.model.settings

        try await ui.press("Settings")
        expect(a.model.screen == .settings, #"a.model.screen == .settings"#)

        try await ui.press("Floating window")
        expect(settings.appearance == .floating, #"settings.appearance == .floating"#)
        try await ui.press("In the notch")
        expect(settings.appearance == .notch, #"settings.appearance == .notch"#)
        try await ui.press("Tabs")
        expect(settings.layout == .tabs, #"settings.layout == .tabs"#)
        try await ui.press("List")
        expect(settings.layout == .sidebar, #"settings.layout == .sidebar"#)

        settings.panelSize = CGSize(width: 900, height: 600)
        try await ui.press("Reset to 3 notches wide")
        expect(settings.panelSize == nil, #"settings.panelSize == nil"#)

        // Shortcut recorder: ⌃⌥K, then Esc cancels a second recording.
        try await ui.press("Change")
        expect(ui.has("Press keys…"), #"ui.has("Press keys…")"#)
        let combo = try require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .option], timestamp: 0,
                                                  windowNumber: ui.window.windowNumber, context: nil, characters: "k",
                                                  charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40))
        NSApp.sendEvent(combo)
        await ui.pump(0.2)
        expect(settings.hotKey.displayString == "⌃⌥K", #"settings.hotKey.displayString == "⌃⌥K""#)
        try await ui.press("Change")
        let esc = try require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                windowNumber: ui.window.windowNumber, context: nil, characters: "\u{1b}",
                                                charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        NSApp.sendEvent(esc)
        await ui.pump(0.2)
        expect(settings.hotKey.displayString == "⌃⌥K", #"settings.hotKey.displayString == "⌃⌥K""#)
        expect(!ui.has("Press keys…"), #"!ui.has("Press keys…")"#)

        // Your name (the field starts selected, so typing replaces it).
        try await ui.type("Alice Work", intoField: ui.views(of: NSTextField.self).firstIndex { $0.stringValue == "Alice" } ?? 0)
        await ui.submit()
        expect(settings.displayName == "Alice Work", #"settings.displayName == "Alice Work""#)
        expect(a.model.messenger.displayName == "Alice Work", #"a.model.messenger.displayName == "Alice Work""#)

        // Contacts: rename, clear chat, (remove is last).
        try await ui.press("Rename")
        let renameIndex = try require(ui.views(of: NSTextField.self).firstIndex { $0.stringValue == "Bob" })
        try await ui.type("Bobby", intoField: renameIndex)
        await ui.submit()
        try await ui.waitUntil("the rename") { a.model.contact(b.id)?.name == "Bobby" }
        try await ui.press("Clear chat")
        try await ui.press("Delete")
        expect(a.model.store.messages(for: b.id).isEmpty, #"a.model.store.messages(for: b.id).isEmpty"#)

        // App lock with a password, lock, wrong password, right password.
        try await ui.press("Password")
        try await ui.type("1234", intoField: 0)
        let secure = ui.views(of: NSSecureTextField.self)
        expect(secure.count == 2, #"secure.count == 2"#)
        ui.window.makeFirstResponder(secure[1])
        await ui.typeKeys("1234")
        try await ui.press("Save password")
        expect(settings.lockType == .password, #"settings.lockType == .password"#)
        try await ui.press("5 min")
        expect(settings.idleLockMinutes == 5, #"settings.idleLockMinutes == 5"#)
        try await ui.press("Never")
        expect(settings.idleLockMinutes == nil, #"settings.idleLockMinutes == nil"#)

        try await ui.press("Back")
        expect(a.model.screen == .chat, #"a.model.screen == .chat"#)
        try await ui.press("Lock")
        expect(a.model.isLocked, #"a.model.isLocked"#)
        expect(ui.has("Invisible Messenger is locked"), #"ui.has("Invisible Messenger is locked")"#)
        try await ui.type("0000", intoField: 0)
        await ui.submit()
        try await ui.waitUntil("the wrong-password message") { ui.has("Wrong password") }
        expect(a.model.isLocked, #"a.model.isLocked"#)
        try await ui.type("1234", intoField: 0)
        await ui.submit()
        try await ui.waitUntil("unlock") { !a.model.isLocked }

        // Turn the lock off again, then remove the contact.
        try await ui.press("Settings")
        try await ui.press("Nothing")
        expect(settings.lockType == .none, #"settings.lockType == .none"#)
        expect(!a.model.lock.hasPassword, #"!a.model.lock.hasPassword"#)
        try await ui.press("Remove")
        try await ui.press("Remove", last: true)
        try await ui.waitUntil("the contact to be removed") { a.model.contacts.isEmpty }
    }

    func pairingProblemsShowClearMessages() async throws {
        let a = try await TestMac("Alice"), b = try await TestMac("Bob")
        defer { a.stop(); b.stop() }

        // Nobody showing a code.
        b.model.messenger.pairingSearchTimeout = 1
        try await b.ui.press("Add contact")
        try await b.ui.press("Enter code")
        try await b.ui.type("K7Q4M2XP")
        try await b.ui.press("Connect")
        try await b.ui.waitUntil("“not found”") { b.ui.has("No Mac is showing a code on this network.") }
        try await b.ui.press("Try again")
        expect(b.model.pairingTab == .enter, #"b.model.pairingTab == .enter"#)

        // Wrong code.
        try await a.ui.press("Add contact")
        try await a.ui.waitUntil("A's code") { a.code != nil }
        link(a, b)
        try await b.ui.type("AAAA-AAAA")
        try await b.ui.press("Connect")
        try await b.ui.waitUntil("“wrong code”") { b.ui.has("That code didn't work. Check it and try again.") }
        try await b.ui.press("Try again")

        // The emoji don't match on one side → both cancel.
        let code = try require(a.code)
        link(a, b)
        try await b.ui.type(code)
        try await b.ui.press("Connect")
        try await a.ui.waitUntil("both to compare emoji") {
            if case .verify? = a.model.pairingState, case .verify? = b.model.pairingState { return true }
            return false
        }
        try await a.ui.press("They match")
        try await b.ui.press("They don't match")
        try await a.ui.waitUntil("both to show the mismatch") {
            a.ui.has("Pairing was cancelled because the emoji didn't match.")
                && b.ui.has("Pairing was cancelled because the emoji didn't match.")
        }
        expect(a.model.contacts.isEmpty && b.model.contacts.isEmpty, #"a.model.contacts.isEmpty && b.model.contacts.isEmpty"#)

        // Switching tabs: a code only on "Show my code"; Back stops it.
        try await a.ui.press("Try again")
        try await a.ui.waitUntil("a fresh code") { a.code != nil && a.code != code }
        try await a.ui.press("Enter code")
        expect(a.code == nil, #"a.code == nil"#)
        expect(!a.model.messenger.listener.pairingOpen, #"!a.model.messenger.listener.pairingOpen"#)
        try await a.ui.press("Show my code")
        try await a.ui.waitUntil("a code again") { a.code != nil }
        try await a.ui.press("Back")
        expect(a.model.screen == .chat, #"a.model.screen == .chat"#)
        expect(!a.model.messenger.listener.pairingOpen, #"!a.model.messenger.listener.pairingOpen"#)

        // An expired code.
        a.model.messenger.pairingTimeout = 0.5
        try await a.ui.press("Add contact")
        try await a.ui.waitUntil("“expired”") { a.ui.has("The code expired. Make a new one.") }
    }

    func globalShortcutRegisters() async throws {
        let spec = HotKeySpec(keyCode: 111, modifiers: UInt32(0x1000 | 0x0800 | 0x0100), keyLabel: "F12")
        let hotKey = try require(HotKey(spec: spec) {})
        hotKey.unregister()
    }
}
