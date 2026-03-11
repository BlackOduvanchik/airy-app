//
//  OnboardingView.swift
//  Airy
//
//  Login page with Sign in with Apple. Shown when user taps "I already have an account" or after onboarding.
//

import AuthenticationServices
import SwiftUI

struct OnboardingView: View {
    @Environment(AuthStore.self) private var authStore
    var onBackToOnboarding: () -> Void = {}
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var badgePulse: Bool = false

    var body: some View {
        ZStack {
            OnboardingGradientBackground()

            VStack(spacing: 0) {
                headerSection
                Spacer(minLength: 0)
                bottomSection
            }
            .padding(.horizontal, 32)
            .padding(.top, 60)
            .padding(.bottom, 56)

            Button(action: onBackToOnboarding) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(OnboardingDesign.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(OnboardingDesign.glassBg)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(OnboardingDesign.glassBorder, lineWidth: 1))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 20)
            .padding(.top, 60)
        }
    }

    private var headerSection: some View {
        VStack(spacing: 0) {
            mascotView
                .padding(.bottom, 24)

            aiBadge
                .padding(.bottom, 20)

            Text("Your personal\nAI companion")
                .font(.system(size: 34, weight: .light))
                .tracking(-1.2)
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .foregroundColor(OnboardingDesign.textPrimary)
                .padding(.bottom, 10)

            Text("Breathe, reflect, and grow with intelligent guidance tailored to you")
                .font(.system(size: 15))
                .foregroundColor(OnboardingDesign.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 240)
                .padding(.bottom, 36)

            aiFeaturesSection
        }
        .frame(maxWidth: .infinity)
    }

    private var mascotView: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.95), Color.white.opacity(0.3)],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 50
                    )
                )
                .frame(width: 72, height: 72)
                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 8)

            Image(systemName: "cloud.fill")
                .font(.system(size: 32))
                .foregroundColor(OnboardingDesign.textPrimary)
        }
    }

    private var aiBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(OnboardingDesign.accentGreen)
                .frame(width: 6, height: 6)
                .shadow(color: OnboardingDesign.accentGreen.opacity(0.8), radius: 3)
                .scaleEffect(badgePulse ? 0.8 : 1)
                .opacity(badgePulse ? 0.7 : 1)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: badgePulse)

            Text("AI-POWERED")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.08 * 11)
                .foregroundColor(OnboardingDesign.accentGreen)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.4))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.65), lineWidth: 1)
        )
        .clipShape(Capsule())
        .onAppear { badgePulse = true }
    }

    private var aiFeaturesSection: some View {
        VStack(spacing: 12) {
            aiFeatureRow(
                iconName: "lightbulb.fill",
                iconColor: OnboardingDesign.accentGreen,
                title: "Smart Insights",
                desc: "Personalized recommendations every day"
            )
            aiFeatureRow(
                iconName: "clock.fill",
                iconColor: OnboardingDesign.accentBlue,
                title: "Adaptive Sessions",
                desc: "Learns your rhythm and adjusts with you"
            )
        }
    }

    private func aiFeatureRow(iconName: String, iconColor: Color, title: String, desc: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.6))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: iconName)
                        .font(.system(size: 18))
                        .foregroundColor(iconColor)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(OnboardingDesign.textPrimary)
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundColor(OnboardingDesign.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(14)
        .padding(.horizontal, 4)
        .background(Color.white.opacity(0.3))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var bottomSection: some View {
        VStack(spacing: 20) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleAppleSignInResult(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 56)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 8)
            .disabled(isSigningIn)

            if isSigningIn {
                ProgressView()
                    .tint(OnboardingDesign.textPrimary)
            }

            if let msg = errorMessage {
                Text(msg)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button(action: onBackToOnboarding) {
                HStack(spacing: 4) {
                    Text("New to Airy?")
                        .foregroundColor(OnboardingDesign.textTertiary)
                    Text("Create account")
                        .fontWeight(.semibold)
                        .foregroundColor(OnboardingDesign.accentGreen)
                }
                .font(.system(size: 14))
            }
            .disabled(isSigningIn)

            #if DEBUG
            Button("Demo login") {
                signInDemo()
            }
            .font(.system(size: 14))
            .foregroundColor(OnboardingDesign.textTertiary)
            .disabled(isSigningIn)
            #endif
        }
        .frame(maxWidth: .infinity)
    }

    private func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) {
        if case .failure(let error) = result {
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            errorMessage = error.localizedDescription
            return
        }
        guard case .success(let authorization) = result,
              let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = appleIDCredential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8)
        else {
            errorMessage = "Sign in failed"
            return
        }
        let email = appleIDCredential.email
        isSigningIn = true
        errorMessage = nil
        Task {
            do {
                await APIClient.shared.setAuthToken(nil)
                let res = try await APIClient.shared.loginWithApple(identityToken: identityToken, email: email)
                await MainActor.run {
                    authStore.setAuth(token: res.token, userId: res.user.id)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            await MainActor.run { isSigningIn = false }
        }
    }

    private func signInDemo() {
        isSigningIn = true
        errorMessage = nil
        Task {
            do {
                await APIClient.shared.setAuthToken(nil)
                let externalId = "demo-\(UUID().uuidString.prefix(8))"
                let res = try await APIClient.shared.registerOrLogin(externalId: externalId, email: nil)
                await MainActor.run {
                    authStore.setAuth(token: res.token, userId: res.user.id)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            await MainActor.run { isSigningIn = false }
        }
    }
}

#Preview {
    ZStack {
        OnboardingGradientBackground()
        OnboardingView(onBackToOnboarding: {})
    }
    .environment(AuthStore())
}
