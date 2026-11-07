import CryptoKit
import Foundation
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
}
