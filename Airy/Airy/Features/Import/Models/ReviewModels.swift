//
//  ReviewModels.swift
//  Airy
//
//  Review UI models and actions.
//

import Foundation

struct ReviewTransactionCard: Identifiable {
    let id: UUID
    var candidate: CandidateTransaction
    var reviewAction: ReviewAction?

    init(candidate: CandidateTransaction, reviewAction: ReviewAction? = nil) {
        self.id = candidate.id
        self.candidate = candidate
        self.reviewAction = reviewAction
    }
}

enum ReviewAction {
    case confirm
    case edit(ConfirmPendingOverrides)
    case skip
    case markDuplicate
    case rememberMerchant(category: String?)
    case ignoreFailed
}
