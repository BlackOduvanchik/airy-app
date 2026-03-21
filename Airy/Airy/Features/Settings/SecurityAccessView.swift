//
//  SecurityAccessView.swift
//  Airy
//
//  Security & Access: Face ID and Passcode toggles with verification.
//

import SwiftUI
import LocalAuthentication

struct SecurityAccessView: View {
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var faceIdEnabled: Bool
    @State private var passcodeEnabled: Bool
    @State private var showPasscodeSetup = false
    @State private var showPasscodeVerify = false
    @State private var wrongPasscode = false

    init() {
        _faceIdEnabled = State(initialValue: UserDefaults.standard.bool(forKey: "airy.security.faceId"))
        _passcodeEnabled = State(initialValue: UserDefaults.standard.bool(forKey: "airy.security.passcode"))
    }

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    faceIdCard
                    passcodeCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            ToolbarItem(placement: .principal) {
                Text(L("security_title"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
            }
        }
        .sheet(isPresented: $showPasscodeSetup) {
            passcodeSetupSheet
                .environment(theme)
        }
        .sheet(isPresented: $showPasscodeVerify) {
            passcodeVerifySheet
                .environment(theme)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("security_caption").uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(theme.textTertiary)
            Text(L("security_title"))
                .font(.system(size: 34, weight: .light))
                .tracking(-1)
                .foregroundColor(theme.textPrimary)
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    // MARK: - Face ID Card

    private var faceIdCard: some View {
        securityCard(
            icon: {
                Image(systemName: "faceid")
                    .font(.system(size: 22))
                    .foregroundColor(theme.accentGreen)
            },
            title: L("security_faceid_title"),
            description: L("security_faceid_desc"),
            isOn: Binding(
                get: { faceIdEnabled },
                set: { newValue in
                    if newValue {
                        // Enable → verify Face ID first
                        Task {
                            let success = await AppLockManager.shared.verifyBiometric()
                            if success {
                                faceIdEnabled = true
                                UserDefaults.standard.set(true, forKey: "airy.security.faceId")
                            }
                        }
                    } else {
                        // Disable → verify Face ID first
                        Task {
                            let success = await AppLockManager.shared.verifyBiometric()
                            if success {
                                faceIdEnabled = false
                                UserDefaults.standard.set(false, forKey: "airy.security.faceId")
                            }
                        }
                    }
                }
            )
        )
    }

    // MARK: - Passcode Card

    private var passcodeCard: some View {
        securityCard(
            icon: {
                Image(systemName: "lock.fill")
                    .font(.system(size: 22))
                    .foregroundColor(theme.accentGreen)
            },
            title: L("security_passcode_title"),
            description: L("security_passcode_desc"),
            isOn: Binding(
                get: { passcodeEnabled },
                set: { newValue in
                    if newValue {
                        // Enable → show passcode setup sheet
                        showPasscodeSetup = true
                    } else {
                        // Disable → verify current passcode first
                        showPasscodeVerify = true
                    }
                }
            )
        )
    }

    // MARK: - Passcode Setup Sheet

    private var passcodeSetupSheet: some View {
        ZStack {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            VStack {
                Spacer()
                PasscodeEntryView(mode: .setup, onComplete: { code in
                    AppLockManager.shared.setPasscode(code)
                    passcodeEnabled = true
                    showPasscodeSetup = false
                }, onCancel: {
                    showPasscodeSetup = false
                })
                Spacer()
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }

    // MARK: - Passcode Verify Sheet (to disable)

    private var passcodeVerifySheet: some View {
        ZStack {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            VStack {
                Spacer()
                PasscodeEntryView(mode: .verify, onComplete: { code in
                    if AppLockManager.shared.verifyPasscode(code) {
                        AppLockManager.shared.removePasscode()
                        passcodeEnabled = false
                        showPasscodeVerify = false
                    } else {
                        wrongPasscode.toggle()
                    }
                }, onCancel: {
                    showPasscodeVerify = false
                })
                Spacer()
            }
        }
        .sensoryFeedback(.error, trigger: wrongPasscode)
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }

    // MARK: - Card Helper

    private func securityCard<Icon: View>(
        @ViewBuilder icon: () -> Icon,
        title: String,
        description: String,
        isOn: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 12) {
                    icon()
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(theme.isDark ? 0.08 : 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                }
                Spacer()
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(theme.accentGreen)
            }
            Text(description)
                .font(.system(size: 14))
                .foregroundColor(theme.textSecondary)
                .lineSpacing(2)
        }
        .padding(20)
        .background(theme.isDark ? AnyShapeStyle(theme.glassBg) : AnyShapeStyle(.ultraThinMaterial))
        .overlay(theme.isDark ? nil : theme.glassBg.opacity(0.5).allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(theme.glassBorder, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: theme.isDark ? Color.black.opacity(0.4) : theme.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
    }
}
