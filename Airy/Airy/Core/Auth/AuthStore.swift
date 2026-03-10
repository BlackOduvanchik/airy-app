//
//  AuthStore.swift
//  Airy
//

import Foundation
import SwiftUI

@Observable
final class AuthStore {
    var token: String? {
        didSet { UserDefaults.standard.set(token, forKey: "airy_token") }
    }
    var userId: String? {
        didSet { UserDefaults.standard.set(userId, forKey: "airy_user_id") }
    }

    var isLoggedIn: Bool { token != nil }

    init() {
        self.token = UserDefaults.standard.string(forKey: "airy_token")
        self.userId = UserDefaults.standard.string(forKey: "airy_user_id")
    }

    func setAuth(token: String, userId: String) {
        self.token = token
        self.userId = userId
    }

    func logout() {
        token = nil
        userId = nil
    }
}
