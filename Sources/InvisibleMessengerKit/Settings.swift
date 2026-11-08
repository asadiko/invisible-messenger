import AppKit
import Carbon.HIToolbox
import Observation

enum AppearanceMode: String, CaseIterable {
    case notch, floating
}

enum ChatLayout: String, CaseIterable {
    case sidebar, tabs
}

enum LockType: String, CaseIterable {
    case none, touchID, password
}

/// A global shortcut: Carbon key code + Carbon modifier mask, with a label for display.
struct HotKeySpec: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyLabel: String

    static let `default` = HotKeySpec(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(cmdKey | optionKey), keyLabel: "M")

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyLabel
    }

    /// Builds a spec from a key event; nil unless at least one of ⌃⌥⌘ is held.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        guard mods & UInt32(controlKey | optionKey | cmdKey) != 0 else { return nil }
        let label = (event.charactersIgnoringModifiers ?? "").uppercased()
        self.init(keyCode: UInt32(event.keyCode), modifiers: mods, keyLabel: label.isEmpty ? "#\(event.keyCode)" : label)
    }

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }
}

/// User preferences, persisted to the profile's UserDefaults as they change.
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    var layout: ChatLayout { didSet { defaults.set(layout.rawValue, forKey: "layout") } }
    /// 0.4 ... 1.0
    var floatingOpacity: Double { didSet { defaults.set(floatingOpacity, forKey: "floatingOpacity") } }
    /// nil means the default (three notch-widths by 520 pt).
    var panelSize: CGSize? {
        didSet {
            if let panelSize {
                defaults.set(Double(panelSize.width), forKey: "panelWidth")
                defaults.set(Double(panelSize.height), forKey: "panelHeight")
            } else {
                defaults.removeObject(forKey: "panelWidth")
                defaults.removeObject(forKey: "panelHeight")
            }
        }
    }
    var hotKey: HotKeySpec {
        didSet { defaults.set(try? JSONEncoder().encode(hotKey), forKey: "hotKey") }
    }
    var lockType: LockType { didSet { defaults.set(lockType.rawValue, forKey: "lockType") } }
    /// nil = never lock when idle.
    var idleLockMinutes: Int? {
        didSet { defaults.set(idleLockMinutes ?? 0, forKey: "idleLockMinutes") }
    }
    var displayName: String { didSet { defaults.set(displayName, forKey: "displayName") } }
    var saveFolder: URL { didSet { defaults.set(saveFolder.path, forKey: "saveFolder") } }
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }

    static let idleChoices: [Int?] = [5, 15, 60, nil]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        appearance = defaults.string(forKey: "appearance").flatMap(AppearanceMode.init) ?? .notch
        layout = defaults.string(forKey: "layout").flatMap(ChatLayout.init) ?? .sidebar
        let opacity = defaults.object(forKey: "floatingOpacity") as? Double ?? 0.92
        floatingOpacity = min(max(opacity, 0.4), 1)
        if let w = defaults.object(forKey: "panelWidth") as? Double, let h = defaults.object(forKey: "panelHeight") as? Double {
            panelSize = CGSize(width: w, height: h)
        } else {
            panelSize = nil
        }
        hotKey = defaults.data(forKey: "hotKey").flatMap { try? JSONDecoder().decode(HotKeySpec.self, from: $0) } ?? .default
        lockType = defaults.string(forKey: "lockType").flatMap(LockType.init) ?? .none
        if let minutes = defaults.object(forKey: "idleLockMinutes") as? Int {
            idleLockMinutes = minutes == 0 ? nil : minutes
        } else {
            idleLockMinutes = 15
        }
        displayName = defaults.string(forKey: "displayName") ?? Host.current().localizedName ?? "Mac"
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        saveFolder = defaults.string(forKey: "saveFolder").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? downloads
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
    }
}
