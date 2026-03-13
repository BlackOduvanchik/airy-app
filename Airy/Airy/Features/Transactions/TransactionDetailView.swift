//
//  TransactionDetailView.swift
//  Airy
//

import SwiftUI

struct TransactionDetailView: View {
    let transaction: Transaction
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var showEditSheet = false

    var body: some View {
        List {
            Section("Details") {
                LabeledContent("Merchant", value: transaction.merchant ?? "—")
                LabeledContent("Amount", value: "\(transaction.amountOriginal) \(transaction.currencyOriginal)")
                LabeledContent("Category", value: transaction.category)
                LabeledContent("Date", value: transaction.transactionDate)
                LabeledContent("Type", value: transaction.type)
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
                Button("Edit") { showEditSheet = true }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete", role: .destructive) {
                    Task { await deleteTransaction() }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            AddTransactionView(transaction: transaction, onSuccess: { dismiss() })
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
