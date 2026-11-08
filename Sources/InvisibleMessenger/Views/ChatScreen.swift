import AppKit
import MessengerCore
import SwiftUI

/// Window-specific controls the chat shows in its header.
struct ChatChrome {
    var onClose: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var isPinned = false
    /// Space kept clear at the top (the hardware notch / menu bar in notch mode).
    var topInset: CGFloat = 0
}

/// Everything shown inside a chat panel: the chat, or the pairing / settings screens.
struct PanelRoot: View {
    let model: AppModel
    var chrome: ChatChrome

    var body: some View {
        Group {
            switch model.screen {
            case .chat: ChatScreen(model: model, chrome: chrome)
            case .pairing: PairingView(model: model, chrome: chrome)
            case .settings: SettingsView(model: model, chrome: chrome)
            }
        }
        .environment(\.colorScheme, .dark)
        .focusEffectDisabled()
        .onChange(of: model.screen) { _, _ in model.screenChanged() }
    }
}

struct ChatScreen: View {
    let model: AppModel
    var chrome: ChatChrome
    @State private var composerHeight = Composer.minHeight
    @State private var width: CGFloat = 660

    /// Narrow windows (the floating mini window) always use tabs; the side list would leave no room to chat.
    private var layout: ChatLayout { width < 460 ? .tabs : model.settings.layout }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, chrome.topInset)
            Rectangle().fill(Theme.separator).frame(height: 1)
            if model.contacts.isEmpty {
                emptyState
            } else if layout == .sidebar {
                HStack(spacing: 0) {
                    ContactList(model: model)
                    Rectangle().fill(Theme.separator).frame(width: 1)
                    conversation
                }
            } else {
                conversation
            }
        }
        .background(Theme.background)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if layout == .tabs && !model.contacts.isEmpty {
                ContactTabs(model: model)
            } else if let contact = model.selectedContact {
                Text(contact.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                PresenceDot(online: model.isOnline(contact.id))
                Text(model.isOnline(contact.id) ? "connected" : "offline")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            } else {
                Text("Invisible Messenger")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer(minLength: 4)
            HeaderButtons(model: model, chrome: chrome)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            if let contact = model.selectedContact, !model.isOnline(contact.id) {
                Text("\(contact.name) is offline · messages will be sent when they're back")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Theme.surface.opacity(0.6))
            }
            MessageList(model: model)
            if let notice = model.notice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.surfaceHigh, in: Capsule())
                    .padding(.bottom, 4)
                    .transition(.opacity)
            }
            composerBar
        }
    }

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            IconButton(systemName: "paperclip", tint: Theme.textSecondary) { pickFiles() }
            Composer(
                placeholder: "Message \(model.selectedContact?.name ?? "")…",
                onSend: { model.send(text: $0) },
                onAttach: { model.attach($0) },
                height: $composerHeight
            )
            .frame(height: composerHeight)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .padding(.top, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 28))
                .foregroundStyle(Theme.textSecondary)
            Text("Add a contact to start")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Pair with another Mac on this Wi-Fi using a short code.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Button("Add contact") { model.openPairing() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Send"
        HiddenWindowGuard.protect(panel)
        NSApp.activate()
        panel.begin { response in
            guard response == .OK else { return }
            model.attach(panel.urls.map(AttachmentDraft.file))
        }
        HiddenWindowGuard.protect(panel)
    }
}

struct HeaderButtons: View {
    let model: AppModel
    var chrome: ChatChrome

    var body: some View {
        HStack(spacing: 2) {
            HiddenBadge()
                .padding(.trailing, 4)
            if let onTogglePin = chrome.onTogglePin {
                IconButton(systemName: chrome.isPinned ? "pin.fill" : "pin", tint: chrome.isPinned ? Theme.accent : Theme.textSecondary, action: onTogglePin)
            }
            if model.settings.lockType != .none {
                IconButton(systemName: "lock") { model.isLocked = true }
            }
            IconButton(systemName: "gearshape") { model.screen = .settings }
            if let onClose = chrome.onClose {
                IconButton(systemName: "xmark", action: onClose)
            }
        }
    }
}
