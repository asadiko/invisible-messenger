import AppKit
import MessengerCore
import SwiftUI

/// The window that lives in the notch: closed (looks like the notch, glows on unread), peek on hover,
/// and the chat panel when open. In floating mode it is only an unread indicator.
final class NotchController {
    enum Mode {
        case full, indicatorOnly
    }

    static let glowMargin: CGFloat = 16
    static let peekExtraWidth: CGFloat = 70
    static let peekExtraHeight: CGFloat = 30

    var mode: Mode = .full { didSet { if mode != oldValue { modeChanged() } } }
    /// In indicator mode: whether the floating chat is currently hidden (the indicator only shows then).
    var floatingHidden = true { didSet { refreshVisibility() } }
    var onIndicatorClick: (() -> Void)?

    private let model: AppModel
    private let settings: AppSettings
    private let state = NotchViewState()
    private let panel: KeyablePanel
    private var screen: NSScreen?
    private var metrics = NotchMetrics(rect: .zero, hasHardwareNotch: false)
    private var clickMonitor: Any?
    private var hoverView: HoverTrackingView!
    private var exitTask: Task<Void, Never>?
    private var resizeStartSize: CGSize = .zero
    private var resizeStartMouse: NSPoint = .zero
    private var liveSize: CGSize?

    var isOpen: Bool { state.phase == .open }

    init(model: AppModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        panel = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.acceptsKey = false
        panel.onEscape = { [weak self] in self?.close() }

        let actions = NotchActions(
            open: { [weak self] in self?.handleClick() },
            close: { [weak self] in self?.close() },
            togglePin: { [weak self] in self?.state.pinned.toggle() },
            resizeBegan: { [weak self] in self?.beginResize() },
            resizeChanged: { [weak self] edge in self?.resize(edge) },
            resizeEnded: { [weak self] in self?.endResize() }
        )
        let hosting = NSHostingView(rootView: NotchRootView(model: model, state: state, actions: actions))
        hosting.sizingOptions = []
        hoverView = HoverTrackingView()
        hoverView.onEnter = { [weak self] in self?.mouseEntered() }
        hoverView.onExit = { [weak self] in self?.mouseExited() }
        hoverView.addSubview(hosting)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: hoverView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: hoverView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: hoverView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: hoverView.bottomAnchor),
        ])
        panel.contentView = hoverView

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        }
        observeModel()
        relayout()
        refreshVisibility()
    }

    // MARK: Public

    /// Opens the chat. `focus` gives the message box the keyboard (hot key, clicking the notch).
    func open(focus: Bool = true) {
        guard mode == .full else { return }
        exitTask?.cancel()
        state.phase = .open
        model.chatVisible = true
        applyFrame(animated: true)
        panel.acceptsKey = true
        if focus {
            panel.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .focusComposer, object: nil)
        } else {
            panel.orderFrontRegardless()
        }
        startClickMonitor()
    }

    func close() {
        guard state.phase != .closed else { return }
        state.phase = .closed
        model.chatVisible = false
        stopClickMonitor()
        panel.acceptsKey = false
        // Ordering out hands keyboard focus back to the app you were using.
        panel.orderOut(nil)
        applyFrame(animated: false)
        refreshVisibility()
    }

    func toggle() {
        isOpen ? close() : open()
    }

    // MARK: Layout

    private func relayout() {
        let target = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        guard let target else { return }
        screen = target
        let menuBar = target.frame.maxY - target.visibleFrame.maxY
        metrics = PanelGeometry.notchMetrics(
            screenFrame: target.frame,
            safeAreaTop: target.safeAreaInsets.top,
            auxiliaryLeft: target.auxiliaryTopLeftArea,
            auxiliaryRight: target.auxiliaryTopRightArea,
            menuBarHeight: menuBar > 0 ? menuBar : NSStatusBar.system.thickness
        )
        state.notchSize = metrics.rect.size
        state.hasHardwareNotch = metrics.hasHardwareNotch
        applyFrame(animated: false)
    }

    private var panelSize: CGSize {
        let screenSize = screen?.frame.size ?? CGSize(width: 1440, height: 900)
        let size = liveSize ?? settings.panelSize ?? PanelGeometry.defaultSize(notchWidth: metrics.rect.width)
        return PanelGeometry.clamp(size, screenSize: screenSize)
    }

    private func frame(for phase: NotchPhase) -> NSRect {
        guard let screen else { return .zero }
        let notch = metrics.rect
        switch phase {
        case .closed:
            let margin = model.totalUnread > 0 ? Self.glowMargin : 0
            state.glowMargin = margin
            return NSRect(x: notch.minX - margin, y: notch.minY - margin, width: notch.width + margin * 2, height: notch.height + margin)
        case .peek:
            let width = notch.width + Self.peekExtraWidth * 2
            let height = notch.height + Self.peekExtraHeight
            return NSRect(x: notch.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        case .open:
            var rect = PanelGeometry.panelFrame(size: panelSize, notch: notch, screenFrame: screen.frame)
            rect.origin.y -= NotchRootView.closeTabHeight
            rect.size.height += NotchRootView.closeTabHeight
            return rect
        }
    }

    private func applyFrame(animated: Bool) {
        let target = frame(for: state.phase)
        guard target != .zero else { return }
        if animated && panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }

    private func refreshVisibility() {
        let shouldShow: Bool = switch mode {
        case .full: true
        case .indicatorOnly: floatingHidden && model.totalUnread > 0
        }
        if shouldShow {
            applyFrame(animated: false)
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    private func modeChanged() {
        if mode == .indicatorOnly { close() }
        refreshVisibility()
    }

    /// Re-applies the frame/visibility whenever unread counts or the lock change.
    private func observeModel() {
        withObservationTracking {
            _ = model.totalUnread
            _ = model.isLocked
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.state.phase == .closed { self.applyFrame(animated: false) }
                self.refreshVisibility()
                self.observeModel()
            }
        }
    }

    // MARK: Interaction

    private func handleClick() {
        switch mode {
        case .full: open()
        case .indicatorOnly: onIndicatorClick?()
        }
    }

    private func mouseEntered() {
        exitTask?.cancel()
        guard mode == .full, state.phase == .closed else { return }
        state.phase = .peek
        applyFrame(animated: true)
    }

    private func mouseExited() {
        guard state.phase == .peek else { return }
        exitTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled, self.state.phase == .peek else { return }
            self.state.phase = .closed
            self.applyFrame(animated: true)
        }
    }

    private func startClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isOpen, !self.state.pinned else { return }
                self.close()
            }
        }
    }

    private func stopClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    // MARK: Resize

    private func beginResize() {
        resizeStartSize = panelSize
        resizeStartMouse = NSEvent.mouseLocation
    }

    private func resize(_ edge: ResizeEdge) {
        guard let screen else { return }
        let mouse = NSEvent.mouseLocation
        let delta = CGSize(width: mouse.x - resizeStartMouse.x, height: mouse.y - resizeStartMouse.y)
        liveSize = PanelGeometry.resized(resizeStartSize, edge: edge, delta: delta, screenSize: screen.frame.size)
        applyFrame(animated: false)
    }

    private func endResize() {
        if let liveSize { settings.panelSize = liveSize }
        liveSize = nil
    }

    /// Development / capture-check aid: open and stay open regardless of outside clicks.
    func openPinned() {
        state.pinned = true
        open(focus: false)
    }

    /// Called from Settings › Reset panel size.
    func resetSize() {
        settings.panelSize = nil
        if isOpen { applyFrame(animated: true) }
    }
}

/// Reports the mouse entering and leaving the window, even while the app is not active.
final class HoverTrackingView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}
