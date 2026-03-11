//
//  AddTransactionViewModel.swift
//  Airy
//
//  Local-only: create/update via SwiftData.
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

    var apiCategoryValue: String { rawValue }

    var displayName: String {
        switch self {
        case .food: return "Food"
        case .transport: return "Travel"
        case .bills: return "Home"
        case .other: return "Other"
        }
    }

    /// Subcategories shown when this main category is selected.
    var subcategories: [TransactionCategory] {
        switch self {
        case .food: return [.food, .groceries, .food_delivery]
        case .transport: return [.transport]
        case .bills: return [.bills, .subscriptions, .entertainment, .health]
        case .other: return [.other, .fees, .transfers, .income]
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

/// Display item for subcategory picker: either built-in or custom.
enum SubcategoryDisplayItem: Equatable, Identifiable {
    case builtIn(TransactionCategory)
    case custom(Subcategory)

    var id: String {
        switch self {
        case .builtIn(let cat): return "builtin-\(cat.rawValue)"
        case .custom(let sub): return "custom-\(sub.id)"
        }
    }

    var displayName: String {
        switch self {
        case .builtIn(let cat): return cat.displayName
        case .custom(let sub): return sub.name
        }
    }
}

@Observable
final class AddTransactionViewModel {
    var amountText = ""
    var selectedCurrency = "USD"
    var merchant = ""
    var selectedCategory: TransactionCategory = .other
    var selectedCustomSubcategory: Subcategory?
    var selectedSheetCategory: AddSheetCategory = .food
    var transactionType: String = "expense"
    var dateTime = Date()
    var note = ""
    var isSubmitting = false
    var errorMessage: String?
    var didSucceed = false

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

    init(existing: Transaction? = nil, initialType: String? = nil) {
        self.existingTransaction = existing
        if let type = initialType, existing == nil {
            transactionType = type
        }
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

    private var apiCategoryAndSubcategory: (String, String?) {
        if let custom = selectedCustomSubcategory {
            return (custom.parentCategoryId, custom.name)
        }
        let parent = selectedSheetCategory
        let cat = selectedCategory
        if parent.subcategories.count <= 1 {
            return (parent.apiCategoryValue, nil)
        }
        if cat.rawValue == parent.apiCategoryValue {
            return (parent.apiCategoryValue, nil)
        }
        return (parent.apiCategoryValue, cat.rawValue)
    }

    private func parseDateTime(dateStr: String, timeStr: String) -> Date? {
        let dStr = String(dateStr.prefix(10))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: "\(dStr) \(timeStr)")
    }

    var subcategoryDisplayItems: [SubcategoryDisplayItem] {
        let builtIn = selectedSheetCategory.subcategories.map { SubcategoryDisplayItem.builtIn($0) }
        let custom = SubcategoryStore.forParent(selectedSheetCategory.apiCategoryValue).map { SubcategoryDisplayItem.custom($0) }
        return builtIn + custom
    }

    func selectSheetCategory(_ cat: AddSheetCategory) {
        selectedSheetCategory = cat
        selectedCustomSubcategory = nil
        if cat.subcategories.contains(selectedCategory) {
        } else {
            selectedCategory = cat.subcategories.first ?? cat.transactionCategory
        }
    }

    func selectSubcategory(_ cat: TransactionCategory) {
        selectedCategory = cat
        selectedCustomSubcategory = nil
    }

    func selectCustomSubcategory(_ sub: Subcategory) {
        selectedCustomSubcategory = sub
        selectedCategory = selectedSheetCategory.transactionCategory
    }

    func addCustomSubcategory(_ sub: Subcategory) {
        selectCustomSubcategory(sub)
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
                category: categoryStr,
                subcategory: subcategoryStr,
                isSubscription: selectedCategory == .subscriptions,
                comment: note.isEmpty ? nil : note,
                sourceType: "manual"
            )
            do {
                _ = try await LocalDataStore.shared.createTransaction(body)
                await MainActor.run { didSucceed = true }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}
