import Foundation

public enum FramingError: Error, Equatable, Sendable {
    case frameTooLarge
}

/// Length-prefixed frames: a 4-byte big-endian length followed by the payload.
public enum Framing {
    public static let maxFrameLength = 1_048_576

    public static func encode(_ payload: Data) -> Data {
        var out = Data(capacity: payload.count + 4)
        withUnsafeBytes(of: UInt32(payload.count).bigEndian) { out.append(contentsOf: $0) }
        out.append(payload)
        return out
    }
}

/// Reassembles frames from arbitrarily split or coalesced stream reads.
public struct FrameDecoder: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ bytes: Data) throws -> [Data] {
        buffer.append(bytes)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let start = buffer.startIndex
            let length = buffer[start..<start + 4].reduce(0) { ($0 << 8) | Int($1) }
            guard length <= Framing.maxFrameLength else { throw FramingError.frameTooLarge }
            guard buffer.count >= 4 + length else { break }
            frames.append(Data(buffer[start + 4..<start + 4 + length]))
            buffer = Data(buffer[(start + 4 + length)...])
        }
        return frames
    }
}
