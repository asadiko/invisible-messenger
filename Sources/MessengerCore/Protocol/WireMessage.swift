import Foundation

public let attachmentChunkSize = 262_144
public let maxAttachmentBytes: Int64 = 104_857_600

/// Application messages exchanged inside an encrypted session.
public enum WireMessage: Codable, Equatable, Sendable {
    case text(id: UUID, sentAt: Date, body: String)
    case attachmentStart(id: UUID, sentAt: Date, info: AttachmentInfo)
    case attachmentChunk(id: UUID, index: Int, data: Data)
    case attachmentEnd(id: UUID)
    case ack(id: UUID)
    case pairConfirm(accepted: Bool)
    case ping
    case pong

    public func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> WireMessage {
        try PropertyListDecoder().decode(WireMessage.self, from: data)
    }
}
