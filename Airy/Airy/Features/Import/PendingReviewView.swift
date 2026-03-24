//
//  PendingReviewView.swift
//  Airy
//
//  Review transactions screen. Confirm, edit, or skip before saving.
//

import SwiftUI

struct PendingReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeProvider.self) private var theme
    @State private var viewModel = PendingReviewViewModel()
    @State private var editPending: PendingTransaction?
    @State private var rememberRules: [String: Bool] = [:]
    @State private var isSaving = false
    @State private var isSkipping = false

    var body: some View {
        ZStack(alignment: .bottom) {
            OnboardingGradientBackground()
            if viewModel.isLoading || viewModel.pending.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        } else {
                            emptyState
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 140)
                }
                .scrollIndicators(.hidden)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    List {
                        ForEach(viewModel.cardDataList) { card in
                            cardFor(card)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                                .listRowBackground(Color.clear)
                                .listRowSpacing(8)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        withAnimation(.smooth(duration: 0.35)) {
                                            viewModel.removePendingLocally(ids: [card.id])
                                        }
                                        Task { await viewModel.persistReject(id: card.id) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .animation(.smooth(duration: 0.35), value: viewModel.cardDataList.map(\.id))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 140)
            }
            stickyBottom
        }
        .navigationTitle(L("pending_title"))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: isSaving) { _, new in new }
        .onAppear { print("[Nav] PendingReview") }
        .task { await viewModel.load() }
        .sheet(item: $editPending) { pending in
            let matchedInterval = viewModel.cardDataList.first { $0.id == pending.id }?.matchedSubscriptionInterval
            AddTransactionView(
                pendingTransaction: pending,
                rememberMerchant: rememberRules[pending.id] ?? true,
                matchedSubscriptionInterval: matchedInterval,
                onConfirm: { overrides, remember in
                    Task {
                        rememberRules[pending.id] = remember
                        await viewModel.confirm(id: pending.id, overrides: overrides, rememberMerchant: remember)
                        await MainActor.run { editPending = nil }
                    }
                },
                onCancel: { editPending = nil }
            )
            .themed(theme)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(L("pending_title"))
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.5)
                    .foregroundColor(theme.textPrimary)
                Text("\(viewModel.pending.count) \(L("pending_found"))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(theme.accentGreen)
                    .clipShape(Capsule())
            }
            Text(L("pending_subtitle"))
                .font(.system(size: 14))
                .foregroundColor(theme.textSecondary)
        }
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(theme.accentGreen)
            Text(L("pending_empty"))
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    @ViewBuilder
    private func cardFor(_ card: ReviewCardData) -> some View {
        let binding = Binding(
            get: { rememberRules[card.id] ?? true },
            set: { rememberRules[card.id] = $0 }
        )
        TransactionReviewCard(
            merchant: card.merchant,
            amount: card.amount,
            currency: card.currency,
            date: card.date,
            time: card.time,
            isIncome: card.isIncome,
            categoryLabel: card.categoryLabel,
            subcategoryLabel: card.subcategoryLabel,
            categoryIcon: card.categoryIcon,
            isLowConfidence: card.isLowConfidence,
            confidencePercent: card.confidencePercent,
            isDuplicate: card.duplicateSeenText != nil,
            duplicateSeenText: card.duplicateSeenText,
            matchedSubscriptionInterval: card.matchedSubscriptionInterval,
            rememberRule: binding,
            onTap: {
                print("[Tap] PendingReview → Edit card '\(card.merchant)'")
                editPending = viewModel.pending.first { $0.id == card.id }
            }
        )
    }

    private var stickyBottom: some View {
        VStack(spacing: 16) {
            Button {
                print("[Tap] PendingReview → Save All (\(viewModel.pending.count) items)")
                Task { await saveAll() }
            } label: {
                Text(L("pending_save_all"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(theme.isDark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(theme.textPrimary)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
            )
            .disabled(viewModel.pending.isEmpty || isSaving)
            .opacity(viewModel.pending.isEmpty ? 0.6 : 1)

            Button {
                Task { await skipBatch() }
            } label: {
                Text(L("pending_skip"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(theme.textSecondary)
            }
            .disabled(viewModel.pending.isEmpty || isSkipping)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.clear, theme.bgBottomRight],
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

}

#Preview {
    NavigationStack {
        PendingReviewView()
    }
}
