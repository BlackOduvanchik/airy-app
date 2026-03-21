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
        "AED": 0.27, "ARS": 0.0011, "AUD": 0.65, "BRL": 0.17,
        "CAD": 0.73, "CHF": 1.12, "CNY": 0.14, "CZK": 0.043,
        "DKK": 0.14, "EUR": 1.08, "GBP": 1.27, "HKD": 0.13,
        "HUF": 0.0027, "IDR": 0.000063, "ILS": 0.27, "INR": 0.012,
        "JPY": 0.0067, "KRW": 0.00075, "MXN": 0.058, "MYR": 0.22,
        "NOK": 0.093, "NZD": 0.60, "PHP": 0.018, "PLN": 0.25,
        "RON": 0.22, "RUB": 0.011, "SAR": 0.27, "SEK": 0.095,
        "SGD": 0.74, "THB": 0.029, "TRY": 0.031, "TWD": 0.031,
        "UAH": 0.025, "USD": 1.0, "USDC": 1.0, "VND": 0.000040,
        "ZAR": 0.055
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
