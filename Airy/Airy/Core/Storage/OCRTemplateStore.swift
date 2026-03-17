//
//  OCRTemplateStore.swift
//  Airy
//
//  Stores up to 200 amount-anchor OCR extraction templates in UserDefaults (LRU eviction).
//

import Foundation

/// How to extract the merchant string from its OCR line.
enum MerchantRule: String, Codable {
    case beforePipe     // "Adobe | - 39.99 USD"  →  everything before "|"
    case entireLine     // whole line = merchant
    case colonRight     // "Merchant: Adobe"       →  everything after ":"
}

/// An amount-anchor template: all field offsets are relative to the line that contains the amount.
struct OCRTemplate: Codable, Identifiable {
    let id: String
    /// Line offset merchant line − amount line. 0 = same line, −1 = line above, +1 = line below.
    var merchantLineOffset: Int
    var merchantExtractionRule: MerchantRule
    /// Line offset date line − amount line.
    var dateLineOffset: Int
    /// Typical number of OCR lines that make up one transaction block (used to separate blocks).
    var linesPerBlock: Int
    /// Regex patterns that reliably match an amount value on the anchor line.
    var knownAmountPatterns: [String]
    var useCount: Int
    var lastUsed: Date
    /// Free-form hint for debugging (e.g. "KasikornBank").
    var bankHint: String?
}

final class OCRTemplateStore {
    static let shared = OCRTemplateStore()

    private let queue = DispatchQueue(label: "ai.airy.OCRTemplateStore", attributes: .concurrent)
    private let udKey = "OCRTemplateStore_v1"
    private let maxCount = 200
    private var _templates: [OCRTemplate] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: udKey),
           let decoded = try? JSONDecoder().decode([OCRTemplate].self, from: data) {
            _templates = decoded
        }
    }

    func upsert(_ template: OCRTemplate) {
        queue.async(flags: .barrier) { [self] in
            var t = template
            t.useCount += 1
            t.lastUsed = Date()
            if let idx = _templates.firstIndex(where: { $0.id == template.id }) {
                _templates[idx] = t
            } else {
                _templates.append(t)
                if _templates.count > maxCount {
                    _templates.sort { $0.lastUsed > $1.lastUsed }
                    _templates = Array(_templates.prefix(maxCount))
                }
            }
            persist()
        }
    }

    func remove(id: String) {
        queue.async(flags: .barrier) { [self] in
            _templates.removeAll { $0.id == id }
            persist()
        }
    }

    func all() -> [OCRTemplate] {
        queue.sync { _templates }
    }

    /// Returns an existing template with the same structural layout (offsets + rule), or nil.
    /// Used to avoid creating a new UUID for the same bank layout on every GPT call.
    func findByStructure(merchantOffset: Int, dateOffset: Int, rule: MerchantRule) -> OCRTemplate? {
        queue.sync {
            _templates.first {
                $0.merchantLineOffset == merchantOffset &&
                $0.dateLineOffset == dateOffset &&
                $0.merchantExtractionRule == rule
            }
        }
    }

    func clearAll() {
        queue.async(flags: .barrier) { [self] in
            _templates = []
            persist()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(_templates) {
            UserDefaults.standard.set(data, forKey: udKey)
        }
    }
}
