import AppKit
import SwiftUI

/// The small, semi-transparent chat window that stays on top of other apps.
final class FloatingController {
    var onVisibilityChange: ((Bool) -> Void)?

    private let model: AppModel
    private let settings: AppSettings
    private let panel: KeyablePanel

    var isVisible: Bool { panel.isVisible }

    init(model: AppModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 340, height: 480)
        let frame = NSRect(x: screen.maxX - size.width - 24, y: screen.maxY - size.height - 24, width: size.width, height: size.height)
        panel = KeyablePanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.titlebarSeparatorStyle = .none
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.minSize = NSSize(width: 300, height: 360)
        panel.backgroundColor = NSColor(Theme.background)
        panel.alphaValue = settings.floatingOpacity
        panel.setFrameAutosaveName("FloatingChat")
        panel.onEscape = { [weak self] in self?.hide() }
        panel.contentView = NSHostingView(rootView: PanelContent(model: model, chrome: ChatChrome(
            onClose: { [weak self] in self?.hide() },
            onTogglePin: nil,
            isPinned: false,
            topInset: 4
        )))
        observeOpacity()
    }

    func show(focus: Bool = true) {
        HiddenWindowGuard.protect(panel)
        if focus {
            panel.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .focusComposer, object: nil)
        } else {
            panel.orderFrontRegardless()
        }
        model.chatVisible = true
        onVisibilityChange?(true)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        model.chatVisible = false
        onVisibilityChange?(false)
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    private func observeOpacity() {
        withObservationTracking {
            panel.alphaValue = settings.floatingOpacity
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.observeOpacity() }
        }
    }
}
