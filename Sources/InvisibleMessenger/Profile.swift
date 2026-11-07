import Foundation

/// Where this instance keeps its data. `IM_PROFILE=<name>` runs a separate copy with its own
/// data folder, Keychain items and preferences (used to try pairing two copies on one Mac).
struct Profile {
    static let bundleID = "com.asadiko.InvisibleMessenger"
    static let current = Profile(name: ProcessInfo.processInfo.environment["IM_PROFILE"])

    let name: String?
    let dataDirectory: URL
    let keychainService: String
    let defaultsSuite: String?

    init(name rawName: String?) {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = rawName.map { String($0.unicodeScalars.filter(allowed.contains)) }
        name = (cleaned?.isEmpty ?? true) ? nil : cleaned
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InvisibleMessenger", isDirectory: true)
        if let name {
            dataDirectory = base.appendingPathComponent("profiles/\(name)", isDirectory: true)
            keychainService = "\(Self.bundleID).\(name)"
            defaultsSuite = "\(Self.bundleID).\(name)"
        } else {
            dataDirectory = base
            keychainService = Self.bundleID
            defaultsSuite = nil
        }
    }

    var defaults: UserDefaults {
        defaultsSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    /// Removes this profile's preferences.
    func resetDefaults() {
        if let defaultsSuite {
            UserDefaults.standard.removePersistentDomain(forName: defaultsSuite)
        } else {
            UserDefaults.standard.removePersistentDomain(forName: Self.bundleID)
        }
    }
}
