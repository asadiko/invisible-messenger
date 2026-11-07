import AppKit
import MessengerCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var model: AppModel!

    #if DEBUG
    private var previewPanel: KeyablePanel?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel.bootstrap()
        model.start()
        #if DEBUG
        if ProcessInfo.processInfo.environment["IM_PREVIEW_CHAT"] == "1" { showPreview() }
        #endif
    }

    #if DEBUG
    /// Development aid: the chat in a plain 660×520 panel, for screenshots before the notch panel exists.
    private func showPreview() {
        let panel = KeyablePanel(contentRect: NSRect(x: 200, y: 200, width: 660, height: 520), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: PanelRoot(model: model, chrome: ChatChrome()))
        panel.makeKeyAndOrderFront(nil)
        model.chatVisible = true
        previewPanel = panel
    }
    #endif

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.messenger.stop()
    }

    /// The menu bar is never shown (accessory app), but its key equivalents still work while the app is active.
    static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
