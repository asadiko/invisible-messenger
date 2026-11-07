import Testing
@testable import MessengerCore

@Suite struct MessageParserTests {
    @Test func plainText() {
        #expect(MessageParser.segments("hi there") == [.text("hi there")])
    }

    @Test func fencedWithLanguage() {
        let input = "look:\n```sql\nSELECT 1;\n```\nok"
        #expect(MessageParser.segments(input) == [
            .text("look:"),
            .code(language: "sql", code: "SELECT 1;"),
            .text("ok"),
        ])
    }

    @Test func fencedWithoutLanguage() {
        #expect(MessageParser.segments("```\na\nb\n```") == [.code(language: nil, code: "a\nb")])
    }

    @Test func unterminatedFenceIsCodeToEnd() {
        #expect(MessageParser.segments("x\n```py\nprint(1)") == [
            .text("x"),
            .code(language: "py", code: "print(1)"),
        ])
    }

    @Test func inlineBackticksStayText() {
        #expect(MessageParser.segments("use `ls` now") == [.text("use `ls` now")])
    }

    @Test func emptyTextSegmentsDropped() {
        #expect(MessageParser.segments("```\nA\n```\n\n```\nB\n```") == [
            .code(language: nil, code: "A"),
            .code(language: nil, code: "B"),
        ])
    }
}
