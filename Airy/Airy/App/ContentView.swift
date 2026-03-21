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
    @Environment(AppLockManager.self) private var appLockManager
    @AppStorage("AiryHasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showSplash = true

    var body: some View {
        ZStack {
            Group {
                if authStore.isLoggedIn {
                    MainTabView()
                } else if hasSeenOnboarding {
                    OnboardingView(onBackToOnboarding: { hasSeenOnboarding = false })
                } else {
                    OnboardingFlowView(onFinish: { hasSeenOnboarding = true })
                }
            }

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }

            if appLockManager.isLocked {
                AppLockView()
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .task {
            if authStore.isLoggedIn {
                await DashboardViewModel.shared.load()
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            withAnimation(.easeOut(duration: 0.6)) {
                showSplash = false
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
        .environment(AppLockManager.shared)
}
