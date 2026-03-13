//
//  PendingReviewView.swift
//  Airy
//
//  Review transactions screen. Confirm, edit, or skip before saving.
//

import SwiftUI

struct PendingReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = PendingReviewViewModel()
    @State private var editPending: PendingTransaction?
    @State private var rememberRules: [String: Bool] = [:]
    @State private var isSaving = false
    @State private var isSkipping = false

    var body: some View {
        ZStack(alignment: .bottom) {
            OnboardingGradientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if viewModel.pending.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.pending) { item in
                            cardFor(item)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 140)
            }
            stickyBottom
        }
        .navigationTitle("Review Transactions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .sheet(item: $editPending) { pending in
            AddTransactionView(
                pendingTransaction: pending,
                rememberMerchant: rememberRules[pending.id] ?? true,
                onConfirm: { overrides, remember in
                    Task {
                        rememberRules[pending.id] = remember
                        await viewModel.confirm(id: pending.id, overrides: overrides, rememberMerchant: remember)
                        await MainActor.run { editPending = nil }
                    }
                },
                onCancel: { editPending = nil }
            )
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text("Review Transactions")
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.5)
                    .foregroundColor(OnboardingDesign.textPrimary)
                Text("\(viewModel.pending.count) found")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(OnboardingDesign.accentGreen)
                    .clipShape(Capsule())
            }
            Text("Tap to edit before saving")
                .font(.system(size: 14))
                .foregroundColor(OnboardingDesign.textSecondary)
        }
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(OnboardingDesign.accentGreen)
            Text("No pending transactions")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(OnboardingDesign.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func cardFor(_ item: PendingTransaction) -> some View {
        guard let p = item.decodedPayload else { return AnyView(EmptyView()) }
        let merchant = p.merchant ?? "Transaction"
        let effectiveCategoryId = MerchantCategoryRuleStore.shared.categoryId(for: merchant) ?? p.category
        let effectiveIcon: String = {
            if let cid = effectiveCategoryId, !cid.isEmpty, cid != "other" {
                return CategoryIconHelper.iconName(categoryId: cid)
            }
            return categoryIcon(for: merchant)
        }()
        let isLowConfidence = isLowConfidenceMerchant(merchant) || (item.confidence ?? 1) < 0.6
        let dupText = viewModel.duplicateSeenText(for: p, excludePendingId: item.id)
        let binding = Binding(
            get: { rememberRules[item.id] ?? true },
            set: { rememberRules[item.id] = $0 }
        )
        let isIncome = (p.type ?? "expense").lowercased() == "income"
        return AnyView(
            TransactionReviewCard(
                merchant: merchant,
                amount: p.amountOriginal ?? 0,
                currency: p.currencyOriginal ?? "USD",
                date: p.transactionDate ?? "",
                time: p.transactionTime,
                isIncome: isIncome,
                categoryLabel: categoryLabel(for: merchant, categoryId: effectiveCategoryId),
                categoryIcon: effectiveIcon,
                isLowConfidence: isLowConfidence,
                confidencePercent: isLowConfidence ? (item.confidence ?? 0.45) * 100 : nil,
                isDuplicate: dupText != nil,
                duplicateSeenText: dupText,
                rememberRule: binding,
                onTap: { editPending = item }
            )
        )
    }

    private var stickyBottom: some View {
        VStack(spacing: 16) {
            Button {
                Task { await saveAll() }
            } label: {
                Text("Save All Transactions")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(OnboardingDesign.textPrimary)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
            )
            .disabled(viewModel.pending.isEmpty || isSaving)
            .opacity(viewModel.pending.isEmpty ? 0.6 : 1)

            Button {
                Task { await skipBatch() }
            } label: {
                Text("Skip this batch")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(OnboardingDesign.textSecondary)
            }
            .disabled(viewModel.pending.isEmpty || isSkipping)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.clear, OnboardingDesign.bgBottomRight],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(maxWidth: .infinity)
        .allowsHitTesting(!isSaving && !isSkipping)
    }

    private func saveAll() async {
        isSaving = true
        await viewModel.confirmAll(rememberRules: rememberRules)
        isSaving = false
        dismiss()
    }

    private func skipBatch() async {
        isSkipping = true
        await viewModel.rejectAll()
        isSkipping = false
        dismiss()
    }

    private func isLowConfidenceMerchant(_ merchant: String) -> Bool {
        merchant.contains("_") || merchant.count < 3 || merchant == "Transaction"
    }

    private func categoryLabel(for merchant: String, categoryId: String?) -> String {
        if let cat = categoryId, !cat.isEmpty, cat != "other" {
            if let c = CategoryStore.byId(cat) { return c.name }
        }
        let m = merchant.lowercased()
        if m.contains("coffee") || m.contains("food") || m.contains("restaurant") || m.contains("grocery") { return "Food & Drink" }
        if m.contains("gas") || m.contains("shell") || m.contains("uber") || m.contains("taxi") || m.contains("transit") { return "Transportation" }
        if m.contains("grocery") || m.contains("whole foods") || m.contains("market") { return "Groceries" }
        if m.contains("netflix") || m.contains("spotify") || m.contains("hulu") || m.contains("entertainment") { return "Entertainment" }
        return "Other"
    }

    private func categoryIcon(for merchant: String) -> String {
        let m = merchant.lowercased()
        if m.contains("coffee") || m.contains("food") || m.contains("restaurant") { return "cup.and.saucer.fill" }
        if m.contains("gas") || m.contains("shell") || m.contains("uber") || m.contains("taxi") || m.contains("transit") { return "car.fill" }
        if m.contains("grocery") || m.contains("whole foods") || m.contains("market") { return "bag.fill" }
        if m.contains("netflix") || m.contains("spotify") || m.contains("hulu") { return "rectangle.grid.1x2.fill" }
        return "creditcard.fill"
    }

}

#Preview {
    NavigationStack {
        PendingReviewView()
    }
}
