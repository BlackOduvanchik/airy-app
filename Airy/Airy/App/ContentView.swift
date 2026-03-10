//
//  ContentView.swift
//  Airy
//

import SwiftUI
import StoreKit

struct ContentView: View {
    @Environment(AuthStore.self) private var authStore
    @AppStorage("AiryHasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        Group {
            if authStore.token == nil {
                if hasSeenOnboarding {
                    OnboardingView()
                } else {
                    OnboardingFlowView(onFinish: { hasSeenOnboarding = true })
                }
            } else {
                MainTabView()
            }
        }
        .task {
            await APIClient.shared.setAuthToken(authStore.token)
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
}

#Preview {
    ContentView()
        .environment(AuthStore())
}
