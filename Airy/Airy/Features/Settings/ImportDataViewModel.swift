//
//  ImportDataViewModel.swift
//  Airy
//
//  CSV parsing, column auto-detection, mapping, and transaction import.
//

import Foundation
import UniformTypeIdentifiers

/// What an imported CSV column maps to in the app.
enum CSVColumnMapping: String, CaseIterable, Identifiable {
    case date, dateAndTime, amount, currency, merchant, note, category, subcategory, type, skip

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .date:        return "Date"
        case .dateAndTime: return "Date & Time"
        case .amount:      return "Amount"
        case .currency:    return "Currency"
        case .merchant:    return "Merchant"
        case .note:        return "Note"
        case .category:    return "Category"
        case .subcategory: return "Subcategory"
        case .type:        return "Type (Income/Expense)"
        case .skip:        return "Skip"
        }
    }
}

/// Info about a detected CSV column.
struct CSVColumnInfo: Identifiable {
    let id: Int          // column index
    let header: String
    let preview: String  // first non-empty value
    var mapping: CSVColumnMapping
}

/// How a detected CSV category should be handled during import.
enum CategoryImportAction: Equatable {
    case importAsCategory
    case importAsSubcategory(parentId: String)
    case mapToExisting(categoryId: String)
    case skip
}

@MainActor
@Observable
final class ImportDataViewModel {

    // MARK: - State

    var importCurrency: String = BaseCurrencyStore.baseCurrency
    var fileName: String?
    var fileSize: String?
    var csvHeaders: [String] = []
    var csvRows: [[String]] = []
    var columns: [CSVColumnInfo] = []
    var isImporting = false
    var importedCount = 0
    var importError: String?
    var importFinished = false
    var categoryActions: [String: CategoryImportAction] = [:]

    // MARK: - Derived

    var transactionCount: Int { csvRows.count }
    var hasFile: Bool { fileName != nil && !csvRows.isEmpty }

    var hasRequiredMappings: Bool {
        let mappings = Set(columns.map(\.mapping))
        return mappings.contains(.date) || mappings.contains(.dateAndTime)
    }

    var detectedCategories: [String] {
        guard let catCol = columns.first(where: { $0.mapping == .category }) else { return [] }
        let idx = catCol.id
        var seen = Set<String>()
        var result: [String] = []
        for row in csvRows {
            guard idx < row.count else { continue }
            let val = row[idx].trimmingCharacters(in: .whitespaces)
            if !val.isEmpty && !seen.contains(val.lowercased()) {
                seen.insert(val.lowercased())
                result.append(val)
            }
        }
        return result
    }

    func transactionCount(forCategory name: String) -> Int {
        guard let catCol = columns.first(where: { $0.mapping == .category }) else { return 0 }
        let idx = catCol.id
        let lower = name.lowercased()
        return csvRows.filter { idx < $0.count && $0[idx].trimmingCharacters(in: .whitespaces).lowercased() == lower }.count
    }

    /// Unique values from the subcategory column, paired with the category from the same row.
    var detectedSubcategories: [(name: String, rowCategory: String?)] {
        guard let subCol = columns.first(where: { $0.mapping == .subcategory }) else { return [] }
        let subIdx = subCol.id
        let catIdx = columns.first(where: { $0.mapping == .category })?.id
        var seen = Set<String>()
        var result: [(name: String, rowCategory: String?)] = []
        for row in csvRows {
            guard subIdx < row.count else { continue }
            let val = row[subIdx].trimmingCharacters(in: .whitespaces)
            if !val.isEmpty && !seen.contains(val.lowercased()) {
                seen.insert(val.lowercased())
                let cat = catIdx.flatMap { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespaces) : nil }
                result.append((val, cat))
            }
        }
        return result
    }

    func setupCategoryActions() {
        let categories = CategoryStore.load()
        let subcategories = SubcategoryStore.load()
        var actions: [String: CategoryImportAction] = [:]

        for csvCat in detectedCategories {
            let lower = csvCat.lowercased()
            if let match = categories.first(where: { $0.name.lowercased() == lower }) {
                actions[csvCat] = .mapToExisting(categoryId: match.id)
            } else if let sub = subcategories.first(where: { $0.name.lowercased() == lower }) {
                // CSV "category" value is actually a subcategory in Airy — map to parent + subcategory
                actions[csvCat] = .importAsSubcategory(parentId: sub.parentCategoryId)
            } else if let match = categories.first(where: { lower.contains($0.name.lowercased()) || $0.name.lowercased().contains(lower) }) {
                actions[csvCat] = .mapToExisting(categoryId: match.id)
            } else {
                actions[csvCat] = .importAsCategory
            }
        }
        categoryActions = actions
    }

    // MARK: - CSV Parsing

    func parseCSV(from url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            var content = try String(contentsOf: url, encoding: .utf8)
            // Strip BOM
            if content.hasPrefix("\u{FEFF}") { content = String(content.dropFirst()) }

            fileName = url.lastPathComponent
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attrs?[.size] as? Int64 {
                fileSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }

            let rows = parseCSVRows(content)
            guard rows.count > 1 else {
                importError = "File is empty or has only headers."
                return
            }
            csvHeaders = rows[0]
            csvRows = Array(rows.dropFirst()).filter { !$0.allSatisfy(\.isEmpty) }
            autoDetectMappings()
            setupCategoryActions()
        } catch {
            importError = "Could not read file: \(error.localizedDescription)"
        }
    }

    /// Parse CSV handling quoted fields.
    private func parseCSVRows(_ content: String) -> [[String]] {
        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuotes = false
        var i = content.startIndex

        while i < content.endIndex {
            let c = content[i]
            if inQuotes {
                if c == "\"" {
                    let next = content.index(after: i)
                    if next < content.endIndex && content[next] == "\"" {
                        field.append("\"")
                        i = content.index(after: next)
                    } else {
                        inQuotes = false
                        i = content.index(after: i)
                    }
                } else {
                    field.append(c)
                    i = content.index(after: i)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                    i = content.index(after: i)
                } else if c == "," || c == ";" || c == "\t" {
                    current.append(field.trimmingCharacters(in: .whitespaces))
                    field = ""
                    i = content.index(after: i)
                } else if c == "\n" || c == "\r" {
                    current.append(field.trimmingCharacters(in: .whitespaces))
                    field = ""
                    if !current.allSatisfy(\.isEmpty) { rows.append(current) }
                    current = []
                    // skip \r\n
                    let next = content.index(after: i)
                    if c == "\r" && next < content.endIndex && content[next] == "\n" {
                        i = content.index(after: next)
                    } else {
                        i = content.index(after: i)
                    }
                } else {
                    field.append(c)
                    i = content.index(after: i)
                }
            }
        }
        // Last field
        if !field.isEmpty || !current.isEmpty {
            current.append(field.trimmingCharacters(in: .whitespaces))
            if !current.allSatisfy(\.isEmpty) { rows.append(current) }
        }
        return rows
    }

    // MARK: - Auto-detection

    private func autoDetectMappings() {
        columns = []
        for (idx, header) in csvHeaders.enumerated() {
            let preview = csvRows.first(where: { idx < $0.count && !$0[idx].isEmpty }).map { $0[idx] } ?? ""
            let mapping = detectMapping(header: header, sampleValue: preview)
            columns.append(CSVColumnInfo(id: idx, header: header, preview: preview, mapping: mapping))
        }
    }

    private func detectMapping(header: String, sampleValue: String) -> CSVColumnMapping {
        let h = header.lowercased().trimmingCharacters(in: .whitespaces)

        // Header-based heuristics
        if h.contains("date") && h.contains("time") { return .dateAndTime }
        if h.contains("date") || h == "дата" || h == "дата операции" { return .date }
        if h.contains("time") || h == "время" { return .dateAndTime }
        if h.contains("amount") || h.contains("sum") || h.contains("total") || h.contains("price") || h == "сумма" || h == "стоимость" { return .amount }
        if h.contains("merchant") || h.contains("description") || h.contains("payee") || h.contains("vendor") || h.contains("name") || h == "описание" || h == "получатель" || h == "назначение" { return .merchant }
        // Subcategory must be checked BEFORE category (since "subcategory" contains "category")
        if h.contains("subcategor") || h.contains("sub_cat") || h.contains("sub cat") || h == "подкатегория" || h == "субкатегория" { return .subcategory }
        if h.contains("category") || h.contains("cat") || h == "категория" || h == "группа" { return .category }
        if h.contains("note") || h.contains("memo") || h.contains("comment") || h == "заметка" || h == "комментарий" || h == "примечание" { return .note }
        if h.contains("currency") || h.contains("cur") || h == "валюта" { return .currency }
        if h.contains("type") || h == "тип" || h == "тип операции" { return .type }

        // Value-based heuristics
        let v = sampleValue.trimmingCharacters(in: .whitespaces)
        if looksLikeDate(v) { return .date }
        if looksLikeAmount(v) { return .amount }

        return .skip
    }

    private func looksLikeDate(_ value: String) -> Bool {
        let patterns = [
            #"^\d{4}[/\-\.]\d{1,2}[/\-\.]\d{1,2}"#,
            #"^\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4}"#
        ]
        for p in patterns {
            if value.range(of: p, options: .regularExpression) != nil { return true }
        }
        return false
    }

    private func looksLikeAmount(_ value: String) -> Bool {
        let cleaned = value.replacingOccurrences(of: "[€$£¥₽₴₹¢]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.range(of: #"^-?\d[\d\s,]*\.?\d*$"#, options: .regularExpression) != nil
            || cleaned.range(of: #"^-?\d[\d\s.]*,\d+$"#, options: .regularExpression) != nil
    }

    // MARK: - Import

    func importTransactions() async -> Int {
        isImporting = true
        importedCount = 0
        importError = nil

        // Step 1: Create new categories & subcategories as configured
        var createdCategoryIds: [String: String] = [:]  // lowercased csvName → new category id
        var colorIndex = 0

        for (csvName, action) in categoryActions {
            switch action {
            case .importAsCategory:
                let color = CategoryStore.presetColors[colorIndex % CategoryStore.presetColors.count]
                let randomIcon = SFSymbolsCatalog.allSymbols.filter { !SFSymbolsCatalog.isLetter($0) }.randomElement() ?? "tag.fill"
                let cat = Category(name: csvName, colorHex: color, iconName: randomIcon)
                CategoryStore.add(cat)
                createdCategoryIds[csvName.lowercased()] = cat.id
                colorIndex += 1
            case .importAsSubcategory(let parentId):
                let existing = SubcategoryStore.forParent(parentId)
                if !existing.contains(where: { $0.name.lowercased() == csvName.lowercased() }) {
                    SubcategoryStore.add(Subcategory(name: csvName, parentCategoryId: parentId))
                }
            default:
                break
            }
        }

        // Step 2: Import transactions
        let categories = CategoryStore.load()
        var count = 0

        for row in csvRows {
            let dateStr = extractDate(from: row)
            guard let dateStr else { continue }

            let time = extractTime(from: row)
            let amount = extractAmount(from: row)
            let type = extractType(from: row, amount: amount)
            let merchant = extractString(from: row, mapping: .merchant)
            let note = extractString(from: row, mapping: .note)
            let categoryName = extractString(from: row, mapping: .category)
            let csvSubcategory = extractString(from: row, mapping: .subcategory)
            let currency = extractString(from: row, mapping: .currency)

            let resolvedCurrency = (currency?.isEmpty ?? true) ? importCurrency : currency!.uppercased()
            let resolved = resolveCategory(name: categoryName, createdIds: createdCategoryIds, categories: categories)
            let categoryId = resolved.categoryId
            // Resolve subcategory: prefer CSV subcategory column, fall back to resolved from category mapping
            let subcategory: String? = if let csvSub = csvSubcategory, !csvSub.isEmpty {
                resolveSubcategoryId(name: csvSub, parentCategoryId: categoryId)
            } else {
                resolved.subcategoryId
            }
            let baseAmount = CurrencyService.convert(amount: abs(amount), from: resolvedCurrency, to: BaseCurrencyStore.baseCurrency)

            let body = CreateTransactionBody(
                type: type,
                amountOriginal: abs(amount),
                currencyOriginal: resolvedCurrency,
                amountBase: baseAmount,
                baseCurrency: BaseCurrencyStore.baseCurrency,
                merchant: merchant,
                title: note,
                transactionDate: dateStr,
                transactionTime: time,
                category: categoryId,
                subcategory: subcategory,
                isSubscription: nil,
                subscriptionInterval: nil,
                comment: nil,
                sourceType: "csv_import"
            )

            do {
                _ = try LocalDataStore.shared.createTransaction(body)
                count += 1
            } catch {
                // Skip failed rows silently
            }
        }

        importedCount = count
        isImporting = false
        importFinished = true
        return count
    }

    private func resolveCategory(name: String?, createdIds: [String: String], categories: [Category]) -> (categoryId: String, subcategoryId: String?) {
        guard let name, !name.isEmpty else { return ("other", nil) }

        let action = categoryActions[name]
            ?? categoryActions.first(where: { $0.key.lowercased() == name.lowercased() })?.value

        guard let action else {
            return matchCategory(name: name, categories: categories)
        }

        switch action {
        case .importAsCategory:
            return (createdIds[name.lowercased()] ?? "other", nil)
        case .importAsSubcategory(let parentId):
            // Resolve subcategory name to its ID
            let subId = resolveSubcategoryId(name: name, parentCategoryId: parentId)
            return (parentId, subId)
        case .mapToExisting(let categoryId):
            return (categoryId, nil)
        case .skip:
            return ("other", nil)
        }
    }

    /// Resolve a subcategory name to its UUID, creating it if needed.
    private func resolveSubcategoryId(name: String, parentCategoryId: String) -> String? {
        guard !name.isEmpty else { return nil }
        let lower = name.lowercased()
        // Look for existing subcategory under this parent
        let existing = SubcategoryStore.forParent(parentCategoryId)
        if let match = existing.first(where: { $0.name.lowercased() == lower }) {
            return match.id
        }
        // Also check all subcategories (might be under a different parent if user remapped)
        let all = SubcategoryStore.load()
        if let match = all.first(where: { $0.name.lowercased() == lower && $0.parentCategoryId == parentCategoryId }) {
            return match.id
        }
        if let match = all.first(where: { $0.name.lowercased() == lower }) {
            return match.id
        }
        // Create new subcategory
        let newSub = Subcategory(name: name, parentCategoryId: parentCategoryId)
        SubcategoryStore.add(newSub)
        return newSub.id
    }

    // MARK: - Field extraction

    private func extractDate(from row: [String]) -> String? {
        // Check dateAndTime first
        if let col = columns.first(where: { $0.mapping == .dateAndTime }), col.id < row.count {
            let val = row[col.id]
            if let parsed = tryParseDate(val) { return parsed }
        }
        if let col = columns.first(where: { $0.mapping == .date }), col.id < row.count {
            let val = row[col.id]
            if let parsed = tryParseDate(val) { return parsed }
        }
        return nil
    }

    private func extractTime(from row: [String]) -> String? {
        if let col = columns.first(where: { $0.mapping == .dateAndTime }), col.id < row.count {
            let val = row[col.id]
            return tryParseTime(val)
        }
        return nil
    }

    private func extractAmount(from row: [String]) -> Double {
        guard let col = columns.first(where: { $0.mapping == .amount }), col.id < row.count else { return 0 }
        return parseAmount(row[col.id])
    }

    private func extractType(from row: [String], amount: Double) -> String {
        if let col = columns.first(where: { $0.mapping == .type }), col.id < row.count {
            let val = row[col.id].lowercased().trimmingCharacters(in: .whitespaces)
            if val.contains("income") || val.contains("доход") || val.contains("credit") { return "income" }
            if val.contains("expense") || val.contains("расход") || val.contains("debit") { return "expense" }
        }
        return amount < 0 ? "expense" : "income"
    }

    private func extractString(from row: [String], mapping: CSVColumnMapping) -> String? {
        guard let col = columns.first(where: { $0.mapping == mapping }), col.id < row.count else { return nil }
        let val = row[col.id].trimmingCharacters(in: .whitespaces)
        return val.isEmpty ? nil : val
    }

    // MARK: - Date parsing

    private static let dateFormats: [String] = [
        "yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd",
        "dd/MM/yyyy", "dd-MM-yyyy", "dd.MM.yyyy",
        "MM/dd/yyyy", "MM-dd-yyyy", "MM.dd.yyyy",
        "dd/MM/yy", "MM/dd/yy",
        "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss",
        "dd/MM/yyyy HH:mm", "MM/dd/yyyy HH:mm",
        "dd.MM.yyyy HH:mm", "yyyy-MM-dd HH:mm"
    ]

    private func tryParseDate(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let output = DateFormatter()
        output.dateFormat = "yyyy-MM-dd"
        output.timeZone = TimeZone(identifier: "UTC")
        for fmt in Self.dateFormats {
            formatter.dateFormat = fmt
            if let date = formatter.date(from: trimmed) {
                return output.string(from: date)
            }
        }
        return nil
    }

    private func tryParseTime(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let output = DateFormatter()
        output.dateFormat = "HH:mm"
        for fmt in Self.dateFormats where fmt.contains("HH") {
            formatter.dateFormat = fmt
            if let date = formatter.date(from: trimmed) {
                return output.string(from: date)
            }
        }
        return nil
    }

    // MARK: - Amount parsing

    private func parseAmount(_ value: String) -> Double {
        var cleaned = value.trimmingCharacters(in: .whitespaces)
        // Remove currency symbols and spaces
        cleaned = cleaned.replacingOccurrences(of: "[€$£¥₽₴₹¢\\s]", with: "", options: .regularExpression)
        // Detect comma as decimal separator (e.g. "1.234,56" or "1234,56")
        if cleaned.contains(",") && cleaned.contains(".") {
            // "1.234,56" → comma is decimal
            if let commaIdx = cleaned.lastIndex(of: ","), let dotIdx = cleaned.lastIndex(of: "."),
               commaIdx > dotIdx {
                cleaned = cleaned.replacingOccurrences(of: ".", with: "")
                cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        } else if cleaned.contains(",") {
            // Could be "1,234" (thousands) or "12,50" (decimal)
            let parts = cleaned.components(separatedBy: ",")
            if let last = parts.last, last.count <= 2 && parts.count == 2 {
                cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        }
        return Double(cleaned) ?? 0
    }

    // MARK: - Category matching

    private func matchCategory(name: String?, categories: [Category]) -> (categoryId: String, subcategoryId: String?) {
        guard let name, !name.isEmpty else { return ("other", nil) }
        let lower = name.lowercased()

        // 1. Exact match on category name
        if let match = categories.first(where: { $0.name.lowercased() == lower }) {
            return (match.id, nil)
        }
        // 2. Exact match on category id
        if let match = categories.first(where: { $0.id.lowercased() == lower }) {
            return (match.id, nil)
        }

        // 3. Search subcategories by name — return subcategory ID (not name)
        let allSubcategories = SubcategoryStore.load()
        if let sub = allSubcategories.first(where: { $0.name.lowercased() == lower }) {
            return (sub.parentCategoryId, sub.id)
        }
        // Partial match on subcategory name
        if let sub = allSubcategories.first(where: { lower.contains($0.name.lowercased()) || $0.name.lowercased().contains(lower) }) {
            return (sub.parentCategoryId, sub.id)
        }

        // 4. Partial match on category name
        if let match = categories.first(where: { lower.contains($0.name.lowercased()) || $0.name.lowercased().contains(lower) }) {
            return (match.id, nil)
        }

        return ("other", nil)
    }
}
