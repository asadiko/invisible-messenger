import MessengerCore
import SwiftUI

/// Add a contact: show a code on this Mac, or type the code shown on the other one, then compare emoji.
struct PairingView: View {
    let model: AppModel
    var chrome: ChatChrome

    private enum Tab: String, CaseIterable {
        case show = "Show my code"
        case enter = "Enter code"
    }

    @State private var tab: Tab = .show
    @State private var typed = ""

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Add a contact", chrome: chrome) {
                model.cancelPairing()
                model.screen = .chat
            }
            .padding(.top, chrome.topInset)
            Rectangle().fill(Theme.separator).frame(height: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
        }
        .background(Theme.background)
    }

    @ViewBuilder private var content: some View {
        switch model.pairingState {
        case .connecting?:
            status(icon: nil, title: "Looking for the other Mac…", detail: "Both Macs need to be on the same Wi-Fi.", spinner: true)
        case .verify(let emoji, let peerName)?:
            verify(emoji: emoji, peerName: peerName)
        case .waitingForPeer?:
            status(icon: nil, title: "Waiting for the other Mac to confirm…", detail: nil, spinner: true)
        case .done(let contact)?:
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 36)).foregroundStyle(Theme.online)
                Text("\(contact.name) added").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Button("Start chatting") {
                    model.cancelPairing()
                    model.screen = .chat
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        case .failed(let failure)?:
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.circle").font(.system(size: 30)).foregroundStyle(Color.orange)
                Text(Self.message(for: failure))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Button("Try again") {
                    model.cancelPairing()
                    if tab == .show { model.startHosting() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        case .showingCode(let code, let expiresAt)?:
            VStack(spacing: 16) {
                tabs
                showCode(code: code, expiresAt: expiresAt)
                Spacer(minLength: 0)
            }
        case nil:
            VStack(spacing: 16) {
                tabs
                if tab == .enter { enterCode } else { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
            }
            .onAppear { if tab == .show { model.startHosting() } }
        }
    }

    private var tabs: some View {
        Picker("", selection: $tab) {
            ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 280)
        .onChange(of: tab) { _, newTab in
            model.cancelPairing()
            if newTab == .show { model.startHosting() }
        }
    }

    private func showCode(code: String, expiresAt: Date) -> some View {
        VStack(spacing: 10) {
            Text("Type this code on the other Mac")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Text(PairingCode.display(code))
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .kerning(4)
                .foregroundStyle(Theme.textPrimary)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = max(0, Int(expiresAt.timeIntervalSince(context.date)))
                Text("Expires in \(left / 60):\(String(format: "%02d", left % 60)) · waiting for the other Mac…")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var enterCode: some View {
        VStack(spacing: 12) {
            Text("Type the code shown on the other Mac")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            TextField("XXXX-XXXX", text: $typed)
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.vertical, 8)
                .frame(maxWidth: 260)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .onChange(of: typed) { _, value in typed = Self.format(value) }
                .onSubmit(connect)
            Button("Connect", action: connect)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(PairingCode.normalize(typed) == nil)
        }
    }

    private func verify(emoji: [String], peerName: String) -> some View {
        VStack(spacing: 16) {
            Text("Do you both see the same emoji?")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Check with \(peerName). If they're different, someone else may be listening.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 14) {
                ForEach(Array(emoji.enumerated()), id: \.offset) { _, e in
                    Text(e).font(.system(size: 40))
                }
            }
            HStack(spacing: 12) {
                Button("They don't match") { model.pairing?.confirm(false) }
                    .buttonStyle(.bordered)
                Button("They match") { model.pairing?.confirm(true) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
    }

    private func status(icon: String?, title: String, detail: String?, spinner: Bool) -> some View {
        VStack(spacing: 12) {
            if spinner { ProgressView().controlSize(.regular) }
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary)
            if let detail { Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary) }
            Button("Cancel") { model.cancelPairing() }.buttonStyle(.plain).foregroundStyle(Theme.accent)
        }
    }

    private func connect() {
        guard PairingCode.normalize(typed) != nil else { return }
        model.join(code: typed)
    }

    /// Uppercases and inserts the dash as the user types: "k7q4m2" → "K7Q4-M2".
    static func format(_ input: String) -> String {
        let chars = input.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(8)
        let s = String(chars)
        return s.count > 4 ? "\(s.prefix(4))-\(s.dropFirst(4))" : s
    }

    static func message(for failure: PairingFailure) -> String {
        switch failure {
        case .wrongCode: "That code didn't work. Check it and try again."
        case .tooManyAttempts: "Too many wrong tries. Make a new code."
        case .expired: "The code expired. Make a new one."
        case .notFound: "No Mac is showing a code on this network."
        case .rejected: "Pairing was cancelled because the emoji didn't match."
        case .cancelled: "Pairing was cancelled."
        case .network: "Couldn't connect. Make sure both Macs are on the same Wi-Fi."
        }
    }
}

/// Back button + title + window controls, used by the pairing and settings screens.
struct ScreenHeader: View {
    let title: String
    var chrome: ChatChrome
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text("Back").font(.system(size: 12))
                }
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            HiddenBadge()
            if let onClose = chrome.onClose {
                IconButton(systemName: "xmark", action: onClose)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
