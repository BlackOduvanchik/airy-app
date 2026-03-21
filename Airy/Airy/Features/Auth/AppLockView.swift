//
//  AppLockView.swift
//  Airy
//
//  Full-screen lock overlay. Supports Face ID, Passcode, or both.
//

import SwiftUI

struct AppLockView: View {
    @Environment(ThemeProvider.self) private var theme
    @Environment(AppLockManager.self) private var lockManager
    @State private var wrongPasscode = false

    var body: some View {
        ZStack {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            if lockManager.showPasscodeInput {
                passcodeUnlockView
            } else {
                faceIdView
            }
        }
    }

    // MARK: - Face ID View

    private var faceIdView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 96, height: 96)
                    .shadow(color: theme.accentGreen.opacity(0.4), radius: 30)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.9), Color.white.opacity(0.2)],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 50
                        )
                    )
                    .frame(width: 84, height: 84)
                    .shadow(color: Color.white.opacity(0.8), radius: 2, x: 0, y: -1)
                    .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 8)

                Image(systemName: "faceid")
                    .font(.system(size: 36, weight: .thin))
                    .foregroundColor(theme.accentGreen)
            }

            Text(L("lock_title"))
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(theme.textPrimary)

            Text(L("lock_subtitle"))
                .font(.system(size: 14))
                .foregroundColor(theme.textSecondary)

            if lockManager.isPasscodeEnabled {
                Button {
                    lockManager.switchToPasscode()
                } label: {
                    Text(L("lock_use_passcode"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(theme.accentGreen)
                        .padding(.top, 12)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { lockManager.authenticate() }
        .task { lockManager.authenticate() }
    }

    // MARK: - Passcode Unlock View

    private var passcodeUnlockView: some View {
        VStack {
            Spacer()

            PasscodeEntryView(mode: .unlock) { code in
                if !lockManager.unlockWithPasscode(code) {
                    wrongPasscode.toggle()
                }
            }

            if lockManager.isFaceIdEnabled {
                Button {
                    lockManager.showPasscodeInput = false
                    lockManager.authenticate()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "faceid")
                            .font(.system(size: 15))
                        Text(L("lock_use_faceid"))
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(theme.accentGreen)
                    .padding(.top, 16)
                }
            }

            Spacer()
        }
        .sensoryFeedback(.error, trigger: wrongPasscode)
    }
}
