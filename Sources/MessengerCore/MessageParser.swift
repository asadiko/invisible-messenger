import Foundation

/// A piece of a chat message as it should be rendered.
public enum MessageSegment: Equatable, Sendable {
    case text(String)
    case code(language: String?, code: String)
}

/// Splits message text into prose and fenced code blocks (```lang ... ```).
/// Inline markdown such as `code` or **bold** stays inside text segments.
public enum MessageParser {
    public static func segments(_ text: String) -> [MessageSegment] {
        var result: [MessageSegment] = []
        var buffer: [String] = []
        var inCode = false
        var language: String?

        func flush() {
            let joined = buffer.joined(separator: "\n")
            buffer.removeAll()
            if inCode {
                result.append(.code(language: language, code: joined))
            } else {
                let trimmed = joined.trimmingCharacters(in: .newlines)
                if !trimmed.isEmpty { result.append(.text(trimmed)) }
            }
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flush()
                if inCode {
                    inCode = false
                    language = nil
                } else {
                    inCode = true
                    let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    language = lang.isEmpty ? nil : lang
                }
            } else {
                buffer.append(line)
            }
        }
        flush()
        return result
    }
}
