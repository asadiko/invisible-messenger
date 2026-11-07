import Foundation
import Testing
@testable import MessengerCore

@Suite struct EmojiFingerprintTests {
    @Test func emojiAlphabetHas64Distinct() {
        #expect(EmojiFingerprint.alphabet.count == 64)
        #expect(Set(EmojiFingerprint.alphabet).count == 64)
    }

    @Test func emojisFromDigest() {
        let a = EmojiFingerprint.alphabet
        #expect(EmojiFingerprint.emojis(for: Data([0x00, 0x00, 0x00])) == Array(repeating: a[0], count: 4))
        #expect(EmojiFingerprint.emojis(for: Data([0xFF, 0xFF, 0xFF])) == Array(repeating: a[63], count: 4))
        #expect(EmojiFingerprint.emojis(for: Data([0b0000_0100, 0b0010_0000, 0b1100_0100])) == [a[1], a[2], a[3], a[4]])
    }
}
