//
//  AmountKeyboardView.swift
//  Airy
//
//  Custom calculator-style keyboard for amount input. Supports expressions like 5*5-5.
//

import SwiftUI


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
    @Environment(ThemeProvider.self) private var theme
    @Binding var expression: String
    @Binding var amountText: String
    @Binding var transactionType: String
    @Binding var selectedCurrency: String
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
                            Text(type == "expense" ? L("common_expense") : L("common_income"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(transactionType == type ? theme.textPrimary : theme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(transactionType == type ? Color.white.opacity(theme.isDark ? 0.15 : 1) : Color.clear)
                                        .shadow(color: transactionType == type ? Color.black.opacity(0.07) : .clear, radius: 3, x: 0, y: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(theme.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button { showCurrencyPicker = true } label: {
                    Text("\(selectedCurrency) (\(AddTransactionViewModel.currencySymbol(for: selectedCurrency)))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(theme.isDark ? 0.08 : 0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(theme.isDark ? 0.12 : 0.8), lineWidth: 1))
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
                        .foregroundColor(theme.textSecondary)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(theme.isDark ? 0.08 : 0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(theme.isDark ? 0.12 : 0.8), lineWidth: 1))
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
        .background(theme.bgTop.opacity(0.92))
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(theme.glassBorder, lineWidth: 1)
                .padding(.top, -1)
        )
        .sheet(isPresented: $showCurrencyPicker) {
            TransactionCurrencyPickerSheet(selectedCurrency: $selectedCurrency)
                .themed(theme)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.bgTop)
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
                isOperator ? theme.accentGreen :
                theme.textPrimary
            )
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        isConfirm ? theme.textPrimary :
                        isDelete ? Color(red: 224/255, green: 122/255, blue: 122/255).opacity(0.12) :
                        isOperator ? theme.accentGreen.opacity(0.15) :
                        Color.white.opacity(theme.isDark ? 0.08 : 0.65)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                isConfirm ? Color.clear :
                                isDelete ? Color(red: 224/255, green: 122/255, blue: 122/255).opacity(0.2) :
                                isOperator ? theme.accentGreen.opacity(0.25) :
                                Color.white.opacity(theme.isDark ? 0.12 : 0.8),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: Color.black.opacity(isConfirm ? 0.2 : 0.05), radius: isConfirm ? 7 : 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

}
