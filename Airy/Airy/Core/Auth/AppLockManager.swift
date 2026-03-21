//
//  AppLockManager.swift
//  Airy
//
//  Manages app lock state: Face ID, Passcode, or both. Locks on background, unlocks via auth.
//

import Foundation
import LocalAuthentication

@Observable @MainActor
final class AppLockManager {
    static let shared = AppLockManager()
    var isLocked = false
    /// When true, the lock screen shows passcode input instead of Face ID prompt.
    var showPasscodeInput = false

    var isFaceIdEnabled: Bool {
        UserDefaults.standard.bool(forKey: "airy.security.faceId")
    }

    var isPasscodeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "airy.security.passcode")
    }

    var hasStoredPasscode: Bool {
        KeychainHelper.loadPasscode() != nil
    }

    func lockIfNeeded() {
        if isFaceIdEnabled || isPasscodeEnabled {
            isLocked = true
            showPasscodeInput = false
        }
    }

    /// Main unlock entry. Tries Face ID if enabled, otherwise passcode input.
    func authenticate() {
        guard isLocked else { return }
        if isFaceIdEnabled {
            authenticateWithBiometric()
        } else if isPasscodeEnabled {
            showPasscodeInput = true
        }
    }

    /// Verify entered passcode against Keychain. Returns true on match.
    func verifyPasscode(_ code: String) -> Bool {
        guard let stored = KeychainHelper.loadPasscode() else { return false }
        return code == stored
    }

    /// Unlock with passcode. Called from the passcode entry UI.
    func unlockWithPasscode(_ code: String) -> Bool {
        if verifyPasscode(code) {
            isLocked = false
            showPasscodeInput = false
            return true
        }
        return false
    }

    /// Save a new passcode to Keychain and enable in UserDefaults.
    func setPasscode(_ code: String) {
        KeychainHelper.savePasscode(code)
        UserDefaults.standard.set(true, forKey: "airy.security.passcode")
    }

    /// Remove passcode from Keychain and disable in UserDefaults.
    func removePasscode() {
        KeychainHelper.deletePasscode()
        UserDefaults.standard.set(false, forKey: "airy.security.passcode")
    }

    /// Switch lock screen to passcode entry (e.g. "Use Passcode" button on Face ID screen).
    func switchToPasscode() {
        showPasscodeInput = true
    }

    // MARK: - Face ID

    /// Verify biometric before enabling/disabling. Returns true if auth succeeded.
    func verifyBiometric() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: L("lock_enable_reason"))
        } catch {
            return false
        }
    }

    // MARK: - Private

    private func authenticateWithBiometric() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: L("lock_reason")) { success, _ in
                Task { @MainActor in
                    if success {
                        self.isLocked = false
                        self.showPasscodeInput = false
                    } else if self.isPasscodeEnabled {
                        // Face ID failed/cancelled → offer passcode fallback
                        self.showPasscodeInput = true
                    }
                }
            }
        } else if isPasscodeEnabled {
            showPasscodeInput = true
        }
    }
}
