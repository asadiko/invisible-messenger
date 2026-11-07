import AppKit
import MessengerCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var model: AppModel!
    private(set) var notch: NotchController!
    private(set) var floating: FloatingController!
    private var hotKey: HotKey?
    private var settings: AppSettings { model.settings }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel.bootstrap()
        model.start()
        notch = NotchController(model: model, settings: settings)
        floating = FloatingController(model: model, settings: settings)
        floating.onVisibilityChange = { [weak self] visible in self?.notch.floatingHidden = !visible }
        notch.onIndicatorClick = { [weak self] in self?.floating.show() }
        applyAppearance()
        observeAppearance()
        registerHotKey()
        observeHotKey()
        #if DEBUG
        if ProcessInfo.processInfo.environment["IM_OPEN_ON_LAUNCH"] == "1" {
            settings.appearance == .notch ? notch.openPinned() : floating.show(focus: false)
        }
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showChat()
        return false
    }

    func showChat() {
        settings.appearance == .notch ? notch.open() : floating.show()
    }

    func toggleChat() {
        settings.appearance == .notch ? notch.toggle() : floating.toggle()
    }

    /// Notch mode: the notch is the chat. Floating mode: the mini window is the chat and the notch only glows.
    private func applyAppearance() {
        switch settings.appearance {
        case .notch:
            floating.hide()
            notch.mode = .full
        case .floating:
            notch.mode = .indicatorOnly
            floating.show(focus: false)
        }
    }

    private func observeAppearance() {
        withObservationTracking {
            _ = settings.appearance
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.applyAppearance()
                self?.observeAppearance()
            }
        }
    }

    private func registerHotKey() {
        hotKey?.unregister()
        hotKey = HotKey(spec: settings.hotKey) { [weak self] in self?.toggleChat() }
        if hotKey == nil {
            model.showNotice("\(settings.hotKey.displayString) is used by another app. Pick a different shortcut in Settings.", seconds: 8)
        }
    }

    private func observeHotKey() {
        withObservationTracking {
            _ = settings.hotKey
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.registerHotKey()
                self?.observeHotKey()
            }
        }
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
