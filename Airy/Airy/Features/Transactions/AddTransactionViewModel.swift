//
//  AddTransactionViewModel.swift
//  Airy
//

import SwiftUI

/// Categories matching backend; grid shows Food, Travel, Home, Other.
enum TransactionCategory: String, CaseIterable {
    case other
    case food
    case groceries
    case food_delivery
    case transport
    case subscriptions
    case entertainment
    case bills
    case health
    case fees
    case transfers
    case income

    var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

/// Four categories shown in the add/edit sheet grid (design: Food, Travel, Home, Other).
enum AddSheetCategory: String, CaseIterable {
    case food
    case transport
    case bills
    case other

    var displayName: String {
        switch self {
        case .food: return "Food"
        case .transport: return "Travel"
        case .bills: return "Home"
        case .other: return "Other"
        }
    }

    var transactionCategory: TransactionCategory {
        switch self {
        case .food: return .food
        case .transport: return .transport
        case .bills: return .bills
        case .other: return .other
        }
    }

    init(from category: TransactionCategory) {
        switch category {
        case .food, .groceries, .food_delivery: self = .food
        case .transport: self = .transport
        case .bills, .subscriptions, .entertainment, .health, .fees: self = .bills
        default: self = .other
        }
    }
}

@Observable
final class AddTransactionViewModel {
    var amountText = ""
    var selectedCurrency = "USD"
    var merchant = ""
    var selectedCategory: TransactionCategory = .other
    var selectedSheetCategory: AddSheetCategory = .food
    var transactionType: String = "expense"
    var dateTime = Date()
    var note = ""
    var isSubmitting = false
    var errorMessage: String?
    var didSucceed = false

    /// When set, we're in edit mode and submit calls PATCH.
    var existingTransaction: Transaction?

    static let currencies = ["USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD"]

    var amount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "."))
    }

    var isEditMode: Bool { existingTransaction != nil }

    var primaryButtonTitle: String {
        isEditMode ? "Save" : "Add Transaction"
    }

    var sheetTitle: String {
        isEditMode ? "Edit Entry" : "New Entry"
    }

    init(existing: Transaction? = nil) {
        self.existingTransaction = existing
        if let tx = existing {
            amountText = String(format: "%.2f", tx.amountOriginal)
            selectedCurrency = tx.currencyOriginal
            merchant = tx.merchant ?? ""
            if let cat = TransactionCategory(rawValue: tx.category) {
                selectedCategory = cat
                selectedSheetCategory = AddSheetCategory(from: cat)
            }
            transactionType = tx.type.lowercased()
            note = tx.title ?? ""
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            if let timeStr = tx.transactionTime, let d = parseDateTime(dateStr: tx.transactionDate, timeStr: timeStr) {
                dateTime = d
            } else if let d = formatter.date(from: String(tx.transactionDate.prefix(10))) {
                dateTime = d
            }
        }
    }

    private func parseDateTime(dateStr: String, timeStr: String) -> Date? {
        let dStr = String(dateStr.prefix(10))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: "\(dStr) \(timeStr)")
    }

    func selectSheetCategory(_ cat: AddSheetCategory) {
        selectedSheetCategory = cat
        selectedCategory = cat.transactionCategory
    }

    func submit() async {
        guard let amt = amount, amt > 0 else {
            errorMessage = "Enter a valid amount"
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { Task { @MainActor in isSubmitting = false } }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: dateTime)
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeStr = timeFormatter.string(from: dateTime)

        if let existing = existingTransaction {
            let body = UpdateTransactionBody(
                amountOriginal: amt,
                amountBase: amt,
                merchant: merchant.isEmpty ? nil : merchant,
                category: selectedCategory.rawValue,
                subcategory: nil,
                transactionDate: dateStr,
                comment: note.isEmpty ? nil : note
            )
            do {
                _ = try await APIClient.shared.updateTransaction(id: existing.id, body: body)
                await MainActor.run { didSucceed = true }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        } else {
            let body = CreateTransactionBody(
                type: transactionType,
                amountOriginal: amt,
                currencyOriginal: selectedCurrency,
                amountBase: amt,
                baseCurrency: selectedCurrency,
                merchant: merchant.isEmpty ? nil : merchant,
                title: note.isEmpty ? nil : note,
                transactionDate: dateStr,
                transactionTime: timeStr,
                category: selectedCategory.rawValue,
                subcategory: nil,
                isSubscription: selectedCategory == .subscriptions,
                comment: note.isEmpty ? nil : note,
                sourceType: "manual"
            )
            do {
                _ = try await APIClient.shared.createTransaction(body)
                await MainActor.run { didSucceed = true }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}
