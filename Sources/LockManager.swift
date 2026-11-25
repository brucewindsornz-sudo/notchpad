import Foundation
import LocalAuthentication

/// Touch ID / Mac password lock for the scratchpad.
final class LockManager: ObservableObject {
    static let shared = LockManager()
    @Published var isLocked = false
    private var prompting = false

    func lock() {
        if Settings.shared.lockEnabled { isLocked = true }
    }

    func unlock() {
        guard isLocked, !prompting else { return }
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use Password"
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No Touch ID and no login password set: nothing to check against.
            isLocked = false
            return
        }
        prompting = true
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "open your scratchpad") { ok, _ in
            DispatchQueue.main.async {
                self.prompting = false
                if ok { self.isLocked = false }
            }
        }
    }
}
