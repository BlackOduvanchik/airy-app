//
//  GPTTeacherMapper.swift
//  Airy
//
//  Maps GPT-extracted transactions back to OCR row groups to create structural
//  learning examples. The system learns which OCR row patterns correspond to
//  transactions — not the content of those transactions.
//
//  Algorithm: 3-pass matching
//    Pass 1: Amount-anchor — find row group containing GPT transaction's amount string (multiple formats tried). Unique match → confidence 0.95.
//    Pass 2: Positional fallback — if counts match, map GPT[i] → row[i], confidence 0.80.
//    Pass 3: Date validation — if row contains no fragment of GPT date, reduce confidence 0.2.
//

import Foundation

enum GPTTeacherMapper {

    struct MappingResult {
        let examples: [ConfirmedRowExample]
        let mappedCount: Int
        let unmappedGPTCount: Int
        /// Overall mapping confidence 0...1. Below 0.65 = not reliable; don't learn from this image.
        let mappingConfidence: Double
    }

    /// Map GPT transactions to OCR row groups and produce structural ConfirmedRowExamples.
    /// - Parameters:
    ///   - gptTransactions: Array of GPTExtractionTransaction (date, merchant, amount, ...) from GPT response.
    ///   - groupedOCRRows: Grouped transaction candidate rows from OCR block classifier.
    ///   - familyId: Layout family that this screenshot belongs to.
    ///   - imageHash: SHA256 hash of the source image.
    static func map(
        gptTransactions: [GPTExtractionTransaction],
        groupedOCRRows: [[String]],
        familyId: String,
        imageHash: String
    ) -> MappingResult {
        guard !gptTransactions.isEmpty, !groupedOCRRows.isEmpty else {
            return MappingResult(examples: [], mappedCount: 0, unmappedGPTCount: gptTransactions.count, mappingConfidence: 0)
        }

        // Safety: if GPT returned more transactions than we have row groups, the mapping
        // is unreliable — skip learning from this image.
        if gptTransactions.count > groupedOCRRows.count + 2 {
            return MappingResult(examples: [], mappedCount: 0, unmappedGPTCount: gptTransactions.count, mappingConfidence: 0)
        }

        var matched: [(gptIndex: Int, rowIndex: Int, confidence: Double)] = []
        var usedRowIndices = Set<Int>()

        // PASS 1: Amount-based anchor
        for (gi, tx) in gptTransactions.enumerated() {
            let candidates = amountMatchingRowIndices(for: tx, in: groupedOCRRows)
            // Exclude already-matched rows
            let available = candidates.filter { !usedRowIndices.contains($0) }
            if available.count == 1 {
                matched.append((gi, available[0], 0.95))
                usedRowIndices.insert(available[0])
            }
            // Multiple candidates or zero → leave for pass 2
        }

        let unmatchedGPTIndices = gptTransactions.indices.filter { gi in
            !matched.contains { $0.gptIndex == gi }
        }

        // PASS 2: Positional fallback for unmatched GPT transactions
        // Only apply if total count parity is close (GPT count ≤ row count)
        if !unmatchedGPTIndices.isEmpty && gptTransactions.count <= groupedOCRRows.count {
            let availableRowIndices = groupedOCRRows.indices.filter { !usedRowIndices.contains($0) }
            let positionalConf: Double = gptTransactions.count == groupedOCRRows.count ? 0.80 : 0.65
            for (slot, gi) in unmatchedGPTIndices.enumerated() {
                if slot < availableRowIndices.count {
                    let ri = availableRowIndices[slot]
                    matched.append((gi, ri, positionalConf))
                    usedRowIndices.insert(ri)
                }
            }
        }

        guard !matched.isEmpty else {
            return MappingResult(examples: [], mappedCount: 0, unmappedGPTCount: gptTransactions.count, mappingConfidence: 0)
        }

        // PASS 3: Date validation — downgrade confidence when date is not in row
        var validatedMatches: [(rowGroup: [String], confidence: Double)] = []
        for m in matched {
            let tx = gptTransactions[m.gptIndex]
            let rowGroup = groupedOCRRows[m.rowIndex]
            var conf = m.confidence
            if !dateFragmentPresent(date: tx.date, in: rowGroup) {
                conf -= 0.20
            }
            validatedMatches.append((rowGroup, conf))
        }

        // Only emit examples with confidence ≥ 0.65
        let qualifiedMatches = validatedMatches.filter { $0.confidence >= 0.65 }
        let examples = qualifiedMatches.map { match -> ConfirmedRowExample in
            buildExample(from: match.rowGroup, familyId: familyId, imageHash: imageHash)
        }

        let overallConf = qualifiedMatches.isEmpty ? 0.0 :
            qualifiedMatches.map { $0.confidence }.reduce(0, +) / Double(qualifiedMatches.count)

        let unmapped = gptTransactions.count - matched.count

        return MappingResult(
            examples: examples,
            mappedCount: qualifiedMatches.count,
            unmappedGPTCount: unmapped,
            mappingConfidence: overallConf
        )
    }

    // MARK: - Private helpers

    /// Return indices of row groups that contain an amount matching this GPT transaction.
    private static func amountMatchingRowIndices(for tx: GPTExtractionTransaction, in rowGroups: [[String]]) -> [Int] {
        let amountVariants = amountStringVariants(tx.amount)
        var result: [Int] = []
        for (i, rowLines) in rowGroups.enumerated() {
            let rowText = rowLines.joined(separator: " ")
            for variant in amountVariants {
                if rowText.contains(variant) {
                    result.append(i)
                    break
                }
            }
        }
        return result
    }

    /// Generate several string representations of the amount to handle different locale formats.
    private static func amountStringVariants(_ amount: Double) -> [String] {
        var variants: [String] = []
        // Plain decimal
        variants.append(String(format: "%.2f", amount))
        // Comma as decimal separator
        variants.append(String(format: "%.2f", amount).replacingOccurrences(of: ".", with: ","))
        // Thousands separator with period decimal
        if amount >= 1000 {
            let int = Int(amount)
            let frac = Int((amount - Double(int)) * 100)
            let formatted = "\(formattedThousands(int)).\(String(format: "%02d", frac))"
            variants.append(formatted)
            variants.append(formatted.replacingOccurrences(of: ".", with: ","))
        }
        // Integer only (when amount is a round number)
        if amount == Double(Int(amount)) {
            variants.append(String(Int(amount)))
        }
        return variants
    }

    private static func formattedThousands(_ value: Int) -> String {
        var s = ""
        let str = "\(value)"
        for (i, ch) in str.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { s.insert(",", at: s.startIndex) }
            s.insert(ch, at: s.startIndex)
        }
        return s
    }

    /// True if any fragment of the date string (day or month number) appears in the row lines.
    private static func dateFragmentPresent(date: String, in rowLines: [String]) -> Bool {
        let rowText = rowLines.joined(separator: " ")
        // date format is typically "2024-03-15" — check day and month numbers
        let parts = date.components(separatedBy: CharacterSet(charactersIn: "-./"))
        for part in parts where !part.isEmpty {
            // Skip the year (4-digit) since it's less discriminative
            if part.count == 4 { continue }
            if rowText.contains(part) { return true }
        }
        return false
    }

    /// Build a ConfirmedRowExample from a row group by extracting only structural features.
    private static func buildExample(from rowLines: [String], familyId: String, imageHash: String) -> ConfirmedRowExample {
        let lineCount = rowLines.count
        let sig = rowLines.prefix(3).map { lineLengthBucket(for: $0) }
        let amountPos = detectAmountPosition(in: rowLines)
        let (dateInline, dateLineIdx) = detectDatePlacement(in: rowLines)
        return ConfirmedRowExample(
            familyId: familyId,
            imageHash: imageHash,
            rowLineCount: lineCount,
            lineLengthSignature: sig,
            amountPosition: amountPos,
            hasDateInline: dateInline,
            dateLineIndex: dateLineIdx,
            confirmedAt: Date(),
            source: .gptTeacher
        )
    }

    private static func lineLengthBucket(for line: String) -> String {
        let count = line.trimmingCharacters(in: .whitespaces).count
        if count < 16 { return "S" }
        if count < 36 { return "M" }
        return "L"
    }

    private static let amountPatternStr = #"[-+]?\s*\d{1,3}(?:[\s.,]\d{3})*(?:[.,]\d{2})|\d+[.,]\d{2}|\d+"#

    private static func detectAmountPosition(in lines: [String]) -> LearnedAmountPosition {
        let joined = lines.joined(separator: " ")
        guard let regex = try? NSRegularExpression(pattern: amountPatternStr),
              let match = regex.firstMatch(in: joined, range: NSRange(joined.startIndex..., in: joined)) else {
            return .unknown
        }
        let len = joined.utf16.count
        guard len > 0 else { return .unknown }
        let ratio = Double(match.range.location) / Double(len)
        if ratio >= 0.70 { return .suffix }
        if ratio <= 0.20 { return .prefix }
        return .inline
    }

    private static let datePatternStr = #"\d{4}[-./]\d{1,2}[-./]\d{1,2}|\d{1,2}[-./]\d{1,2}[-./]\d{2,4}"#

    private static func detectDatePlacement(in lines: [String]) -> (hasDate: Bool, lineIndex: Int?) {
        guard let regex = try? NSRegularExpression(pattern: datePatternStr) else {
            return (false, nil)
        }
        for (idx, line) in lines.enumerated() {
            if regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                return (true, idx)
            }
        }
        return (false, nil)
    }
}
