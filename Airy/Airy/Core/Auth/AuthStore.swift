//
//  AuthStore.swift
//  Airy
//
//  Local-only auth: Sign in with Apple, stored in Keychain. No backend.
//

import Foundation
import SwiftUI

@Observable
final class AuthStore {
    /// Apple user identifier (from ASAuthorizationAppleIDCredential.user). Used as local session.
    var userId: String? {
        didSet {
            if let id = userId {
                KeychainHelper.saveUserIdentifier(id)
            } else {
                KeychainHelper.deleteUserIdentifier()
            }
        }
    }

    var isLoggedIn: Bool { userId != nil }

    init() {
        self.userId = KeychainHelper.loadUserIdentifier()
    }

    func setAuth(userIdentifier: String) {
        self.userId = userIdentifier
    }

    func logout() {
        userId = nil
    }
}
