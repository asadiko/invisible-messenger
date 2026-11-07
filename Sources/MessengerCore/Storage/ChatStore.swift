import Foundation

/// Contacts, chat history and attachments, each file sealed with `DataSealer`.
///
/// Layout: `contacts.bin`, `chats/<deviceID>.bin`, `attachments/<uuid>.bin`.
@MainActor
public final class ChatStore {
    public let directory: URL
    private let sealer: DataSealer
    private var chats: [DeviceID: [ChatMessage]] = [:]
    public private(set) var contacts: [Contact] = []

    private var contactsURL: URL { directory.appendingPathComponent("contacts.bin") }
    private var chatsDir: URL { directory.appendingPathComponent("chats", isDirectory: true) }
    private var attachmentsDir: URL { directory.appendingPathComponent("attachments", isDirectory: true) }

    public init(directory: URL, sealer: DataSealer) throws {
        self.directory = directory
        self.sealer = sealer
        let fm = FileManager.default
        try fm.createDirectory(at: chatsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        if fm.fileExists(atPath: contactsURL.path) {
            contacts = try read([Contact].self, from: contactsURL)
        }
    }

    // MARK: Contacts

    public func contact(_ id: DeviceID) -> Contact? {
        contacts.first { $0.id == id }
    }

    public func upsert(_ contact: Contact) throws {
        if let i = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[i] = contact
        } else {
            contacts.append(contact)
        }
        try write(contacts, to: contactsURL)
    }

    public func removeContact(_ id: DeviceID) throws {
        for message in messages(for: id) {
            try? FileManager.default.removeItem(at: attachmentURL(message.id))
        }
        try? FileManager.default.removeItem(at: chatURL(id))
        chats[id] = nil
        contacts.removeAll { $0.id == id }
        try write(contacts, to: contactsURL)
    }

    // MARK: Messages

    public func messages(for id: DeviceID) -> [ChatMessage] {
        if let cached = chats[id] { return cached }
        let url = chatURL(id)
        var loaded: [ChatMessage] = []
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                loaded = try read([ChatMessage].self, from: url)
            } catch {
                let aside = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
                try? FileManager.default.moveItem(at: url, to: aside)
            }
        }
        loaded.sort { $0.sentAt < $1.sentAt }
        chats[id] = loaded
        return loaded
    }

    /// Returns false (and changes nothing) if a message with the same id already exists.
    @discardableResult
    public func append(_ message: ChatMessage) throws -> Bool {
        var list = messages(for: message.contactID)
        guard !list.contains(where: { $0.id == message.id }) else { return false }
        let index = list.lastIndex { $0.sentAt <= message.sentAt }.map { $0 + 1 } ?? 0
        list.insert(message, at: index)
        try save(list, for: message.contactID)
        return true
    }

    public func message(_ id: UUID, contact: DeviceID) -> ChatMessage? {
        messages(for: contact).first { $0.id == id }
    }

    public func update(_ message: ChatMessage) throws {
        var list = messages(for: message.contactID)
        guard let i = list.firstIndex(where: { $0.id == message.id }) else { return }
        list[i] = message
        try save(list, for: message.contactID)
    }

    public func deleteMessage(_ id: UUID, contact: DeviceID) throws {
        var list = messages(for: contact)
        list.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: attachmentURL(id))
        try save(list, for: contact)
    }

    public func clearChat(_ id: DeviceID) throws {
        for message in messages(for: id) {
            try? FileManager.default.removeItem(at: attachmentURL(message.id))
        }
        try save([], for: id)
    }

    public func pendingOutgoing(for id: DeviceID) -> [ChatMessage] {
        messages(for: id).filter { $0.direction == .outgoing && $0.status == .sending }
    }

    // MARK: Attachments

    public func writeAttachment(_ data: Data, messageID: UUID) throws {
        try sealer.seal(data).write(to: attachmentURL(messageID), options: .atomic)
    }

    public func readAttachment(messageID: UUID) throws -> Data {
        try sealer.open(Data(contentsOf: attachmentURL(messageID)))
    }

    public func hasAttachment(messageID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: attachmentURL(messageID).path)
    }

    public static func wipe(directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: Private

    private func chatURL(_ id: DeviceID) -> URL { chatsDir.appendingPathComponent("\(id.rawValue).bin") }
    private func attachmentURL(_ id: UUID) -> URL { attachmentsDir.appendingPathComponent("\(id.uuidString).bin") }

    private func save(_ list: [ChatMessage], for id: DeviceID) throws {
        chats[id] = list
        try write(list, to: chatURL(id))
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try sealer.seal(encoder.encode(value)).write(to: url, options: .atomic)
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try PropertyListDecoder().decode(type, from: sealer.open(Data(contentsOf: url)))
    }
}
