//
//  PendingReviewView.swift
//  Airy
//

import SwiftUI

struct PendingReviewView: View {
    @State private var viewModel = PendingReviewViewModel()
    @State private var editPending: PendingTransaction?
    @State private var editOverrides = ConfirmPendingOverrides()

    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.pending.isEmpty {
                Text("No pending transactions")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.pending) { item in
                    PendingRow(
                        transaction: item,
                        onConfirm: { Task { await viewModel.confirm(id: item.id) } },
                        onReject: { Task { await viewModel.reject(id: item.id) } },
                        onEdit: {
                            editOverrides = overridesFromPayload(item.decodedPayload)
                            editPending = item
                        }
                    )
                }
            }
        }
        .navigationTitle("Pending review")
        .task { await viewModel.load() }
        .sheet(item: $editPending) { pending in
            PendingEditSheet(
                pending: pending,
                overrides: $editOverrides,
                onConfirm: { submittedOverrides in
                    Task {
                        await viewModel.confirm(id: pending.id, overrides: submittedOverrides.isEmpty ? nil : submittedOverrides)
                        await MainActor.run { editPending = nil }
                    }
                },
                onCancel: { editPending = nil }
            )
        }
    }

    private func overridesFromPayload(_ payload: PendingTransactionPayload?) -> ConfirmPendingOverrides {
        guard let p = payload else { return ConfirmPendingOverrides() }
        return ConfirmPendingOverrides(
            type: p.type,
            amountOriginal: p.amountOriginal,
            currencyOriginal: p.currencyOriginal,
            amountBase: p.amountBase,
            baseCurrency: p.baseCurrency,
            merchant: p.merchant,
            transactionDate: p.transactionDate,
            transactionTime: p.transactionTime,
            category: p.category,
            subcategory: p.subcategory
        )
    }
}

private struct PendingRow: View {
    let transaction: PendingTransaction
    let onConfirm: () -> Void
    let onReject: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack {
            if let p = transaction.decodedPayload {
                VStack(alignment: .leading) {
                    Text(p.merchant ?? "Transaction")
                        .font(.headline)
                    if let amount = p.amountOriginal, let currency = p.currencyOriginal, !currency.isEmpty {
                        Text("\(amount) \(currency)")
                            .font(.subheadline)
                    } else if let amount = p.amountOriginal {
                        Text(String(format: "%.2f", amount))
                            .font(.subheadline)
                    }
                }
            } else {
                Text("Transaction")
            }
            Spacer()
            HStack(spacing: 8) {
                Button("Edit") { onEdit() }
                    .buttonStyle(.bordered)
                Button("Reject", role: .destructive) { onReject() }
                    .buttonStyle(.bordered)
                Button("Confirm", action: onConfirm)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct PendingEditSheet: View {
    let pending: PendingTransaction
    @Binding var overrides: ConfirmPendingOverrides
    let onConfirm: (ConfirmPendingOverrides) -> Void
    let onCancel: () -> Void

    @State private var amountText: String = ""
    @State private var currencyText: String = ""
    @State private var merchantText: String = ""
    @State private var dateText: String = ""
    @State private var categoryText: String = ""
    @State private var typeText: String = "expense"

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField("Currency", text: $currencyText)
                        .textInputAutocapitalization(.characters)
                }
                Section("Details") {
                    TextField("Merchant", text: $merchantText)
                    TextField("Date (YYYY-MM-DD)", text: $dateText)
                    TextField("Category", text: $categoryText)
                    Picker("Type", selection: $typeText) {
                        Text("Expense").tag("expense")
                        Text("Income").tag("income")
                    }
                }
            }
            .navigationTitle("Edit transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { submitOverrides() }
                }
            }
            .onAppear { fillFromOverrides() }
        }
    }

    private func fillFromOverrides() {
        amountText = overrides.amountOriginal.map { String($0) } ?? ""
        currencyText = overrides.currencyOriginal ?? ""
        merchantText = overrides.merchant ?? ""
        dateText = overrides.transactionDate ?? ""
        categoryText = overrides.category ?? ""
        typeText = overrides.type ?? "expense"
    }

    private func submitOverrides() {
        let submitted = ConfirmPendingOverrides(
            type: typeText,
            amountOriginal: Double(amountText),
            currencyOriginal: currencyText.isEmpty ? nil : currencyText,
            amountBase: nil,
            baseCurrency: nil,
            merchant: merchantText.isEmpty ? nil : merchantText,
            transactionDate: dateText.isEmpty ? nil : dateText,
            transactionTime: nil,
            category: categoryText.isEmpty ? nil : categoryText,
            subcategory: nil
        )
        overrides = submitted
        onConfirm(submitted)
    }
}

#Preview {
    NavigationStack {
        PendingReviewView()
    }
}
