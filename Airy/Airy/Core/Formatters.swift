//
//  Formatters.swift
//  Airy
//
//  Shared static formatters — avoids allocating NumberFormatter/DateFormatter on every render.
//

import Foundation

enum AppFormatters {
    // MARK: - Date Formatters

    static let inputDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static let shortMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    static let monthDayYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let iso8601Basic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Date Normalization

    /// Normalizes a possibly non-zero-padded date string to "yyyy-MM-dd" format.
    /// E.g. "2025-4-15" → "2025-04-15". Returns the original string if parsing fails.
    static func normalizeISODate(_ raw: String) -> String {
        let trimmed = String(raw.prefix(10))
        if trimmed.count == 10, inputDate.date(from: trimmed) != nil { return trimmed }
        let parts = trimmed.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return trimmed }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    // MARK: - Currency Formatters (cached by code + fractionDigits)

    private static let currencyCache = NSCache<NSString, NumberFormatter>()

    static func currency(code: String, fractionDigits: Int = 2) -> NumberFormatter {
        let key = "\(code)_\(fractionDigits)" as NSString
        if let cached = currencyCache.object(forKey: key) {
            return cached
        }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        f.maximumFractionDigits = fractionDigits
        f.minimumFractionDigits = fractionDigits == 0 ? 0 : min(fractionDigits, 2)
        currencyCache.setObject(f, forKey: key)
        return f
    }

    // MARK: - Format-aware transaction formatting

    private static let formatCache = NSCache<NSString, NumberFormatter>()

    private static func formatter(for format: AmountDisplayFormat, currency code: String, fractionDigits: Int = 2) -> NumberFormatter {
        let key = "\(code)_\(format.rawValue)_\(fractionDigits)" as NSString
        if let cached = formatCache.object(forKey: key) { return cached }
        let f = NumberFormatter()
        if format.showSymbol {
            f.numberStyle = .currency
            f.currencyCode = code
        } else {
            f.numberStyle = .decimal
        }
        f.usesGroupingSeparator = format.useGrouping
        f.maximumFractionDigits = fractionDigits
        f.minimumFractionDigits = fractionDigits == 0 ? 0 : min(fractionDigits, 2)
        formatCache.setObject(f, forKey: key)
        return f
    }

    static func formatTransaction(amount: Double, currency: String, isIncome: Bool) -> String {
        let fmt = isIncome ? AppearanceStore.incomeFormat : AppearanceStore.expenseFormat
        let f = formatter(for: fmt, currency: currency)
        let formatted = f.string(from: NSNumber(value: abs(amount))) ?? "\(abs(amount))"
        if fmt.showSign {
            return (isIncome ? "+ " : "- ") + formatted
        }
        return formatted
    }

    static func formatTotal(amount: Double, currency: String, fractionDigits: Int = 2) -> String {
        let fmt = AppearanceStore.expenseFormat
        let f = formatter(for: fmt, currency: currency, fractionDigits: fractionDigits)
        return f.string(from: NSNumber(value: abs(amount))) ?? "\(abs(amount))"
    }

    static func formatTotalWhole(amount: Double, currency: String) -> String {
        formatTotal(amount: amount, currency: currency, fractionDigits: 0)
    }

    static func formatTotalCents(_ value: Double) -> String {
        let cents = Int((abs(value).truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: ".%02d", cents)
    }

    static func currencySymbol(for code: String) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = code
        return fmt.currencySymbol ?? code
    }
}
