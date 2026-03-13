//
//  AnalyzingTransactionsView.swift
//  Airy
//
//  Full-screen processing UI when importing screenshot. Shows mascot, status, progress stepper,
//  and live extraction list with staggered animation.
//

import SwiftUI

struct AnalyzingTransactionsView: View {
    let images: [UIImage]
    let importViewModel: ImportViewModel
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var extractedItems: [ParsedTransactionItem] = []
    @State private var statusPhraseIndex = 0
    @State private var visibleItemCount = 0
    @State private var thumbOrder: [Int] = [0, 1, 2]
    @State private var thumbSwapPairIndex = 0

    /// Order and 2s each; last stays until result. Smooth transition per design.
    private let statusPhrases = [
        "Reading amounts...",
        "Checking dates...",
        "Looking for duplicates...",
        "Matching categories...",
        "Saving new rules...",
        "Almost done..."
    ]

    var body: some View {
        ZStack {
            OnboardingGradientBackground()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { onCancel() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(OnboardingDesign.textSecondary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

                uploadPreviews
                processingCenter
                progressStepper
                extractionList
                Spacer(minLength: 0)
                footerAction
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .onAppear {
            importViewModel.startAnalyzing(images: images)
            startStatusPhraseCycling()
            startThumbShuffle()
        }
        .onChange(of: importViewModel.analyzingItems) { _, new in
            if new != nil {
                extractedItems = new ?? []
                visibleItemCount = 0
                revealItemsStaggered()
            }
        }
    }

    private static let thumbWidth: CGFloat = 60
    private static let thumbHeight: CGFloat = 80
    private static let thumbGap: CGFloat = 12
    private static let thumbSwapPairs: [(Int, Int)] = [(0, 1), (1, 2), (0, 2), (2, 1), (0, 2), (1, 0)]

    /// Three thumbnails in a row; middle (2nd) card centered. Clear fixed-size base so HStack centers 204pt block; ZStack overlay for shuffle.
    private var uploadPreviews: some View {
        let totalWidth = Self.thumbWidth * 3 + Self.thumbGap * 2
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            Color.clear
                .frame(width: totalWidth, height: Self.thumbHeight)
                .overlay(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        ForEach(0..<3, id: \.self) { cardId in
                            let slot = thumbOrder.firstIndex(of: cardId) ?? cardId
                            let x = CGFloat(slot) * (Self.thumbWidth + Self.thumbGap)
                            let opacity = slot == 1 ? 1.0 : (slot == 0 ? 0.9 : 0.6)
                            thumbnailBoxPlaceholder(opacity: opacity)
                                .offset(x: x)
                                .animation(.easeInOut(duration: 0.7), value: thumbOrder)
                        }
                    }
                }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .padding(.bottom, 20)
    }

    /// Cycle status phrases every ~2.5s while waiting for GPT (Task-based so it runs reliably in fullScreenCover).
    private func startStatusPhraseCycling() {
        Task { @MainActor in
            statusPhraseIndex = 0
            var waitCount = 0
            while !importViewModel.isAnalyzing, waitCount < 50 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waitCount += 1
            }
            while importViewModel.isAnalyzing {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard importViewModel.isAnalyzing else { break }
                if statusPhraseIndex < statusPhrases.count - 1 {
                    withAnimation(.easeInOut(duration: 0.35)) { statusPhraseIndex += 1 }
                }
            }
        }
    }

    /// Shuffle thumbnail positions every ~2.4s while analyzing.
    private func startThumbShuffle() {
        Task { @MainActor in
            var waitCount = 0
            while !importViewModel.isAnalyzing, waitCount < 50 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waitCount += 1
            }
            while importViewModel.isAnalyzing {
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                guard importViewModel.isAnalyzing else { break }
                performThumbSwap()
            }
        }
    }

    private func performThumbSwap() {
        let (a, b) = Self.thumbSwapPairs[thumbSwapPairIndex % Self.thumbSwapPairs.count]
        thumbSwapPairIndex += 1
        let slotA = thumbOrder.firstIndex(of: a)!
        let slotB = thumbOrder.firstIndex(of: b)!
        withAnimation(.easeInOut(duration: 0.7)) {
            thumbOrder[slotA] = b
            thumbOrder[slotB] = a
        }
    }

    private func thumbnailBoxPlaceholder(opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(opacity * 0.9), Color.white.opacity(opacity * 0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 24))
                    .foregroundColor(OnboardingDesign.textTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
            )
            .frame(width: Self.thumbWidth, height: Self.thumbHeight)
    }

    private var processingCenter: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [OnboardingDesign.accentBlue.opacity(0.4), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .blur(radius: 8)
                    .opacity(importViewModel.isAnalyzing ? 0.25 : 0.1)
                    .scaleEffect(importViewModel.isAnalyzing ? 1.2 : 0.8)
                    .animation(
                        importViewModel.isAnalyzing ? .easeInOut(duration: 3).repeatForever(autoreverses: true) : .default,
                        value: importViewModel.isAnalyzing
                    )

                CloudFloatView()
            }

            Text(importViewModel.isAnalyzing ? statusPhrases[statusPhraseIndex] : "Ready")
                .id(statusPhraseIndex)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(OnboardingDesign.textSecondary)
                .frame(height: 20)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .animation(.easeInOut(duration: 0.35), value: statusPhraseIndex)
                .animation(.easeInOut(duration: 0.2), value: importViewModel.isAnalyzing)
        }
        .padding(.vertical, 20)
    }

    private var progressStepper: some View {
        HStack {
            stepView(label: "Upload", isCompleted: true, isActive: false)
            progressLine
            stepView(label: "Extract", isCompleted: !importViewModel.isAnalyzing, isActive: importViewModel.isAnalyzing)
            progressLine
            stepView(label: "Review", isCompleted: false, isActive: false)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 24)
    }

    private func stepView(label: String, isCompleted: Bool, isActive: Bool) -> some View {
        VStack(spacing: 8) {
            Circle()
                .fill(isCompleted || isActive ? OnboardingDesign.accentGreen : Color.white.opacity(0.5))
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(isActive ? Color.white : OnboardingDesign.glassBorder, lineWidth: 2)
                )
                .scaleEffect(isActive ? 1.2 : 1)
                .shadow(color: isActive ? OnboardingDesign.accentGreen.opacity(0.5) : .clear, radius: 6)
                .animation(.easeInOut(duration: 0.3), value: isActive)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isActive || isCompleted ? OnboardingDesign.textPrimary : OnboardingDesign.textTertiary)
        }
    }

    private var progressLine: some View {
        Rectangle()
            .fill(Color.white.opacity(0.3))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }

    private var extractionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LIVE EXTRACTION")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(OnboardingDesign.textTertiary)
                .tracking(0.5)
                .padding(.bottom, 12)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(extractedItems.prefix(visibleItemCount).enumerated()), id: \.offset) { _, item in
                        extractionRow(item: item)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.92)).combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                    }
                    if importViewModel.isAnalyzing || visibleItemCount < extractedItems.count {
                        shimmerRow
                    }
                    if !importViewModel.isAnalyzing && extractedItems.isEmpty && importViewModel.errorMessage != nil {
                        Text(importViewModel.errorMessage ?? "")
                            .font(.system(size: 13))
                            .foregroundColor(OnboardingDesign.textSecondary)
                            .padding()
                    }
                    if !importViewModel.isAnalyzing && extractedItems.isEmpty && importViewModel.errorMessage == nil && importViewModel.resultMessage != nil {
                        Text(importViewModel.resultMessage ?? "")
                            .font(.system(size: 13))
                            .foregroundColor(OnboardingDesign.textSecondary)
                            .padding()
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(OnboardingDesign.glassBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
                )
                .shadow(color: Color(red: 0.118, green: 0.176, blue: 0.141).opacity(0.06), radius: 32, x: 0, y: 8)
        )
    }

    private func extractionRow(item: ParsedTransactionItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: categoryIcon(for: item.merchant))
                            .font(.system(size: 20))
                            .foregroundColor(categoryColor(for: item.merchant))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(OnboardingDesign.glassHighlight, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.merchant ?? "Transaction")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(OnboardingDesign.textPrimary)
                        Spacer()
                        Text(formatAmount(item.amount, item.currency))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(OnboardingDesign.textPrimary)
                    }
                    Text(categoryLabel(for: item.merchant))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textTertiary)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 4)

            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(height: 1)
        }
    }

    private var shimmerRow: some View {
        ShimmerRowView()
            .padding(.vertical, 14)
    }

    private var footerAction: some View {
        Button {
            importViewModel.addProcessedToPending()
            onConfirm()
        } label: {
            Text("Confirm Transactions")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(extractedItems.isEmpty ? OnboardingDesign.textTertiary : OnboardingDesign.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )
        )
        .disabled(extractedItems.isEmpty)
        .padding(.top, 20)
    }

    private func revealItemsStaggered() {
        Task { @MainActor in
            for i in 0..<extractedItems.count {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                    visibleItemCount = i + 1
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    private func categoryIcon(for merchant: String?) -> String {
        let m = (merchant ?? "").lowercased()
        if m.contains("coffee") || m.contains("food") || m.contains("restaurant") || m.contains("grocery") { return "cup.and.saucer.fill" }
        if m.contains("gas") || m.contains("shell") || m.contains("uber") || m.contains("taxi") || m.contains("transit") { return "car.fill" }
        return "creditcard.fill"
    }

    private func categoryColor(for merchant: String?) -> Color {
        let m = (merchant ?? "").lowercased()
        if m.contains("coffee") || m.contains("food") || m.contains("restaurant") || m.contains("grocery") { return OnboardingDesign.accentGreen }
        if m.contains("gas") || m.contains("shell") || m.contains("uber") || m.contains("taxi") || m.contains("transit") { return OnboardingDesign.accentBlue }
        return OnboardingDesign.textSecondary
    }

    private func categoryLabel(for merchant: String?) -> String {
        let m = (merchant ?? "").lowercased()
        if m.contains("coffee") || m.contains("food") || m.contains("restaurant") || m.contains("grocery") { return "Food & Drink" }
        if m.contains("gas") || m.contains("shell") || m.contains("uber") || m.contains("taxi") || m.contains("transit") { return "Transportation" }
        return "Other"
    }

    private func formatAmount(_ amount: Double, _ currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount) \(currency)"
    }
}

private struct CloudFloatView: View {
    @State private var offset: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.9), Color.white.opacity(0.2)],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 45
                    )
                )
                .frame(width: 80, height: 80)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 24, x: 0, y: 8)
            Image(systemName: "cloud.fill")
                .font(.system(size: 40))
                .foregroundColor(OnboardingDesign.textPrimary)
        }
        .offset(y: offset)
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                offset = -12
            }
        }
    }
}

private struct ShimmerRowView: View {
    @State private var opacity: Double = 0.3

    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(opacity))
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(opacity))
                        .frame(width: 120, height: 14)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(opacity))
                        .frame(width: 40, height: 14)
                }
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(opacity * 0.7))
                    .frame(width: 60, height: 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                opacity = 0.6
            }
        }
    }
}
