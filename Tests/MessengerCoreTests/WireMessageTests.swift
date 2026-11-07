import CryptoKit
import Foundation
import Testing
@testable import MessengerCore

@Suite struct WireMessageTests {
    static let info = AttachmentInfo(kind: .image, fileName: "a.png", byteCount: 3, sha256: Data([1, 2, 3]))
    static let id = UUID()
    static let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: [
        WireMessage.text(id: id, sentAt: date, body: "hello ✓"),
        .attachmentStart(id: id, sentAt: date, info: info),
        .attachmentChunk(id: id, index: 4, data: Data(count: attachmentChunkSize)),
        .attachmentEnd(id: id),
        .ack(id: id),
        .pairConfirm(accepted: true),
        .ping,
        .pong,
    ])
    func wireRoundTripAllCases(_ message: WireMessage) throws {
        #expect(try WireMessage.decode(message.encoded()) == message)
    }

    @Test func chunkFrameFitsUnderMax() throws {
        let k = SymmetricKey(size: .bits256)
        var channel = SecureChannel(keys: SessionKeys(sendKey: k, receiveKey: k))
        let message = WireMessage.attachmentChunk(id: UUID(), index: Int.max, data: Data(count: attachmentChunkSize))
        let frame = Framing.encode(try channel.seal(message.encoded()))
        #expect(frame.count <= Framing.maxFrameLength + 4)
    }

    @Test func attachmentLimitIs100MB() {
        #expect(maxAttachmentBytes == 104_857_600)
    }
}
