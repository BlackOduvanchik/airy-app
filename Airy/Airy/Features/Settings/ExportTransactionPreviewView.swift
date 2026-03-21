//
//  ExportTransactionPreviewView.swift
//  Airy
//
//  Preview list of transactions that will be included in the CSV export.
//

import SwiftUI

struct ExportTransactionPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeProvider.self) private var theme
    let transactions: [Transaction]

    var body: some View {
        ZStack {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            if transactions.isEmpty {
                Text("No transactions")
                    .font(.system(size: 15))
                    .foregroundColor(theme.textSecondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(transactions.enumerated()), id: \.element.id) { index, tx in
                            transactionRow(tx, showBottomBorder: index < transactions.count - 1)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
        }
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
                Text("TRANSACTIONS")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(transactions.count)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.textSecondary)
            }
        }
    }

    // MARK: - Row

    private func transactionRow(_ tx: Transaction, showBottomBorder: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.merchant ?? tx.title ?? "Unknown")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)
                Text(formatDate(tx.transactionDate))
                    .font(.system(size: 12))
                    .foregroundColor(theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(AppFormatters.formatTransaction(amount: tx.amountOriginal, currency: tx.currencyOriginal, isIncome: tx.type.lowercased() == "income"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tx.type.lowercased() == "income" ? theme.incomeColor : theme.expenseColor)
        }
        .padding(.horizontal, 4)
        .frame(height: 56)
        .overlay(
            Group {
                if showBottomBorder {
                    Rectangle()
                        .fill(Color.white.opacity(theme.isDark ? 0.06 : 0.15))
                        .frame(height: 1)
                }
            },
            alignment: .bottom
        )
    }

    // MARK: - Formatters

    private func formatAmount(_ amount: Double, _ currency: String) -> String {
        AppFormatters.formatTotal(amount: amount, currency: currency)
    }

    private func formatDate(_ dateStr: String) -> String {
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        input.timeZone = TimeZone(identifier: "UTC")
        guard let date = input.date(from: String(dateStr.prefix(10))) else { return dateStr }
        let output = DateFormatter()
        output.dateFormat = "d MMM yyyy"
        return output.string(from: date)
    }
}
