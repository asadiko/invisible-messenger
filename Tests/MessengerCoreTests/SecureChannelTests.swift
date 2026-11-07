import CryptoKit
import Foundation
import Testing
@testable import MessengerCore

@Suite struct SecureChannelTests {
    @Test func channelRejectsReplayAndTamper() throws {
        let k1 = SymmetricKey(size: .bits256), k2 = SymmetricKey(size: .bits256)
        var a = SecureChannel(keys: SessionKeys(sendKey: k1, receiveKey: k2))
        var b = SecureChannel(keys: SessionKeys(sendKey: k2, receiveKey: k1))
        let first = try a.seal(Data("one".utf8))
        #expect(try b.open(first) == Data("one".utf8))
        #expect(throws: HandshakeError.authenticationFailed) { try b.open(first) }
        let second = try a.seal(Data("two".utf8))
        var tampered = second
        tampered[tampered.startIndex] ^= 0x01
        #expect(throws: HandshakeError.authenticationFailed) { try b.open(tampered) }
        #expect(try b.open(second) == Data("two".utf8))
    }
}
