import SwiftUI

/// Shown in the panel instead of the chat while the app is locked.
struct LockView: View {
    let model: AppModel
    var chrome: ChatChrome

    @State private var password = ""
    @State private var wrong = false
    @State private var authenticating = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                HiddenBadge()
                if let onClose = chrome.onClose { IconButton(systemName: "xmark", label: "Close", action: onClose) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .padding(.top, chrome.topInset)
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.textSecondary)
                Text("Invisible Messenger is locked")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if model.totalUnread > 0 {
                    Text("\(model.totalUnread) new")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                }
                switch model.settings.lockType {
                case .password: passwordForm
                case .touchID: touchIDButton
                case .none: Button("Unlock") { model.isLocked = false }.buttonStyle(.borderedProminent)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
    }

    private var passwordForm: some View {
        VStack(spacing: 10) {
            SecureField("App password", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit(tryPassword)
            if wrong {
                Text("Wrong password").font(.system(size: 11.5)).foregroundStyle(Color.red)
            }
            Button("Unlock", action: tryPassword)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
    }

    private var touchIDButton: some View {
        VStack(spacing: 8) {
            Button {
                authenticating = true
                Task {
                    _ = await model.lock.unlockWithTouchID()
                    authenticating = false
                }
            } label: {
                Label("Unlock with Touch ID", systemImage: "touchid")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(authenticating)
            Text("The Touch ID prompt is drawn by macOS and may show up in a screen share.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
    }

    private func tryPassword() {
        wrong = !model.lock.unlock(password: password)
        password = ""
    }
}

/// The App lock part of Settings.
struct LockSettingsSection: View {
    let model: AppModel

    @State private var settingPassword = false
    @State private var first = ""
    @State private var second = ""
    @State private var problem: String?

    private var settings: AppSettings { model.settings }

    var body: some View {
        SettingsSection("App lock") {
            HStack {
                Text("Lock with").font(.system(size: 12.5)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Picker("", selection: Binding(get: { settings.lockType }, set: choose)) {
                    Text("Nothing").tag(LockType.none)
                    Text("Touch ID").tag(LockType.touchID)
                    Text("Password").tag(LockType.password)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 230)
            }
            if settingPassword {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("New password (at least 4 characters)", text: $first).textFieldStyle(.roundedBorder)
                    SecureField("Repeat password", text: $second).textFieldStyle(.roundedBorder)
                    if let problem { Text(problem).font(.system(size: 11)).foregroundStyle(Color.red) }
                    HStack {
                        Button("Cancel") { resetForm() }.buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Button("Save password", action: savePassword).buttonStyle(.borderedProminent).tint(Theme.accent)
                    }
                    .font(.system(size: 12))
                }
            }
            if settings.lockType != .none {
                HStack {
                    Text("Lock when the Mac is idle for").font(.system(size: 12.5)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Picker("", selection: Binding(get: { settings.idleLockMinutes ?? 0 }, set: { settings.idleLockMinutes = $0 == 0 ? nil : $0 })) {
                        Text("5 min").tag(5)
                        Text("15 min").tag(15)
                        Text("1 hour").tag(60)
                        Text("Never").tag(0)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 230)
                }
                if settings.lockType == .password && !settingPassword {
                    Button("Change password") { settingPassword = true }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent).font(.system(size: 12))
                }
                Text("It also locks when the Mac sleeps or its screen locks.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func choose(_ type: LockType) {
        resetForm()
        switch type {
        case .none:
            settings.lockType = .none
            model.lock.removePassword()
        case .touchID:
            if AppLock.touchIDAvailable {
                settings.lockType = .touchID
                model.lock.removePassword()
            } else {
                problem = "This Mac can't use Touch ID or its password for this."
            }
        case .password:
            settingPassword = true
        }
    }

    private func savePassword() {
        guard first.count >= 4 else { problem = "Use at least 4 characters."; return }
        guard first == second else { problem = "The passwords don't match."; return }
        do {
            try model.lock.setPassword(first)
            settings.lockType = .password
            resetForm()
        } catch {
            problem = "Couldn't save the password."
        }
    }

    private func resetForm() {
        settingPassword = false
        first = ""
        second = ""
        problem = nil
    }
}
