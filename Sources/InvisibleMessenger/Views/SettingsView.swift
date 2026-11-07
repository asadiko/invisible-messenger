import AppKit
import MessengerCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    var chrome: ChatChrome

    @State private var name = ""
    @State private var recordingHotKey = false
    @State private var hotKeyMonitor: Any?
    @State private var renaming: DeviceID?
    @State private var renameText = ""
    @State private var confirming: Confirmation?

    private enum Confirmation: Equatable {
        case clear(DeviceID), remove(DeviceID), deleteAll
    }

    private var settings: AppSettings { model.settings }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Settings", chrome: chrome) {
                stopRecording()
                model.screen = .chat
            }
            .padding(.top, chrome.topInset)
            Rectangle().fill(Theme.separator).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    appearanceSection
                    shortcutSection
                    LockSettingsSection(model: model)
                    profileSection
                    contactsSection
                    filesSection
                    appSection
                    Text("Hidden from screen sharing: always on")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.hidden)
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
        }
        .background(Theme.background)
        .onAppear { name = settings.displayName }
        .onDisappear(perform: stopRecording)
    }

    // MARK: Sections

    private var appearanceSection: some View {
        SettingsSection("Appearance") {
            row("Show chat") {
                Picker("", selection: Binding(get: { settings.appearance }, set: { settings.appearance = $0 })) {
                    Text("In the notch").tag(AppearanceMode.notch)
                    Text("Floating window").tag(AppearanceMode.floating)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 230)
            }
            row("Contacts") {
                Picker("", selection: Binding(get: { settings.layout }, set: { settings.layout = $0 })) {
                    Text("List").tag(ChatLayout.sidebar)
                    Text("Tabs").tag(ChatLayout.tabs)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 140)
            }
            row("Window opacity") {
                HStack {
                    Slider(value: Binding(get: { settings.floatingOpacity }, set: { settings.floatingOpacity = $0 }), in: 0.4...1)
                        .frame(width: 150)
                    Text("\(Int(settings.floatingOpacity * 100))%")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
            row("Notch panel size") {
                Button("Reset to 3 notches wide") { settings.panelSize = nil }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent).font(.system(size: 12))
            }
        }
    }

    private var shortcutSection: some View {
        SettingsSection("Shortcut") {
            row("Show / hide chat") {
                HStack(spacing: 10) {
                    Text(recordingHotKey ? "Press keys…" : settings.hotKey.displayString)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
                    Button(recordingHotKey ? "Cancel" : "Change") {
                        recordingHotKey ? stopRecording() : startRecording()
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent).font(.system(size: 12))
                }
            }
        }
    }

    private var profileSection: some View {
        SettingsSection("This Mac") {
            row("Your name") {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit { model.setDisplayName(name) }
                    .onChange(of: name) { _, value in
                        if !value.trimmingCharacters(in: .whitespaces).isEmpty { model.setDisplayName(value) }
                    }
            }
        }
    }

    private var contactsSection: some View {
        SettingsSection("Contacts") {
            if model.contacts.isEmpty {
                Text("No contacts yet.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            ForEach(model.contacts) { contact in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        PresenceDot(online: model.isOnline(contact.id))
                        if renaming == contact.id {
                            TextField("Name", text: $renameText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                                .onSubmit { finishRename(contact.id) }
                            Button("Save") { finishRename(contact.id) }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                        } else {
                            Text(contact.name).font(.system(size: 12.5)).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            smallButton("Rename") { renameText = contact.name; renaming = contact.id }
                            smallButton("Clear chat") { confirming = .clear(contact.id) }
                            smallButton("Remove", destructive: true) { confirming = .remove(contact.id) }
                        }
                    }
                    if confirming == .clear(contact.id) {
                        confirmRow("Delete all messages with \(contact.name)?", action: "Delete") {
                            model.messenger.clearChat(contact.id)
                            model.selectedContactID = model.selectedContactID
                        }
                    } else if confirming == .remove(contact.id) {
                        confirmRow("Remove \(contact.name) and delete the chat?", action: "Remove") {
                            model.messenger.removeContact(contact.id)
                        }
                    }
                }
            }
        }
    }

    private var filesSection: some View {
        SettingsSection("Files") {
            row("Save files to") {
                HStack(spacing: 8) {
                    Text(settings.saveFolder.lastPathComponent)
                        .font(.system(size: 12)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Button("Change…", action: chooseFolder)
                        .buttonStyle(.plain).foregroundStyle(Theme.accent).font(.system(size: 12))
                }
            }
        }
    }

    private var appSection: some View {
        SettingsSection("App") {
            row("Open at login") {
                Toggle("", isOn: Binding(get: { settings.launchAtLogin }, set: setLaunchAtLogin))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            HStack(spacing: 12) {
                Button("Quit Invisible Messenger") { NSApp.terminate(nil) }
                    .buttonStyle(.bordered)
                Button("Delete all data…") { confirming = .deleteAll }
                    .buttonStyle(.bordered)
                    .foregroundStyle(Color.red)
            }
            if confirming == .deleteAll {
                confirmRow("Delete every chat, contact and key on this Mac and quit?", action: "Delete everything", perform: deleteAllData)
            }
        }
    }

    // MARK: Pieces

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 12)
            content()
        }
    }

    private func smallButton(_ title: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11.5))
            .foregroundStyle(destructive ? Color.red.opacity(0.85) : Theme.accent)
    }

    private func confirmRow(_ question: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(question).font(.system(size: 11.5)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Button("Cancel") { confirming = nil }.buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            Button(action) {
                confirming = nil
                perform()
            }
            .buttonStyle(.plain).foregroundStyle(Color.red)
        }
        .font(.system(size: 11.5))
        .padding(8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Actions

    private func finishRename(_ id: DeviceID) {
        model.messenger.renameContact(id, to: renameText)
        renaming = nil
    }

    private func startRecording() {
        recordingHotKey = true
        hotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            guard let spec = HotKeySpec(event: event) else { return nil }
            settings.hotKey = spec
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let hotKeyMonitor { NSEvent.removeMonitor(hotKeyMonitor) }
        hotKeyMonitor = nil
        recordingHotKey = false
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = settings.saveFolder
        HiddenWindowGuard.protect(panel)
        NSApp.activate()
        panel.begin { response in
            if response == .OK, let url = panel.url { settings.saveFolder = url }
        }
        HiddenWindowGuard.protect(panel)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            settings.launchAtLogin = on
        } catch {
            model.showNotice("Couldn't change Open at login: \(error.localizedDescription)")
        }
    }

    private func deleteAllData() {
        model.messenger.stop()
        try? ChatStore.wipe(directory: model.store.directory)
        try? model.secrets.deleteAll()
        model.profile.resetDefaults()
        if settings.launchAtLogin { try? SMAppService.mainApp.unregister() }
        NSApp.terminate(nil)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
