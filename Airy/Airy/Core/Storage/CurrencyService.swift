//
//  CurrencyService.swift
//  Airy
//
//  Base currency preference and conversion to it for totals/dashboard.
//

import Foundation

/// User's chosen currency for totals and reports. Stored in UserDefaults.
enum BaseCurrencyStore {
    private static let key = "airy_baseCurrency"

    static var baseCurrency: String {
        get { UserDefaults.standard.string(forKey: key) ?? "USD" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Converts amounts to a target currency using approximate rates (to USD). Use for dashboard/category totals.
enum CurrencyService {
    /// Rate to USD (1 unit of currency = X USD). Approximate; update periodically for production.
    private static let rateToUSD: [String: Double] = [
        "USD": 1.0,
        "EUR": 1.08,
        "GBP": 1.27,
        "JPY": 0.0067,
        "CHF": 1.12,
        "CAD": 0.73,
        "AUD": 0.65,
        "UAH": 0.025,
        "RUB": 0.011,
        "THB": 0.029,
        "USDC": 1.0
    ]

    /// Convert amount from source currency to target currency. Unknown currencies treated as USD.
    static func convert(amount: Double, from source: String, to target: String) -> Double {
        let src = source.uppercased()
        let tgt = target.uppercased()
        if src == tgt { return amount }
        let rateFrom = rateToUSD[src] ?? 1.0
        let rateTo = rateToUSD[tgt] ?? 1.0
        guard rateTo > 0 else { return amount }
        let inUSD = amount * rateFrom
        return inUSD / rateTo
    }

    /// Amount in user's base currency for summing. Use for a transaction that may be stored in any currency.
    static func amountInBase(amountOriginal: Double, currencyOriginal: String, amountBase: Double, baseCurrency: String) -> Double {
        let userBase = BaseCurrencyStore.baseCurrency
        if baseCurrency.uppercased() == userBase { return amountBase }
        return convert(amount: amountOriginal, from: currencyOriginal, to: userBase)
    }
}
