import Foundation
import LocalAuthentication
import MessengerCore

/// The optional app lock: Touch ID (falling back to the Mac password) or a separate app password.
/// It keeps people at your Mac out of the chats; the files on disk are encrypted either way.
final class AppLock {
    unowned let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    private var settings: AppSettings { model.settings }

    var hasPassword: Bool { ((try? model.secrets.read(SecretAccount.appPassword)) ?? nil) != nil }

    static var touchIDAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func lockIfEnabled() {
        guard settings.lockType != .none else { return }
        if settings.lockType == .password && !hasPassword { return }
        model.isLocked = true
    }

    @discardableResult
    func unlock(password: String) -> Bool {
        guard let stored = (try? model.secrets.read(SecretAccount.appPassword)) ?? nil,
              PasswordHash.verify(password, against: stored) else { return false }
        model.isLocked = false
        return true
    }

    func unlockWithTouchID() async -> Bool {
        let context = LAContext()
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "unlock Invisible Messenger")
            if ok { model.isLocked = false }
            return ok
        } catch {
            return false
        }
    }

    func setPassword(_ password: String) throws {
        try model.secrets.write(PasswordHash.make(password), account: SecretAccount.appPassword)
    }

    func removePassword() {
        try? model.secrets.delete(SecretAccount.appPassword)
    }
}
