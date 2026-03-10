//
//  AppleSignInService.swift
//  Airy
//

import AuthenticationServices
import Foundation

struct AppleSignInResult {
    let identityToken: String
    let email: String?
    let fullName: PersonNameComponents?
    let userIdentifier: String
}

enum AppleSignInError: Error {
    case noIdentityToken
    case invalidIdentityToken
    case cancelled
    case unknown(Error)
}

@MainActor
final class AppleSignInService: NSObject {
    private var continuation: CheckedContinuation<AppleSignInResult, Error>?

    func signIn() async throws -> AppleSignInResult {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }
}

extension AppleSignInService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        _ controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                continuation?.resume(throwing: AppleSignInError.unknown(NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid credential type"])))
                continuation = nil
                return
            }
            guard let tokenData = appleIDCredential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                continuation?.resume(throwing: AppleSignInError.noIdentityToken)
                continuation = nil
                return
            }
            let email = appleIDCredential.email
            let fullName = appleIDCredential.fullName
            let userIdentifier = appleIDCredential.user
            let result = AppleSignInResult(
                identityToken: identityToken,
                email: email,
                fullName: fullName,
                userIdentifier: userIdentifier
            )
            continuation?.resume(returning: result)
            continuation = nil
        }
    }

    nonisolated func authorizationController(
        _ controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            let err = (error as NSError)
            if err.code == ASAuthorizationError.canceled.rawValue {
                continuation?.resume(throwing: AppleSignInError.cancelled)
            } else {
                continuation?.resume(throwing: AppleSignInError.unknown(error))
            }
            continuation = nil
        }
    }
}

extension AppleSignInService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}
