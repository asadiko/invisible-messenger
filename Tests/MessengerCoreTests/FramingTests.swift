import Foundation
import Testing
@testable import MessengerCore

@Suite struct FramingTests {
    @Test func decoderHandlesSplitAndCoalescedFrames() throws {
        let payloads = [Data("a".utf8), Data(repeating: 7, count: 70_000), Data()]
        let stream = payloads.map(Framing.encode).reduce(Data(), +)

        var byteByByte = FrameDecoder()
        var got: [Data] = []
        for byte in stream { got += try byteByByte.append(Data([byte])) }
        #expect(got == payloads)

        var whole = FrameDecoder()
        #expect(try whole.append(stream) == payloads)
    }

    @Test func decoderRejectsOversize() {
        var decoder = FrameDecoder()
        var header = Data()
        withUnsafeBytes(of: UInt32(Framing.maxFrameLength + 1).bigEndian) { header.append(contentsOf: $0) }
        #expect(throws: FramingError.frameTooLarge) { try decoder.append(header) }
    }
}
