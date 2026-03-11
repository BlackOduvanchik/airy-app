//
//  MerchantCorrectionStore.swift
//  Airy
//
//  Learns from user edits: when user corrects a merchant, we remember it for future imports.
//

import Foundation

struct MerchantCorrection: Codable {
    let amount: Double
    let date: String
    let originalMerchant: String
    let correctedMerchant: String
}

final class MerchantCorrectionStore {
    static let shared = MerchantCorrectionStore()
    private let key = "merchantCorrections"
    private let maxCorrections = 500

    private init() {}

    func saveCorrection(amount: Double, date: String, originalMerchant: String?, correctedMerchant: String) {
        guard !correctedMerchant.isEmpty, correctedMerchant != (originalMerchant ?? "Transaction") else { return }
        var all = loadAll()
        let correction = MerchantCorrection(
            amount: amount,
            date: date,
            originalMerchant: originalMerchant ?? "Transaction",
            correctedMerchant: correctedMerchant
        )
        all.removeAll { $0.amount == amount && $0.date == date && $0.originalMerchant == correction.originalMerchant }
        all.insert(correction, at: 0)
        if all.count > maxCorrections { all = Array(all.prefix(maxCorrections)) }
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func lookup(amount: Double, date: String, originalMerchant: String?) -> String? {
        let orig = originalMerchant ?? "Transaction"
        return loadAll().first { $0.amount == amount && $0.date == date && $0.originalMerchant == orig }?.correctedMerchant
    }

    private func loadAll() -> [MerchantCorrection] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([MerchantCorrection].self, from: data)) ?? []
    }
}
