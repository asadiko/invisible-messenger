import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The message box: Return sends, Shift-Return adds a line, pasting or dropping files/images attaches them.
/// Spelling, autocorrect, substitutions and predictions are off (their popups are separate windows, and they mangle code).
struct Composer: NSViewRepresentable {
    var placeholder: String
    var onSend: (String) -> Void
    var onAttach: ([AttachmentDraft]) -> Void
    @Binding var height: CGFloat

    static let minHeight: CGFloat = 22
    static let maxHeight: CGFloat = 120

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let textView = ComposerTextView.make()
        textView.placeholder = placeholder
        textView.delegate = context.coordinator
        textView.onSend = { [weak textView] in
            guard let textView else { return }
            let text = textView.string
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            context.coordinator.parent.onSend(text)
            textView.string = ""
            context.coordinator.updateHeight(textView)
        }
        textView.onAttach = { drafts in context.coordinator.parent.onAttach(drafts) }
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: Self.minHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let textView = scroll.documentView as? ComposerTextView, textView.placeholder != placeholder {
            textView.placeholder = placeholder
            textView.needsDisplay = true
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: Composer

        init(_ parent: Composer) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            updateHeight(textView)
            textView.needsDisplay = true
        }

        func updateHeight(_ textView: NSTextView) {
            guard let manager = textView.layoutManager, let container = textView.textContainer else { return }
            manager.ensureLayout(for: container)
            let used = manager.usedRect(for: container).height + textView.textContainerInset.height * 2
            let clamped = min(max(used, Composer.minHeight), Composer.maxHeight)
            if abs(clamped - parent.height) > 0.5 {
                DispatchQueue.main.async { self.parent.height = clamped }
            }
        }
    }
}

final class ComposerTextView: NSTextView {
    var placeholder = ""
    var onSend: (() -> Void)?
    var onAttach: (([AttachmentDraft]) -> Void)?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }

    /// A TextKit 1 text view (the height calculation uses its layout manager).
    static func make() -> ComposerTextView {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        manager.addTextContainer(container)
        return ComposerTextView(frame: .zero, textContainer: container)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        drawsBackground = false
        font = .systemFont(ofSize: 13)
        textColor = NSColor.white.withAlphaComponent(0.92)
        insertionPointColor = NSColor(Theme.accent)
        textContainerInset = NSSize(width: 0, height: 3)
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticTextCompletionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        smartInsertDeleteEnabled = false
        inlinePredictionType = .no
        writingToolsBehavior = .none
        registerForDraggedTypes([.fileURL, .png, .tiff])
        // Selector-based observers are removed automatically when the view goes away.
        NotificationCenter.default.addObserver(self, selector: #selector(takeFocus), name: .focusComposer, object: nil)
    }

    @objc private func takeFocus() {
        guard let window, window.isVisible else { return }
        window.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if isReturn, !hasMarkedText(), !flags.contains(.shift), !flags.contains(.option) {
            onSend?()
            return
        }
        if event.keyCode == 53, !hasMarkedText() {
            window?.cancelOperation(nil)
            return
        }
        super.keyDown(with: event)
    }

    /// No right-click menu: it would be a separate window outside the hidden panel.
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    override func paste(_ sender: Any?) {
        if let drafts = Self.drafts(from: .general, preferText: true) {
            onAttach?(drafts)
        } else {
            pasteAsPlainText(sender)
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.drafts(from: sender.draggingPasteboard, preferText: false) != nil ? .copy : super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let drafts = Self.drafts(from: sender.draggingPasteboard, preferText: false) {
            onAttach?(drafts)
            return true
        }
        return super.performDragOperation(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: 13),
            .foregroundColor: NSColor.white.withAlphaComponent(0.35),
        ]
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 5), y: textContainerInset.height)
        (placeholder as NSString).draw(at: origin, withAttributes: attributes)
    }

    /// Files win; then plain text (returns nil so it pastes as text); then image data.
    static func drafts(from pasteboard: NSPasteboard, preferText: Bool) -> [AttachmentDraft]? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls.map(AttachmentDraft.file)
        }
        if preferText, pasteboard.string(forType: .string) != nil { return nil }
        if let png = pasteboard.data(forType: .png) { return [.image(png)] }
        if let tiff = pasteboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return [.image(png)]
        }
        return nil
    }
}
