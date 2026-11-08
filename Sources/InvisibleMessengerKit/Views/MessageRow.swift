import AppKit
import MessengerCore
import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    let model: AppModel
    @State private var hovering = false

    private var outgoing: Bool { message.direction == .outgoing }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if outgoing { Spacer(minLength: 40) }
            if outgoing && hovering { actions }
            VStack(alignment: outgoing ? .trailing : .leading, spacing: 3) {
                content
                if let fraction = model.progress[message.id] {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(Theme.accent)
                        .frame(width: 140)
                }
                footer
            }
            if !outgoing && hovering { actions }
            if !outgoing { Spacer(minLength: 40) }
        }
        .onHover { hovering = $0 }
        // The hover buttons only exist while the pointer is over the row; VoiceOver gets them as actions.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Message: \(preview)")
        .accessibilityActions {
            if case .text(let text) = message.body {
                Button("Copy message") { copyToPasteboard(text) }
            }
            Button("Delete message") { model.delete(message) }
        }
    }

    private var preview: String {
        switch message.body {
        case .text(let text): text
        case .attachment(let info): info.fileName
        }
    }

    @ViewBuilder private var content: some View {
        switch message.body {
        case .text(let text):
            VStack(alignment: outgoing ? .trailing : .leading, spacing: 5) {
                ForEach(Array(MessageParser.segments(text).enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let prose): TextBubble(text: prose, outgoing: outgoing)
                    case .code(let language, let code): CodeBlockView(language: language, code: code)
                    }
                }
            }
        case .attachment(let info) where info.kind == .image:
            ImageAttachmentView(message: message, info: info, model: model)
        case .attachment(let info):
            FileAttachmentView(message: message, info: info, model: model)
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if hovering {
                Text(message.sentAt, style: .time)
            }
            if outgoing { Text(statusGlyph) }
        }
        .font(.system(size: 10))
        .foregroundStyle(message.status == .failed ? Color.red : Theme.textSecondary)
        .frame(height: 12)
    }

    private var statusGlyph: String {
        switch message.status {
        case .sending: "◷"
        case .sent: "✓"
        case .delivered: "✓✓"
        case .failed: "!"
        }
    }

    private var actions: some View {
        HStack(spacing: 0) {
            if case .text(let text) = message.body {
                IconButton(systemName: "doc.on.doc", label: "Copy message") { copyToPasteboard(text) }
            }
            IconButton(systemName: "trash", label: "Delete message") { model.delete(message) }
        }
        .padding(.bottom, 14)
    }
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

struct TextBubble: View {
    let text: String
    let outgoing: Bool

    var body: some View {
        Text(Self.render(text))
            .font(.system(size: 13))
            .foregroundStyle(outgoing ? Color.white : Theme.textPrimary)
            .tint(outgoing ? Color.white : Theme.accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(outgoing ? Theme.bubbleOutgoing : Theme.bubbleIncoming, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
    }

    static func render(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Button {
                    copyToPasteboard(code)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(copied ? Theme.online : Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 7)
            .padding(.bottom, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.codeText)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 9)
            }
        }
        .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.08)))
        .frame(maxWidth: 520, alignment: .leading)
    }
}

struct ImageAttachmentView: View {
    let message: ChatMessage
    let info: AttachmentInfo
    let model: AppModel
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 220, maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onTapGesture { ImageViewerController.shared.show(image: image, message: message, model: model) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Open image \(info.fileName)")
                    .accessibilityAction { ImageViewerController.shared.show(image: image, message: message, model: model) }
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.surface)
                    .frame(width: 160, height: 100)
                    .overlay(Image(systemName: "photo").foregroundStyle(Theme.textSecondary))
            }
        }
        .task(id: message.id) {
            if let data = model.attachmentData(message) { image = NSImage(data: data) }
        }
    }
}

struct FileAttachmentView: View {
    let message: ChatMessage
    let info: AttachmentInfo
    let model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.fileName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ByteCountFormatter.string(fromByteCount: info.byteCount, countStyle: .file))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            if model.store.hasAttachment(messageID: message.id) {
                Button("Save") { model.save(message) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: 280, alignment: .leading)
        .background(Theme.bubbleIncoming, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
