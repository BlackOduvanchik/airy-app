//
//  ContentView.swift
//  Airy
//
//  Local-only: Sign in with Apple, no backend.
//

import SwiftUI
import StoreKit

struct ContentView: View {
    @Environment(AuthStore.self) private var authStore
    @AppStorage("AiryHasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        Group {
            if authStore.isLoggedIn {
                MainTabView()
            } else if hasSeenOnboarding {
                OnboardingView(onBackToOnboarding: { hasSeenOnboarding = false })
            } else {
                OnboardingFlowView(onFinish: { hasSeenOnboarding = true })
            }
        }
        .task(id: authStore.userId) {
            guard authStore.isLoggedIn else { return }
            if #available(iOS 15.0, *) {
                Task.detached(priority: .background) {
                    await StoreKitService.shared.startTransactionUpdatesListener()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthStore())
}
