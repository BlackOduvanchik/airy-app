//
//  AddTransactionViewModel.swift
//  Airy
//
//  Local-only: create/update via SwiftData.
//

import SwiftUI

/// Legacy categories for backward compatibility with existing transactions.
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

@Observable
final class AddTransactionViewModel {
    var amountText = ""
    var selectedCurrency = "USD"
    var merchant = ""
    var selectedCategoryId: String?
    var selectedSubcategoryId: String?
    var transactionType: String = "expense"
    var dateTime = Date()
    var note = ""
    var isSubmitting = false
    var errorMessage: String?
    var didSucceed = false

    var existingTransaction: Transaction?
    var isPendingEditMode: Bool = false

    static let currencies = ["USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "UAH", "RUB"]

    var amount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "."))
    }

    var isEditMode: Bool { existingTransaction != nil }

    var primaryButtonTitle: String {
        if isPendingEditMode || isEditMode { return "Save" }
        return "Add Transaction"
    }

    var sheetTitle: String {
        if isPendingEditMode { return "Edit Entry" }
        return isEditMode ? "Edit Entry" : "New Entry"
    }

    func buildPendingOverrides() -> ConfirmPendingOverrides {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: dateTime)
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeStr = timeFormatter.string(from: dateTime)
        let (categoryStr, subcategoryStr) = apiCategoryAndSubcategory
        return ConfirmPendingOverrides(
            type: transactionType,
            amountOriginal: amount,
            currencyOriginal: selectedCurrency,
            amountBase: amount,
            baseCurrency: selectedCurrency,
            merchant: merchant.isEmpty ? nil : merchant,
            transactionDate: dateStr,
            transactionTime: timeStr,
            category: categoryStr,
            subcategory: subcategoryStr
        )
    }

    init(existing: Transaction? = nil, initialType: String? = nil, fromPayload payload: PendingTransactionPayload? = nil) {
        self.existingTransaction = existing
        if let type = initialType, existing == nil, payload == nil {
            transactionType = type
        }
        CategoryStore.ensureDefaults()
        if let p = payload, existing == nil {
            isPendingEditMode = true
            amountText = p.amountOriginal.map { String(format: "%.2f", $0) } ?? ""
            selectedCurrency = p.currencyOriginal ?? "USD"
            merchant = p.merchant ?? ""
            selectedCategoryId = mapLegacyCategoryToId(p.category ?? "other")
            if let subName = p.subcategory, let catId = selectedCategoryId {
                selectedSubcategoryId = SubcategoryStore.forParent(catId).first { $0.name == subName }?.id
            }
            transactionType = (p.type ?? "expense").lowercased()
            note = p.title ?? ""
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            if let dateStr = p.transactionDate, let timeStr = p.transactionTime,
               let d = parseDateTime(dateStr: dateStr, timeStr: timeStr) {
                dateTime = d
            } else if let dateStr = p.transactionDate, !dateStr.isEmpty,
                      let d = formatter.date(from: String(dateStr.prefix(10))) {
                dateTime = d
            }
        } else if let tx = existing {
            amountText = String(format: "%.2f", tx.amountOriginal)
            selectedCurrency = tx.currencyOriginal
            merchant = tx.merchant ?? ""
            selectedCategoryId = mapLegacyCategoryToId(tx.category)
            if let subName = tx.subcategory, let catId = selectedCategoryId {
                selectedSubcategoryId = SubcategoryStore.forParent(catId).first { $0.name == subName }?.id
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
        } else {
            let cats = CategoryStore.load()
            selectedCategoryId = cats.first?.id ?? "other"
        }
    }

    private func mapLegacyCategoryToId(_ legacy: String) -> String {
        let map: [String: String] = [
            "food": "food", "groceries": "food", "food_delivery": "food",
            "transport": "transport",
            "bills": "housing", "subscriptions": "housing", "entertainment": "other",
            "health": "health",
            "other": "other", "fees": "other", "transfers": "other", "income": "other",
        ]
        return map[legacy] ?? (CategoryStore.byId(legacy) != nil ? legacy : "other")
    }

    private var apiCategoryAndSubcategory: (String, String?) {
        guard let catId = selectedCategoryId else { return ("other", nil) }
        if let subId = selectedSubcategoryId,
           let sub = SubcategoryStore.forParent(catId).first(where: { $0.id == subId }) {
            return (catId, sub.name)
        }
        return (catId, nil)
    }

    private func parseDateTime(dateStr: String, timeStr: String) -> Date? {
        let dStr = String(dateStr.prefix(10))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: "\(dStr) \(timeStr)")
    }

    var lastUsedCategoryIds: [String] {
        LastUsedCategoriesStore.forQuickPick()
    }

    var selectedCategoryDisplay: String {
        guard let catId = selectedCategoryId else { return "Select category" }
        let cat = CategoryStore.byId(catId)
        let catName = cat?.name ?? catId
        if let subId = selectedSubcategoryId,
           let sub = SubcategoryStore.forParent(catId).first(where: { $0.id == subId }) {
            return "\(catName) › \(sub.name)"
        }
        return catName
    }

    var selectedCategoryColor: Color {
        guard let catId = selectedCategoryId, let cat = CategoryStore.byId(catId) else {
            return OnboardingDesign.accentGreen
        }
        return cat.color
    }

    func selectCategory(categoryId: String, subcategoryId: String?) {
        selectedCategoryId = categoryId
        selectedSubcategoryId = subcategoryId
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

        let (categoryStr, subcategoryStr) = apiCategoryAndSubcategory
        let isSubscription = subcategoryStr?.lowercased().contains("subscription") == true

        if let existing = existingTransaction {
            let body = UpdateTransactionBody(
                amountOriginal: amt,
                amountBase: amt,
                merchant: merchant.isEmpty ? nil : merchant,
                category: categoryStr,
                subcategory: subcategoryStr,
                transactionDate: dateStr,
                comment: note.isEmpty ? nil : note
            )
            do {
                _ = try await LocalDataStore.shared.updateTransaction(id: existing.id, body: body)
                await MainActor.run {
                    if let catId = selectedCategoryId { LastUsedCategoriesStore.recordUsed(categoryId: catId) }
                    didSucceed = true
                }
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
                category: categoryStr,
                subcategory: subcategoryStr,
                isSubscription: isSubscription,
                comment: note.isEmpty ? nil : note,
                sourceType: "manual"
            )
            do {
                _ = try await LocalDataStore.shared.createTransaction(body)
                await MainActor.run {
                    if let catId = selectedCategoryId { LastUsedCategoriesStore.recordUsed(categoryId: catId) }
                    didSucceed = true
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}
