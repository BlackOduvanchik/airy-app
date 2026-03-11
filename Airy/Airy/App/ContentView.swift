//
//  ContentView.swift
//  Airy
//

import SwiftUI
import StoreKit

private let deviceIdKey = "airy_device_id"

struct ContentView: View {
    @Environment(AuthStore.self) private var authStore
    @AppStorage("AiryHasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var triedLocalLogin = false

    var body: some View {
        Group {
            if authStore.token != nil {
                MainTabView()
            } else if !triedLocalLogin {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hasSeenOnboarding {
                OnboardingView(onBackToOnboarding: { hasSeenOnboarding = false })
            } else {
                OnboardingFlowView(onFinish: { hasSeenOnboarding = true })
            }
        }
        .task {
            await APIClient.shared.setAuthToken(authStore.token)
        }
        .task {
            guard authStore.token == nil, !triedLocalLogin else { return }
            await tryLocalLogin()
        }
        .task(id: authStore.token) {
            guard authStore.token != nil else { return }
            if #available(iOS 15.0, *) {
                Task.detached(priority: .background) {
                    await StoreKitService.shared.startTransactionUpdatesListener()
                }
            }
        }
    }

    private func tryLocalLogin() async {
        let id: String
        if let stored = UserDefaults.standard.string(forKey: deviceIdKey) {
            id = stored
        } else {
            id = "device-\(UUID().uuidString.prefix(12))"
            UserDefaults.standard.set(id, forKey: deviceIdKey)
        }
        do {
            let res = try await APIClient.shared.registerOrLogin(externalId: id, email: nil)
            await MainActor.run {
                authStore.setAuth(token: res.token, userId: res.user.id)
            }
        } catch {
            await MainActor.run { triedLocalLogin = true }
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthStore())
}
