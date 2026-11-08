import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import InvisibleMessenger
@testable import MessengerCore

@Suite struct AppModelTests {
    func makeModel() throws -> AppModel {
        let suite = "im-tests-\(UUID().uuidString)"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let store = try ChatStore(directory: dir, sealer: DataSealer(key: SymmetricKey(size: .bits256)))
        return AppModel(
            profile: Profile(name: suite),
            settings: AppSettings(defaults: UserDefaults(suiteName: suite)!),
            secrets: InMemorySecretStore(),
            identity: .generate(),
            store: store
        )
    }

    /// Mirrors what Messenger does when a message arrives: store it, bump unread, then announce it.
    func deliverIncoming(_ text: String, from contact: Contact, to model: AppModel) throws {
        let message = ChatMessage(contactID: contact.id, direction: .incoming, body: .text(text), status: .delivered)
        try model.store.append(message)
        var updated = model.store.contact(contact.id)!
        updated.unreadCount += 1
        try model.store.upsert(updated)
        model.messenger.onEvent?(.messageAdded(message))
        model.messenger.onEvent?(.contactsChanged)
    }

    @Test func incomingMessageIsReadWhenChatIsOpen() throws {
        let model = try makeModel()
        let peer = DeviceIdentity.generate()
        let contact = Contact(id: peer.deviceID, name: "Sam", publicKey: peer.publicKeyData)
        try model.store.upsert(contact)
        model.messenger.onEvent?(.contactsChanged)
        model.selectedContactID = contact.id
        model.chatVisible = true
        try deliverIncoming("hi", from: contact, to: model)
        #expect(model.store.contact(contact.id)?.unreadCount == 0)
        #expect(model.totalUnread == 0)
    }

    @Test func incomingMessageStaysUnreadWhenChatIsClosed() throws {
        let model = try makeModel()
        let peer = DeviceIdentity.generate()
        let contact = Contact(id: peer.deviceID, name: "Sam", publicKey: peer.publicKeyData)
        try model.store.upsert(contact)
        model.messenger.onEvent?(.contactsChanged)
        model.chatVisible = false
        try deliverIncoming("hi", from: contact, to: model)
        #expect(model.totalUnread == 1)
        model.chatVisible = true
        #expect(model.totalUnread == 0)
    }

    func modelWithContact() throws -> (AppModel, Contact) {
        let model = try makeModel()
        let peer = DeviceIdentity.generate()
        let contact = Contact(id: peer.deviceID, name: "Sam", publicKey: peer.publicKeyData)
        try model.store.upsert(contact)
        model.messenger.onEvent?(.contactsChanged)
        model.selectedContactID = contact.id
        return (model, contact)
    }

    @Test func longTextIsSentAsFile() throws {
        let (model, contact) = try modelWithContact()
        model.send(text: String(repeating: "log line\n", count: 150_000))
        let sent = model.store.messages(for: contact.id)
        #expect(sent.count == 1)
        guard case .attachment(let info) = sent.first?.body else { Issue.record("expected a file"); return }
        #expect(info.fileName == "Pasted text.txt")
        #expect(info.kind == .file)
    }

    @Test func saveNeverLeavesSaveFolder() throws {
        let (model, contact) = try modelWithContact()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("im-save-\(UUID().uuidString)", isDirectory: true)
        model.settings.saveFolder = folder
        let data = Data("x".utf8)
        let info = AttachmentInfo(kind: .file, fileName: "../../escape.txt", byteCount: 1, sha256: Data(SHA256.hash(data: data)))
        let message = ChatMessage(contactID: contact.id, direction: .incoming, body: .attachment(info), status: .delivered)
        try model.store.writeAttachment(data, messageID: message.id)
        try model.store.append(message)
        let saved = try #require(model.save(message))
        #expect(saved.deletingLastPathComponent().standardizedFileURL.path == folder.standardizedFileURL.path)
        #expect(saved.lastPathComponent == "escape.txt")
    }

    @Test func lockingClosesImageViewer() throws {
        let (model, contact) = try modelWithContact()
        let message = ChatMessage(contactID: contact.id, direction: .incoming, body: .text("x"), status: .delivered)
        ImageViewerController.shared.show(image: NSImage(size: NSSize(width: 10, height: 10)), message: message, model: model)
        #expect(ImageViewerController.shared.isOpen)
        model.isLocked = true
        #expect(!ImageViewerController.shared.isOpen)
    }

    /// The chat UI exists twice (notch panel + hidden floating window). Merely drawing the pairing
    /// screen in a hidden window must never start or replace a pairing.
    @Test func hiddenPairingScreenDoesNotStartPairing() throws {
        let (model, _) = try modelWithContact()
        model.screen = .pairing
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 520), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: PanelRoot(model: model, chrome: ChatChrome()))
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        #expect(model.pairingState == nil)
        #expect(!model.messenger.listener.pairingOpen)
    }

    func code(_ model: AppModel) -> String? {
        if case .showingCode(let code, _)? = model.pairingState { return code }
        return nil
    }

    @Test func openingAddContactShowsACode() throws {
        let (model, _) = try modelWithContact()
        model.openPairing()
        #expect(model.screen == .pairing)
        #expect(model.pairingTab == .show)
        #expect(code(model) != nil)
        #expect(model.messenger.listener.pairingOpen)
    }

    /// The reported bug: on "Enter code" a (different) code kept appearing.
    @Test func enterCodeTabShowsNoCodeEvenWithTheHiddenWindowDrawn() throws {
        let (model, _) = try modelWithContact()
        let hidden = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 520), styleMask: [.borderless], backing: .buffered, defer: false)
        hidden.contentView = NSHostingView(rootView: PanelRoot(model: model, chrome: ChatChrome()))
        model.openPairing()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        model.selectPairingTab(.enter)
        hidden.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        #expect(model.pairingTab == .enter)
        #expect(model.pairingState == nil)
        #expect(!model.messenger.listener.pairingOpen)
    }

    @Test func backToShowMakesAFreshCode() throws {
        let (model, _) = try modelWithContact()
        model.openPairing()
        let first = code(model)
        model.selectPairingTab(.enter)
        model.selectPairingTab(.show)
        #expect(code(model) != nil)
        #expect(code(model) != first)
    }

    @Test func leavingPairingStopsHosting() throws {
        let (model, _) = try modelWithContact()
        model.openPairing()
        model.closePairing()
        #expect(model.screen == .chat)
        #expect(model.pairingState == nil)
        #expect(!model.messenger.listener.pairingOpen)
    }
}

