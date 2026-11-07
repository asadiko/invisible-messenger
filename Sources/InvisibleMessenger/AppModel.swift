import AppKit
import CryptoKit
import MessengerCore
import Observation
import UniformTypeIdentifiers

/// Which screen the chat panel is showing.
enum PanelScreen: Equatable {
    case chat, pairing, settings
}

/// Something the user is about to send: pasted/dropped data or a file on disk.
struct AttachmentDraft {
    var data: Data?
    var url: URL?
    var fileName: String
    var kind: AttachmentKind

    static func file(_ url: URL) -> AttachmentDraft {
        let isImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
        return AttachmentDraft(data: nil, url: url, fileName: url.lastPathComponent, kind: isImage ? .image : .file)
    }

    static func image(_ data: Data, name: String = "Pasted image.png") -> AttachmentDraft {
        AttachmentDraft(data: data, url: nil, fileName: name, kind: .image)
    }
}

/// UI state for the whole app, fed by the messenger's events.
@Observable
final class AppModel {
    let profile: Profile
    let settings: AppSettings
    @ObservationIgnored let secrets: SecretStore
    @ObservationIgnored let store: ChatStore
    @ObservationIgnored let messenger: Messenger

    var contacts: [Contact] = []
    var selectedContactID: DeviceID? {
        didSet {
            guard oldValue != selectedContactID else { return }
            reloadMessages()
            markReadIfVisible()
        }
    }
    var messages: [ChatMessage] = []
    var online: Set<DeviceID> = []
    var progress: [UUID: Double] = [:]
    var isLocked = false {
        didSet {
            // Nothing of the chat may stay on screen once locked.
            if isLocked { ImageViewerController.shared.close() }
            markReadIfVisible()
        }
    }
    /// Set by the window controllers: true while the chat is on screen.
    var chatVisible = false { didSet { markReadIfVisible() } }
    var screen: PanelScreen = .chat
    var pairing: PairingSession?
    var pairingState: PairingSession.State?
    /// A short inline message ("Saved to Downloads", errors), cleared after a few seconds.
    var notice: String?
    var lastIncomingFrom: DeviceID?

    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored lazy var lock = AppLock(model: self)

    var totalUnread: Int { contacts.reduce(0) { $0 + $1.unreadCount } }
    var selectedContact: Contact? { contacts.first { $0.id == selectedContactID } }
    func isOnline(_ id: DeviceID) -> Bool { online.contains(id) }
    func contact(_ id: DeviceID?) -> Contact? { contacts.first { $0.id == id } }

    init(profile: Profile, settings: AppSettings, secrets: SecretStore, identity: DeviceIdentity, store: ChatStore) {
        self.profile = profile
        self.settings = settings
        self.secrets = secrets
        self.store = store
        messenger = Messenger(.init(
            identity: identity,
            displayName: settings.displayName,
            store: store,
            advertise: true,
            directory: BonjourDirectory()
        ))
        messenger.onEvent = { [weak self] event in self?.handle(event) }
        refreshContacts()
    }

    /// Opens this profile's keys and data. If the Keychain can't be read, runs with a throwaway profile
    /// (nothing is lost on disk); if the data can't be decrypted, sets it aside and starts fresh.
    static func bootstrap(profile: Profile = .current) -> AppModel {
        let settings = AppSettings(defaults: profile.defaults)
        let keychain = KeychainSecretStore(service: profile.keychainService)
        var notice: String?
        var secrets: SecretStore = keychain
        var dataDirectory = profile.dataDirectory
        var identity: DeviceIdentity
        var key: SymmetricKey
        do {
            identity = try DeviceIdentity.loadOrCreate(in: keychain)
            key = try DataSealer.loadOrCreateKey(in: keychain)
        } catch {
            secrets = InMemorySecretStore()
            identity = DeviceIdentity.generate()
            key = SymmetricKey(size: .bits256)
            dataDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("InvisibleMessenger-\(UUID().uuidString)")
            notice = "Couldn't open the Keychain, so chats won't be kept after you quit."
        }
        let store: ChatStore
        if let opened = try? ChatStore(directory: dataDirectory, sealer: DataSealer(key: key)) {
            store = opened
        } else {
            let aside = dataDirectory.deletingLastPathComponent()
                .appendingPathComponent("\(dataDirectory.lastPathComponent).unreadable-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: dataDirectory, to: aside)
            if let fresh = try? ChatStore(directory: dataDirectory, sealer: DataSealer(key: key)) {
                store = fresh
                notice = "Old chats couldn't be opened, so they were set aside and you're starting fresh."
            } else {
                // The folder couldn't even be moved: run from a temporary folder rather than crash.
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("InvisibleMessenger-\(UUID().uuidString)")
                store = try! ChatStore(directory: temporary, sealer: DataSealer(key: key))
                notice = "Your chats folder couldn't be opened, so chats won't be kept after you quit."
            }
        }
        let model = AppModel(profile: profile, settings: settings, secrets: secrets, identity: identity, store: store)
        model.seedDemoIfRequested()
        if let notice { model.showNotice(notice, seconds: 10) }
        return model
    }

    func start() {
        do {
            try messenger.start()
        } catch {
            showNotice("Couldn't start networking: \(error.localizedDescription)", seconds: 10)
        }
    }

    // MARK: Events

    private func handle(_ event: MessengerEvent) {
        switch event {
        case .messageAdded(let message):
            if message.direction == .incoming { lastIncomingFrom = message.contactID }
            if message.contactID == selectedContactID, !messages.contains(where: { $0.id == message.id }) {
                messages.append(message)
                messages.sort { $0.sentAt < $1.sentAt }
            }
            if message.direction == .incoming { markReadIfVisible() }
        case .messageUpdated(let message):
            if let i = messages.firstIndex(where: { $0.id == message.id }) { messages[i] = message }
        case .messageRemoved(let id, _):
            messages.removeAll { $0.id == id }
        case .contactsChanged:
            refreshContacts()
        case .presenceChanged(let id, let isOnline):
            if isOnline { online.insert(id) } else { online.remove(id) }
        case .transferProgress(let id, let fraction):
            progress[id] = fraction < 1 ? fraction : nil
        }
    }

    private func refreshContacts() {
        contacts = store.contacts.sorted { $0.pairedAt < $1.pairedAt }
        if selectedContactID == nil || contact(selectedContactID) == nil {
            selectedContactID = contacts.first?.id
        }
        if let selectedContactID { messages = store.messages(for: selectedContactID) }
        // A message announced just before this refresh may belong to the chat that is open right now.
        markReadIfVisible()
    }

    private func reloadMessages() {
        messages = selectedContactID.map { store.messages(for: $0) } ?? []
    }

    private func markReadIfVisible() {
        guard chatVisible, !isLocked, screen == .chat, let id = selectedContactID,
              contact(id)?.unreadCount ?? 0 > 0 else { return }
        messenger.markRead(id)
    }

    func screenChanged() {
        markReadIfVisible()
    }

    // MARK: Chat actions

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = selectedContactID else { return }
        let body = text.trimmingCharacters(in: .newlines)
        do {
            try messenger.sendText(body, to: id)
        } catch MessengerError.messageTooLarge {
            // Very long pastes (logs, dumps) go as a text file instead.
            attach([AttachmentDraft(data: Data(body.utf8), url: nil, fileName: "Pasted text.txt", kind: .file)])
            showNotice("That text was long, so it was sent as a file.")
        } catch {
            showNotice("Couldn't send the message.")
        }
    }

    func attach(_ drafts: [AttachmentDraft]) {
        guard let id = selectedContactID else { return }
        for draft in drafts {
            do {
                if let data = draft.data {
                    try messenger.sendData(data, fileName: draft.fileName, kind: draft.kind, to: id)
                } else if let url = draft.url {
                    try messenger.sendFile(at: url, kind: draft.kind, to: id)
                }
            } catch MessengerError.attachmentTooLarge {
                showNotice("\(draft.fileName) is larger than 100 MB.")
            } catch {
                showNotice("Couldn't read \(draft.fileName).")
            }
        }
    }

    func delete(_ message: ChatMessage) {
        messenger.deleteMessage(message.id, contact: message.contactID)
    }

    func attachmentData(_ message: ChatMessage) -> Data? {
        try? store.readAttachment(messageID: message.id)
    }

    /// Writes an attachment to the save folder without any dialog, never overwriting an existing file.
    @discardableResult
    func save(_ message: ChatMessage) -> URL? {
        guard case .attachment(let info) = message.body else { return nil }
        guard let data = attachmentData(message) else {
            showNotice("That file isn't available on this Mac.")
            return nil
        }
        let folder = settings.saveFolder.standardizedFileURL
        let name = AttachmentInfo.safeFileName(info.fileName)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var url = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            n += 1
        }
        guard url.deletingLastPathComponent().standardizedFileURL.path == folder.path else { return nil }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url)
            showNotice("Saved to \(folder.lastPathComponent)")
            return url
        } catch {
            showNotice("Couldn't save \(info.fileName).")
            return nil
        }
    }

    func showNotice(_ text: String, seconds: Double = 3) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    // MARK: Pairing

    func startHosting() {
        track(messenger.startHostingPairing())
    }

    func join(code: String) {
        track(messenger.joinPairing(code: code))
    }

    func cancelPairing() {
        pairing?.cancel()
        pairing = nil
        pairingState = nil
    }

    private func track(_ session: PairingSession) {
        pairing?.cancel()
        pairing = session
        pairingState = session.state
        session.onStateChange = { [weak self, weak session] state in
            guard let self, let session, self.pairing === session else { return }
            self.pairingState = state
            if case .done(let contact) = state { self.selectedContactID = contact.id }
        }
    }

    // MARK: Contacts

    func setDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        settings.displayName = String(trimmed.prefix(64))
        messenger.displayName = settings.displayName
    }

    // MARK: Demo data

    /// Fills an empty profile with a sample chat, for screenshots and the capture check.
    private func seedDemoIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard env["IM_SEED_DEMO"] == "1", store.contacts.isEmpty else { return }
        #if !DEBUG
        guard profile.name == "capturecheck" else { return }
        #endif
        let peer = DeviceIdentity.generate()
        let contact = Contact(id: peer.deviceID, name: "Sam", publicKey: peer.publicKeyData)
        try? store.upsert(contact)
        let t0 = Date().addingTimeInterval(-600)
        func add(_ body: MessageBody, _ direction: MessageDirection, _ offset: TimeInterval, data: Data? = nil) {
            let m = ChatMessage(contactID: contact.id, direction: direction, sentAt: t0.addingTimeInterval(offset), body: body, status: .delivered)
            if let data { try? store.writeAttachment(data, messageID: m.id) }
            _ = try? store.append(m)
        }
        add(.text("can you check the query before the demo?"), .incoming, 0)
        add(.text("sure, paste it here"), .outgoing, 30)
        add(.text("```sql\nSELECT id, total\nFROM orders\nWHERE created_at > now() - interval '1 day';\n```"), .incoming, 60)
        add(.text("looks right, add an index on `created_at` 👍"), .outgoing, 90)
        let png = Self.samplePNG()
        add(.attachment(AttachmentInfo(kind: .image, fileName: "screenshot.png", byteCount: Int64(png.count), sha256: Data(SHA256.hash(data: png)))), .outgoing, 120, data: png)
        let notes = Data("Deck notes\n- slide 4 typo\n".utf8)
        add(.attachment(AttachmentInfo(kind: .file, fileName: "deck-notes.txt", byteCount: Int64(notes.count), sha256: Data(SHA256.hash(data: notes)))), .incoming, 150, data: notes)
        refreshContacts()
    }

    private static func samplePNG() -> Data {
        let image = NSImage(size: NSSize(width: 320, height: 200), flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.30, green: 0.42, blue: 0.57, alpha: 1), NSColor(red: 0.75, green: 0.54, blue: 0.37, alpha: 1)])?
                .draw(in: rect, angle: 35)
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return Data() }
        return png
    }
}
