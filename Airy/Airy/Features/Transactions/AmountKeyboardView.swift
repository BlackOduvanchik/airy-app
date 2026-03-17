//
//  AmountKeyboardView.swift
//  Airy
//
//  Custom calculator-style keyboard for amount input. Supports expressions like 5*5-5.
//

import SwiftUI

private let currencySymbols: [String: String] = [
    "USD": "$", "EUR": "€", "GBP": "£", "RUB": "₽", "JPY": "¥", "CHF": "Fr", "CAD": "C$", "AUD": "A$"
]

/// Evaluates a calculator expression (e.g. "5*5-5") and returns the result, or nil if invalid.
/// When expression ends with operator (e.g. "8+"), returns the result of the part before the operator
/// so the display shows the last valid number instead of 0.
func evaluateAmountExpression(_ expr: String) -> Double? {
    var s = expr.trimmingCharacters(in: .whitespaces)
    guard !s.isEmpty else { return 0 }
    let opChars = CharacterSet(charactersIn: "+-*/×÷−")
    if let last = s.unicodeScalars.last, opChars.contains(last) {
        // Expression ends with operator - evaluate without it for display (e.g. "8+" → show 8)
        let trimmed = String(s.dropLast()).trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return 0 }
        return evaluateAmountExpression(trimmed)
    }
    s = s.replacingOccurrences(of: "×", with: "*")
    s = s.replacingOccurrences(of: "÷", with: "/")
    s = s.replacingOccurrences(of: "−", with: "-")
    // Sanitize incomplete decimals: "5." → "5.0", standalone "." → "0.0"
    s = s.replacingOccurrences(of: #"\.(?=[+\-*/]|$)"#, with: ".0", options: .regularExpression)
    if s == "." || s == ".0" { return 0 }
    let nsExpr = NSExpression(format: s)
    guard let result = nsExpr.expressionValue(with: nil, context: nil) as? NSNumber else { return nil }
    return result.doubleValue
}

struct AmountKeyboardView: View {
    @Binding var expression: String
    @Binding var amountText: String
    @Binding var transactionType: String
    @Binding var selectedCurrency: String
    let currencies: [String]
    let onDismiss: () -> Void

    @State private var showCurrencyPicker = false

    private var evaluatedResult: Double {
        evaluateAmountExpression(expression) ?? 0
    }

    private var displayResult: String {
        String(format: "%.2f", evaluatedResult)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(["expense", "income"], id: \.self) { type in
                        Button { transactionType = type } label: {
                            Text(type == "expense" ? "Expense" : "Income")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(transactionType == type ? OnboardingDesign.textPrimary : OnboardingDesign.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(transactionType == type ? Color.white : Color.clear)
                                        .shadow(color: transactionType == type ? Color.black.opacity(0.07) : .clear, radius: 3, x: 0, y: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color.black.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button { showCurrencyPicker = true } label: {
                    Text("\(selectedCurrency) (\(currencySymbols[selectedCurrency] ?? "$"))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.8), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    if !expression.isEmpty {
                        amountText = displayResult
                        expression = ""
                    }
                    onDismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textSecondary)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.8), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 10)

            // Keys grid
            GeometryReader { g in
                let gap: CGFloat = 8
                let col = (g.size.width - gap * 3) / 4
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        keyButton("7")
                        keyButton("8")
                        keyButton("9")
                        keyButton("÷", isOp: true)
                    }
                    HStack(spacing: gap) {
                        keyButton("4")
                        keyButton("5")
                        keyButton("6")
                        keyButton("×", isOp: true)
                    }
                    HStack(spacing: gap) {
                        keyButton("1")
                        keyButton("2")
                        keyButton("3")
                        keyButton("−", isOp: true)
                    }
                    HStack(spacing: gap) {
                        keyButton("0").frame(width: col * 2 + gap)
                        keyButton(".")
                        keyButton("+", isOp: true)
                    }
                    HStack(spacing: gap) {
                        keyButton("⌫", isDelete: true).frame(width: col * 3 + gap * 2)
                        keyButton("OK", isConfirm: true)
                    }
                }
            }
            .frame(height: 52 * 5 + 8 * 4)
        }
        .padding(14)
        .padding(.bottom, 32)
        .background(Color(red: 220/255, green: 230/255, blue: 225/255).opacity(0.92))
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
                .padding(.top, -1)
        )
        .sheet(isPresented: $showCurrencyPicker) {
            currencyPickerSheet
        }
    }

    @ViewBuilder
    private func keyButton(_ key: String, isOp: Bool = false, isDelete: Bool = false, isConfirm: Bool = false) -> some View {
        let isOperator = isOp || ["+", "−", "×", "÷"].contains(key)
        Button {
            if isConfirm {
                if !expression.isEmpty {
                    amountText = displayResult
                    expression = ""
                }
                onDismiss()
            } else if key == "⌫" || isDelete {
                if !expression.isEmpty { expression = String(expression.dropLast()) }
            } else {
                if isOp {
                    let ops = ["+", "−", "×", "÷"]
                    let last = expression.last.map(String.init) ?? ""
                    if ops.contains(last) {
                        expression = String(expression.dropLast()) + key
                        return
                    }
                }
                if key == "." {
                    let segments = expression.components(separatedBy: CharacterSet(charactersIn: "+−×÷"))
                    if let last = segments.last, last.contains(".") { return }
                }
                expression += key
            }
        } label: {
            Group {
                if key == "⌫" {
                    Image(systemName: "delete.left").font(.system(size: 20, weight: .medium))
                } else {
                    Text(key).font(.system(size: isConfirm ? 14 : 20, weight: isConfirm ? .bold : .regular))
                }
            }
            .foregroundColor(
                isConfirm ? .white :
                isDelete ? Color(red: 192/255, green: 98/255, blue: 90/255) :
                isOperator ? OnboardingDesign.accentGreen :
                OnboardingDesign.textPrimary
            )
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        isConfirm ? OnboardingDesign.textPrimary :
                        isDelete ? Color(red: 224/255, green: 122/255, blue: 122/255).opacity(0.12) :
                        isOperator ? OnboardingDesign.accentGreen.opacity(0.15) :
                        Color.white.opacity(0.65)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                isConfirm ? Color.clear :
                                isDelete ? Color(red: 224/255, green: 122/255, blue: 122/255).opacity(0.2) :
                                isOperator ? OnboardingDesign.accentGreen.opacity(0.25) :
                                Color.white.opacity(0.8),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: Color.black.opacity(isConfirm ? 0.2 : 0.05), radius: isConfirm ? 7 : 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var currencyPickerSheet: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.black.opacity(0.08))
                .frame(width: 36, height: 5)
                .padding(.top, 16)
                .padding(.bottom, 20)
            HStack {
                Text("Currency")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(OnboardingDesign.textPrimary)
                Spacer()
                Button { showCurrencyPicker = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 16)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(currencies, id: \.self) { code in
                        Button {
                            selectedCurrency = code
                            showCurrencyPicker = false
                        } label: {
                            HStack(spacing: 14) {
                                Text(currencySymbols[code] ?? "$")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(OnboardingDesign.accentGreen)
                                    .frame(width: 36, height: 36)
                                    .background(OnboardingDesign.accentGreen.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(code)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(OnboardingDesign.textPrimary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if selectedCurrency == code {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(OnboardingDesign.accentGreen)
                                }
                            }
                            .padding(14)
                            .padding(.horizontal, 16)
                            .background(selectedCurrency == code ? Color.white : Color.white.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(selectedCurrency == code ? OnboardingDesign.accentGreen.opacity(0.3) : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
        .background(Color(red: 220/255, green: 230/255, blue: 225/255).opacity(0.97))
        .background(.ultraThinMaterial)
        .presentationDetents([.medium])
    }
}
