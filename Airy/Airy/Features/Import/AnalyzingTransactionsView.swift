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
    @State private var isProcessing = true
    @State private var statusPhraseIndex = 0
    @State private var visibleItemCount = 0
    @State private var thumbHighlightIndex = 0

    private let statusPhrases = [
        "Reading amounts...",
        "Checking dates...",
        "Matching categories...",
        "Looking for duplicates...",
        "Almost done"
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
        .task {
            let allItems = await importViewModel.processImagesReturningItems(images)
            await MainActor.run {
                isProcessing = false
                extractedItems = allItems
                visibleItemCount = 0
                revealItemsStaggered()
            }
        }
        .onReceive(Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()) { _ in
            if isProcessing {
                statusPhraseIndex = (statusPhraseIndex + 1) % statusPhrases.count
            }
        }
        .onReceive(Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()) { _ in
            if isProcessing {
                thumbHighlightIndex = (thumbHighlightIndex + 1) % 3
            }
        }
    }

    private var uploadPreviews: some View {
        HStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { i in
                thumbnailBoxPlaceholder(isHighlighted: i == thumbHighlightIndex)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 20)
    }

    private func thumbnailBoxPlaceholder(isHighlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(isHighlighted ? 0.9 : 0.6), Color.white.opacity(isHighlighted ? 0.4 : 0.2)],
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
            .frame(width: 60, height: 80)
            .opacity(isHighlighted ? 1 : 0.6)
            .scaleEffect(isHighlighted ? 1.02 : 1)
            .animation(.easeInOut(duration: 0.4), value: thumbHighlightIndex)
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
                    .opacity(isProcessing ? 0.25 : 0.1)
                    .scaleEffect(isProcessing ? 1.2 : 0.8)
                    .animation(
                        isProcessing ? .easeInOut(duration: 3).repeatForever(autoreverses: true) : .default,
                        value: isProcessing
                    )

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
                .offset(y: isProcessing ? -12 : 0)
                .animation(
                    isProcessing ? .easeInOut(duration: 4).repeatForever(autoreverses: true) : .default,
                    value: isProcessing
                )
            }

            Text(statusPhrases[statusPhraseIndex])
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(OnboardingDesign.textSecondary)
                .frame(height: 20)
                .animation(.easeInOut(duration: 0.3), value: statusPhraseIndex)
        }
        .padding(.vertical, 20)
    }

    private var progressStepper: some View {
        HStack {
            stepView(label: "Upload", isCompleted: true, isActive: false)
            progressLine
            stepView(label: "Extract", isCompleted: !isProcessing, isActive: isProcessing)
            progressLine
            stepView(label: "Review", isCompleted: !isProcessing && !extractedItems.isEmpty, isActive: false)
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
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                    }
                    if isProcessing || visibleItemCount < extractedItems.count {
                        shimmerRow
                    }
                    if !isProcessing && extractedItems.isEmpty && importViewModel.errorMessage != nil {
                        Text(importViewModel.errorMessage ?? "")
                            .font(.system(size: 13))
                            .foregroundColor(OnboardingDesign.textSecondary)
                            .padding()
                    }
                    if !isProcessing && extractedItems.isEmpty && importViewModel.errorMessage == nil && importViewModel.resultMessage != nil {
                        Text(importViewModel.resultMessage ?? "")
                            .font(.system(size: 13))
                            .foregroundColor(OnboardingDesign.textSecondary)
                            .padding()
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .padding(20)
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
                withAnimation(.easeOut(duration: 0.3)) {
                    visibleItemCount = i + 1
                }
                try? await Task.sleep(nanoseconds: 80_000_000)
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

private struct ShimmerRowView: View {
    @State private var opacity: Double = 0.3

    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(opacity))
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(opacity))
                    .frame(width: 120, height: 14)
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
