import AppKit
import MessengerCore
import SwiftUI

/// Full-size view of a received or sent image, in its own hidden panel.
final class ImageViewerController {
    static let shared = ImageViewerController()
    private var panel: KeyablePanel?

    func show(image: NSImage, message: ChatMessage, model: AppModel) {
        close()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let maxSize = NSSize(width: screen.width * 0.7, height: screen.height * 0.7)
        let scale = min(1, maxSize.width / max(image.size.width, 1), maxSize.height / max(image.size.height, 1))
        let size = NSSize(width: max(image.size.width * scale, 320), height: max(image.size.height * scale, 200) + 44)
        let frame = NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)

        let panel = KeyablePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.onEscape = { [weak self] in self?.close() }
        panel.contentView = NSHostingView(rootView: ImageViewer(
            image: image,
            onSave: { model.save(message) },
            onClose: { [weak self] in self?.close() }
        ))
        HiddenWindowGuard.protect(panel)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct ImageViewer: View {
    let image: NSImage
    let onSave: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HiddenBadge()
                Spacer()
                Button("Save", action: onSave).buttonStyle(.plain).foregroundStyle(Theme.accent)
                IconButton(systemName: "xmark", action: onClose)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}
