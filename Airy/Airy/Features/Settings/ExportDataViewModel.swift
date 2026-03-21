//
//  ExportDataViewModel.swift
//  Airy
//
//  ViewModel for Export Data: period selection, column management, CSV generation.
//

import Foundation

/// Exportable column definition.
struct ExportColumn: Identifiable {
    let id: String
    let displayName: String
    let keyPath: (Transaction) -> String
}

@MainActor
@Observable
final class ExportDataViewModel {

    enum Period: String, CaseIterable, Identifiable {
        case allTime, last3Months, lastYear, custom
        var id: String { rawValue }

        @MainActor var displayName: String {
            switch self {
            case .allTime:     return L("export_period_all")
            case .last3Months: return L("export_period_3m")
            case .lastYear:    return L("export_period_year")
            case .custom:      return L("export_period_custom")
            }
        }

        @MainActor func subtitle(customStart: Date?, customEnd: Date?) -> String {
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM yyyy"
            switch self {
            case .allTime:
                return L("export_period_all_sub")
            case .last3Months:
                let end = Date()
                let start = Calendar.current.date(byAdding: .month, value: -3, to: end) ?? end
                return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
            case .lastYear:
                let end = Date()
                let start = Calendar.current.date(byAdding: .year, value: -1, to: end) ?? end
                return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
            case .custom:
                if let s = customStart, let e = customEnd {
                    let df = DateFormatter()
                    df.dateFormat = "dd MMM yyyy"
                    return "\(df.string(from: s)) – \(df.string(from: e))"
                }
                return L("export_period_custom_sub")
            }
        }
    }

    // MARK: - State

    var selectedPeriod: Period = .allTime
    var customStartDate: Date?
    var customEndDate: Date?
    var transactions: [Transaction] = []
    var isLoading = false

    // MARK: - Columns

    static let allColumns: [ExportColumn] = [
        ExportColumn(id: "date",            displayName: "Date",         keyPath: { $0.transactionDate }),
        ExportColumn(id: "time",            displayName: "Time",         keyPath: { $0.transactionTime ?? "" }),
        ExportColumn(id: "type",            displayName: "Type",         keyPath: { $0.type }),
        ExportColumn(id: "merchant",        displayName: "Merchant",     keyPath: { $0.merchant ?? "" }),
        ExportColumn(id: "title",           displayName: "Note",         keyPath: { $0.title ?? "" }),
        ExportColumn(id: "category",        displayName: "Category",     keyPath: { CategoryIconHelper.displayName(categoryId: $0.category) }),
        ExportColumn(id: "subcategory",     displayName: "Subcategory",  keyPath: {
            guard let sub = $0.subcategory, !sub.isEmpty else { return "" }
            // Resolve UUID to display name if needed
            if let found = SubcategoryStore.load().first(where: { $0.id == sub }) { return found.name }
            return sub
        }),
        ExportColumn(id: "amountOriginal",  displayName: "Amount",       keyPath: {
            let sign: Double = $0.type == "expense" ? -1 : 1
            return String(format: "%.2f", $0.amountOriginal * sign)
        }),
        ExportColumn(id: "currencyOriginal",displayName: "Currency",     keyPath: { $0.currencyOriginal }),
        ExportColumn(id: "amountBase",      displayName: "Base Amount",  keyPath: {
            let sign: Double = $0.type == "expense" ? -1 : 1
            return String(format: "%.2f", $0.amountBase * sign)
        }),
        ExportColumn(id: "baseCurrency",    displayName: "Base Currency", keyPath: { $0.baseCurrency }),
        ExportColumn(id: "isSubscription",  displayName: "Subscription", keyPath: { $0.isSubscription == true ? "Yes" : "No" }),
    ]

    var selectedColumnIds: Set<String> = {
        if let saved = UserDefaults.standard.string(forKey: "exportSelectedColumns") {
            let ids = Set(saved.components(separatedBy: ","))
            if !ids.isEmpty { return ids }
        }
        return Set(allColumns.map(\.id))
    }()

    var selectedColumns: [ExportColumn] {
        Self.allColumns.filter { selectedColumnIds.contains($0.id) }
    }

    func toggleColumn(_ id: String) {
        if selectedColumnIds.contains(id) {
            if selectedColumnIds.count > 1 { selectedColumnIds.remove(id) }
        } else {
            selectedColumnIds.insert(id)
        }
        persistColumns()
    }

    private func persistColumns() {
        UserDefaults.standard.set(selectedColumnIds.sorted().joined(separator: ","), forKey: "exportSelectedColumns")
    }

    // MARK: - Date Range

    var effectiveDateRange: (start: String, end: String) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        let now = Date()
        switch selectedPeriod {
        case .allTime:
            return ("0000-01-01", "9999-12-31")
        case .last3Months:
            let start = Calendar.current.date(byAdding: .month, value: -3, to: now) ?? now
            return (fmt.string(from: start), fmt.string(from: now))
        case .lastYear:
            let start = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now
            return (fmt.string(from: start), fmt.string(from: now))
        case .custom:
            guard let s = customStartDate, let e = customEndDate else {
                return ("0000-01-01", "9999-12-31")
            }
            return (fmt.string(from: s), fmt.string(from: e))
        }
    }

    // MARK: - Load

    func loadTransactions() {
        isLoading = true
        let range = effectiveDateRange
        if selectedPeriod == .allTime {
            transactions = LocalDataStore.shared.fetchTransactions(limit: 100_000)
        } else {
            transactions = LocalDataStore.shared.fetchTransactions(from: range.start, to: range.end)
        }
        isLoading = false
    }

    // MARK: - CSV

    func buildCSV() -> String {
        let cols = selectedColumns
        var lines: [String] = []
        lines.append(cols.map { csvEscape($0.displayName) }.joined(separator: ","))
        for tx in transactions {
            let row = cols.map { csvEscape($0.keyPath(tx)) }
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    func exportToFile() -> URL? {
        let csv = buildCSV()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let fileName = "Airy_Export_\(fmt.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
