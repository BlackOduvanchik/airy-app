//
//  OnboardingView.swift
//  Airy
//

import AuthenticationServices
import SwiftUI

struct OnboardingView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Text("Airy")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Your AI-first expense tracker")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleAppleSignInResult(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .disabled(isSigningIn)
            if isSigningIn { ProgressView() }
            if let msg = errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            #if DEBUG
            Button("Demo login") {
                signInDemo()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .disabled(isSigningIn)
            #endif
        }
        .padding()
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
    OnboardingView()
        .environment(AuthStore())
}
