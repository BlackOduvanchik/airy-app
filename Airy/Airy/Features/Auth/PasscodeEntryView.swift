//
//  PasscodeEntryView.swift
//  Airy
//
//  4-digit passcode entry. Used for setup (enter + confirm) and unlock/verify modes.
//

import SwiftUI

struct PasscodeEntryView: View {
    enum Mode {
        case setup          // Enter new passcode + confirm
        case verify         // Verify existing passcode (to disable toggle)
        case unlock         // Unlock app from lock screen
    }

    @Environment(ThemeProvider.self) private var theme
    let mode: Mode
    let onComplete: (String) -> Void
    var onCancel: (() -> Void)?

    @State private var code = ""
    @State private var confirmCode = ""
    @State private var isConfirming = false
    @State private var shake = false
    @State private var errorMessage = ""

    private let codeLength = 4

    var body: some View {
        VStack(spacing: 32) {
            if mode != .unlock {
                Spacer().frame(height: 20)
            }

            // Icon
            Image(systemName: mode == .setup && !isConfirming ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 32, weight: .thin))
                .foregroundColor(theme.accentGreen)
                .frame(width: 64, height: 64)
                .background(Color.white.opacity(theme.isDark ? 0.08 : 0.5))
                .clipShape(Circle())

            // Title
            Text(titleText)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(theme.textPrimary)

            // Subtitle
            Text(subtitleText)
                .font(.system(size: 14))
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)

            // Dots
            HStack(spacing: 16) {
                ForEach(0..<codeLength, id: \.self) { index in
                    Circle()
                        .fill(index < currentCode.count ? theme.accentGreen : Color.white.opacity(theme.isDark ? 0.15 : 0.4))
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .stroke(theme.accentGreen.opacity(index < currentCode.count ? 0 : 0.3), lineWidth: 1)
                        )
                }
            }
            .offset(x: shake ? -12 : 0)
            .animation(shake ? .default.repeatCount(3, autoreverses: true).speed(6) : .default, value: shake)
            .padding(.vertical, 8)

            // Error
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.red.opacity(0.8))
                    .transition(.opacity)
            }

            // Numpad
            numpad
                .padding(.horizontal, 40)

            if mode != .unlock, let onCancel {
                Button {
                    onCancel()
                } label: {
                    Text(L("common_cancel"))
                        .font(.system(size: 15))
                        .foregroundColor(theme.textSecondary)
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 24)
    }

    private var currentCode: String {
        isConfirming ? confirmCode : code
    }

    private var titleText: String {
        switch mode {
        case .setup:
            return isConfirming ? L("passcode_confirm_title") : L("passcode_create_title")
        case .verify:
            return L("passcode_enter_title")
        case .unlock:
            return L("passcode_enter_title")
        }
    }

    private var subtitleText: String {
        switch mode {
        case .setup:
            return isConfirming ? L("passcode_confirm_subtitle") : L("passcode_create_subtitle")
        case .verify:
            return L("passcode_verify_subtitle")
        case .unlock:
            return L("lock_subtitle_passcode")
        }
    }

    // MARK: - Numpad

    private var numpad: some View {
        VStack(spacing: 12) {
            ForEach(numpadRows, id: \.self) { row in
                HStack(spacing: 16) {
                    ForEach(row, id: \.self) { key in
                        numpadButton(key)
                    }
                }
            }
        }
    }

    private var numpadRows: [[String]] {
        [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            ["", "0", "⌫"],
        ]
    }

    private func numpadButton(_ key: String) -> some View {
        Group {
            if key.isEmpty {
                Color.clear.frame(width: 72, height: 56)
            } else if key == "⌫" {
                Button {
                    deleteDigit()
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 20))
                        .foregroundColor(theme.textPrimary)
                        .frame(width: 72, height: 56)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    appendDigit(key)
                } label: {
                    Text(key)
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(theme.textPrimary)
                        .frame(width: 72, height: 56)
                        .background(Color.white.opacity(theme.isDark ? 0.08 : 0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(theme.isDark ? 0.05 : 0.4), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Input Logic

    private func appendDigit(_ digit: String) {
        errorMessage = ""
        if isConfirming {
            guard confirmCode.count < codeLength else { return }
            confirmCode += digit
            if confirmCode.count == codeLength {
                handleConfirmComplete()
            }
        } else {
            guard code.count < codeLength else { return }
            code += digit
            if code.count == codeLength {
                handleCodeComplete()
            }
        }
    }

    private func deleteDigit() {
        if isConfirming {
            if !confirmCode.isEmpty { confirmCode.removeLast() }
        } else {
            if !code.isEmpty { code.removeLast() }
        }
        errorMessage = ""
    }

    private func handleCodeComplete() {
        switch mode {
        case .setup:
            // Move to confirm step
            withAnimation {
                isConfirming = true
            }
        case .verify, .unlock:
            onComplete(code)
        }
    }

    private func handleConfirmComplete() {
        if confirmCode == code {
            onComplete(code)
        } else {
            // Mismatch — shake and reset confirm
            errorMessage = L("passcode_mismatch")
            triggerShake()
            confirmCode = ""
        }
    }

    private func triggerShake() {
        shake = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            shake = false
        }
    }

    /// Called externally when verification fails (wrong passcode on verify/unlock)
    func shakeAndReset() {
        triggerShake()
        code = ""
        confirmCode = ""
    }
}
