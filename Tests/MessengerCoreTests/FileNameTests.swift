import Testing
@testable import MessengerCore

@Suite struct FileNameTests {
    @Test(arguments: [
        ("../../Library/LaunchAgents/evil.plist", "evil.plist"),
        ("report.pdf", "report.pdf"),
        ("a/b:c.txt", "b_c.txt"),
        (".hidden", "hidden"),
        ("..", "file"),
        ("", "file"),
        ("/", "file"),
        ("...x", "x"),
    ])
    func safeFileName(_ input: String, _ expected: String) {
        #expect(AttachmentInfo.safeFileName(input) == expected)
    }
}
