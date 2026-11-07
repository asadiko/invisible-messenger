import Foundation

/// Turns a digest into four emoji both people can compare to confirm they paired with each other.
public enum EmojiFingerprint {
    /// 64 distinct, easy-to-name emoji. The order is part of the protocol: never reorder.
    public static let alphabet: [String] = [
        "🐶", "🐱", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁",
        "🐮", "🐷", "🐸", "🐵", "🐔", "🐧", "🦆", "🦉",
        "🐴", "🦄", "🐝", "🐞", "🦋", "🐢", "🐍", "🐙",
        "🦀", "🐠", "🐬", "🐳", "🦈", "🐘", "🦒", "🌵",
        "🌲", "🌴", "🍀", "🍁", "🍄", "🌻", "🌙", "⭐",
        "🔥", "🌈", "⚡", "🍎", "🍌", "🍇", "🍓", "🍒",
        "🍍", "🥝", "🍕", "🍩", "🎈", "🎁", "🎸", "🚀",
        "⚓", "🔑", "🔔", "📌", "💎", "⏰", "🎲", "🧩",
    ]

    /// The first 24 bits of `digest`, six bits per emoji, most significant bits first.
    public static func emojis(for digest: Data) -> [String] {
        let bytes = Array(digest.prefix(3)) + Array(repeating: 0, count: max(0, 3 - digest.count))
        let bits = (UInt32(bytes[0]) << 16) | (UInt32(bytes[1]) << 8) | UInt32(bytes[2])
        return (0..<4).map { i in
            let shift = UInt32(18 - 6 * i)
            return alphabet[Int((bits >> shift) & 0x3F)]
        }
    }
}
