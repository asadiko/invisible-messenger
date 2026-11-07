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
        runDebugAutomation()
        #endif
    }

    #if DEBUG
    /// Development aid for driving two copies of the app without touching the mouse or keyboard:
    /// IM_DEBUG_PAIR=host (writes the code to IM_DEBUG_PAIR_FILE) or join:<code>,
    /// IM_DEBUG_AUTOCONFIRM=1 (answers "They match" after 2 s), IM_DEBUG_SEND=<text> (sends once online).
    private var debugTimer: Timer?

    private func runDebugAutomation() {
        let env = ProcessInfo.processInfo.environment
        if let pair = env["IM_DEBUG_PAIR"] {
            model.screen = .pairing
            if pair == "host" {
                model.startHosting()
                if case .showingCode(let code, _)? = model.pairingState, let file = env["IM_DEBUG_PAIR_FILE"] {
                    try? code.write(toFile: file, atomically: true, encoding: .utf8)
                }
            } else if pair.hasPrefix("join:") {
                model.join(code: String(pair.dropFirst(5)))
            }
        }
        var confirmAt: Date?
        var sent = false
        debugTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let model = self.model else { return }
                if env["IM_DEBUG_AUTOCONFIRM"] == "1", case .verify? = model.pairingState {
                    if confirmAt == nil { confirmAt = Date().addingTimeInterval(2) }
                    if let at = confirmAt, Date() >= at { model.pairing?.confirm(true); confirmAt = nil }
                }
                if let text = env["IM_DEBUG_SEND"], !sent, let contact = model.contacts.first, model.isOnline(contact.id) {
                    sent = true
                    model.screen = .chat
                    model.selectedContactID = contact.id
                    model.send(text: text)
                }
            }
        }
    }
    #endif

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
