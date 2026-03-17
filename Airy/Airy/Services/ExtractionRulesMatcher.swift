//
//  ExtractionRulesMatcher.swift
//  Airy
//
//  Tries structured rules first, then legacy ParsingRulesStore (structure-assist). Outcome-based: only confidentParse skips GPT.
//

import Foundation

enum ExtractionRulesMatcher {
    /// Try structured local rules first, then legacy rule sets. Returns first valid parse that matches OCR.
    /// For outcome-based flow use tryStructuredThenLegacyWithOutcome so only promoted legacy rules block GPT.
    static func tryStructuredThenLegacy(ocrText: String, parser: LocalOCRParser, baseCurrency: String) -> [ParsedTransactionItem]? {
        let result = tryStructuredThenLegacyWithOutcome(
            ocrText: ocrText,
            parser: parser,
            baseCurrency: baseCurrency,
            transactionLikeRowEstimate: nil,
            strongAmountRowCount: nil,
            repeatedRowClusterCount: nil
        )
        if case .confidentParse = result.outcome, let items = result.items, !items.isEmpty {
            return items
        }
        return nil
    }

    /// Outcome-based: only confidentParse skips GPT; noMatch, structureAssistOnly, weakParse, abstain, hardFail → pipeline uses GPT.
    static func tryStructuredThenLegacyWithOutcome(
        ocrText: String,
        parser: LocalOCRParser,
        baseCurrency: String,
        transactionLikeRowEstimate: Int?,
        strongAmountRowCount: Int?,
        repeatedRowClusterCount: Int?
    ) -> LocalRuleMatchResult {
        let rules = StructuredLocalRulesStore.shared.allRules()
        for rule in rules {
            let parsingRules = rule.toParsingRules(baseCurrency: baseCurrency)
            let items = parser.parse(ocrText: ocrText, baseCurrency: baseCurrency, customRules: parsingRules)
            if ParsingRulesStore.shared.isValidResultMatchingOcr(items, ocrText: ocrText) {
                return LocalRuleMatchResult(outcome: .abstain, items: items, matchedRuleId: nil, matchedRuleTrustStage: nil, reasonAbstain: "structured rule matched; only legacy promoted blocks GPT")
            }
        }
        return ParsingRulesStore.shared.tryStructureAssist(
            ocrText: ocrText,
            parser: parser,
            baseCurrency: baseCurrency,
            transactionLikeRowEstimate: transactionLikeRowEstimate,
            strongAmountRowCount: strongAmountRowCount,
            repeatedRowClusterCount: repeatedRowClusterCount
        )
    }
}
