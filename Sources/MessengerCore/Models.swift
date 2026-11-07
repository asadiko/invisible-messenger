import Foundation

/// Stable identifier of a Mac, derived from its identity public key (16 lowercase hex chars).
public struct DeviceID: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func < (lhs: DeviceID, rhs: DeviceID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum AttachmentKind: String, Codable, Sendable {
    case image
    case file
}

public struct AttachmentInfo: Codable, Hashable, Sendable {
    public var kind: AttachmentKind
    public var fileName: String
    public var byteCount: Int64
    public var sha256: Data

    public init(kind: AttachmentKind, fileName: String, byteCount: Int64, sha256: Data) {
        self.kind = kind
        self.fileName = fileName
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    /// A file name that is safe to create inside a folder: no path parts, no ':' and no leading dots.
    /// Peers choose attachment names, so they must never be able to point outside the save folder.
    public static func safeFileName(_ raw: String) -> String {
        let last = raw.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? ""
        var name = last.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "\0", with: "")
        while name.hasPrefix(".") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "file" : String(name.prefix(200))
    }
}

public enum MessageBody: Codable, Hashable, Sendable {
    case text(String)
    case attachment(AttachmentInfo)
}

public enum MessageDirection: String, Codable, Sendable {
    case outgoing
    case incoming
}

public enum MessageStatus: String, Codable, Sendable {
    case sending
    case sent
    case delivered
    case failed
}

public struct ChatMessage: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var contactID: DeviceID
    public var direction: MessageDirection
    public var sentAt: Date
    public var body: MessageBody
    public var status: MessageStatus

    public init(
        id: UUID = UUID(),
        contactID: DeviceID,
        direction: MessageDirection,
        sentAt: Date = Date(),
        body: MessageBody,
        status: MessageStatus
    ) {
        self.id = id
        self.contactID = contactID
        self.direction = direction
        self.sentAt = sentAt
        self.body = body
        self.status = status
    }
}

public struct Contact: Codable, Identifiable, Hashable, Sendable {
    public var id: DeviceID
    public var name: String
    public var publicKey: Data
    public var pairedAt: Date
    public var unreadCount: Int

    public init(id: DeviceID, name: String, publicKey: Data, pairedAt: Date = Date(), unreadCount: Int = 0) {
        self.id = id
        self.name = name
        self.publicKey = publicKey
        self.pairedAt = pairedAt
        self.unreadCount = unreadCount
    }
}
