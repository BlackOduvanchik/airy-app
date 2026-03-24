//
//  TransactionDetailView.swift
//  Airy
//

import SwiftUI

struct TransactionDetailView: View {
    let transaction: Transaction
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var showEditSheet = false

    var body: some View {
        List {
            Section(L("txdetail_details")) {
                LabeledContent(L("txdetail_merchant"), value: transaction.merchant ?? "—")
                LabeledContent(L("txdetail_amount"), value: "\(transaction.amountOriginal) \(transaction.currencyOriginal)")
                LabeledContent(L("txdetail_category"), value: transaction.category)
                LabeledContent(L("txdetail_date"), value: transaction.transactionDate)
                LabeledContent(L("txdetail_type"), value: transaction.type)
            }
            if let err = errorMessage {
                Section {
                    Text(err)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(transaction.merchant ?? "Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L("common_edit")) { showEditSheet = true }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button(L("common_delete"), role: .destructive) {
                    Task { await deleteTransaction() }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            AddTransactionView(transaction: transaction, onSuccess: { dismiss() })
                .themed(theme)
        }
    }

    private func deleteTransaction() async {
        do {
            try LocalDataStore.shared.deleteTransaction(id: transaction.id)
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}

#Preview {
    NavigationStack {
        TransactionDetailView(transaction: Transaction(
            id: "1", type: "expense", amountOriginal: 12.99, currencyOriginal: "USD",
            amountBase: 12.99, baseCurrency: "USD", merchant: "Coffee Shop", title: nil,
            transactionDate: "2025-03-10", transactionTime: nil, category: "food", subcategory: nil,
            isSubscription: false, subscriptionInterval: nil, sourceType: "manual", createdAt: nil, updatedAt: nil
        ))
    }
}
