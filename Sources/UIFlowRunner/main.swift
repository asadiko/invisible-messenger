// Drives the real Invisible Messenger UI through every flow, the way a person would:
// two copies of the app talk over loopback, buttons are pressed through accessibility,
// text fields are clicked into and typed with real key events.
//
//   scripts/ui-tests.sh
//
// Windows are created off-screen, so nothing takes over the mouse or keyboard.
import AppKit
@testable import InvisibleMessengerKit

nonisolated(unsafe) var failures: [String] = []

struct RequireFailed: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ text: String, file: String = #fileID, line: Int = #line) {
    if !condition() {
        failures.append("\(file):\(line): expected \(text)")
        print("    ✘ \(file):\(line): expected \(text)")
    }
}

func require<T>(_ value: T?, file: String = #fileID, line: Int = #line) throws -> T {
    guard let value else { throw RequireFailed(description: "\(file):\(line): required value was nil") }
    return value
}

final class RunnerDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UIHarness.announceAccessibility()
        Task { @MainActor in
            let flows = UIFlows()
            let all: [(String, () async throws -> Void)] = [
                ("typing the code does not crash", flows.typingTheCodeDoesNotCrash),
                ("pair, chat, code blocks, files and images through the UI", flows.pairChatCodeBlocksFilesAndImagesThroughTheUI),
                ("messages wait while the other Mac is offline", flows.messagesWaitWhileTheOtherMacIsOffline),
                ("every setting works through the UI", flows.everySettingWorksThroughTheUI),
                ("pairing problems show clear messages", flows.pairingProblemsShowClearMessages),
                ("global shortcut registers", flows.globalShortcutRegisters),
            ]
            var failed = 0
            for (name, flow) in all {
                let before = failures.count
                let start = Date()
                do {
                    try await flow()
                } catch {
                    failures.append("\(name): \(error)")
                    print("    ✘ \(error)")
                }
                let ok = failures.count == before
                if !ok { failed += 1 }
                print(String(format: "%@ %@ (%.1f s)", ok ? "✔" : "✘", name, Date().timeIntervalSince(start)))
            }
            print(failed == 0 ? "All \(all.count) UI flows passed." : "\(failed) of \(all.count) UI flows failed.")
            exit(failed == 0 ? 0 : 1)
        }
    }
}

let app = NSApplication.shared
let runner = RunnerDelegate()
app.delegate = runner
app.run()
