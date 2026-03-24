//
//  AnalyzingTransactionsView.swift
//  Airy
//
//  Live extraction view: shows queue progress and extracted transactions in real time.
//  Processing runs in the background (ImportViewModel.shared) and continues if this view is closed.
//

import SwiftUI

struct AnalyzingTransactionsView: View {
    let importViewModel: ImportViewModel
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(ThemeProvider.self) private var theme
    @State private var extractedItems: [ParsedTransactionItem] = []
    @State private var visibleItemCount = 0
    @State private var statusPhraseIndex = 0
    @State private var thumbOrder: [Int] = [0, 1, 2]
    @Namespace private var thumbNS

    private let statusPhrases = [
        L("analyzing_reading"),
        L("analyzing_dates"),
        L("analyzing_duplicates"),
        L("analyzing_categories"),
        L("analyzing_rules"),
        L("analyzing_almost")
    ]

    var body: some View {
        ZStack {
            OnboardingGradientBackground()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { onCancel() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(theme.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
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
            print("[Nav] AnalyzingTransactions")
            extractedItems = importViewModel.liveExtractedItems
            visibleItemCount = extractedItems.count
            startStatusPhraseCycling()
            startThumbShuffle()
        }
        .onChange(of: importViewModel.liveExtractedItems) { _, new in
            let newItems = Array(new.dropFirst(extractedItems.count))
            extractedItems = new
            if !newItems.isEmpty { revealItemsStaggered(startFrom: extractedItems.count - newItems.count) }
        }
    }

    // MARK: - Queue thumbnails

    private var uploadPreviews: some View {
        let thumbWidth: CGFloat = 60
        let thumbHeight: CGFloat = 80
        let gap: CGFloat = 12
        let queueImages = importViewModel.imageQueue.prefix(3).map { $0.image }

        return HStack(spacing: gap) {
            ForEach(Array(thumbOrder.enumerated()), id: \.element) { posIdx, queueIdx in
                let opacity: Double = posIdx == 0 ? 1.0 : posIdx == 1 ? 0.85 : 0.55
                Group {
                    if queueIdx < queueImages.count {
                        Image(uiImage: queueImages[queueIdx])
                            .resizable()
                            .scaledToFill()
                            .frame(width: thumbWidth, height: thumbHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.glassBorder, lineWidth: 1))
                    } else {
                        thumbnailPlaceholder(opacity: opacity)
                    }
                }
                .opacity(opacity)
                .matchedGeometryEffect(id: queueIdx, in: thumbNS)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 20)
    }

    private func thumbnailPlaceholder(opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(LinearGradient(
                colors: [Color.white.opacity(opacity * 0.9), Color.white.opacity(opacity * 0.4)],
                startPoint: .top, endPoint: .bottom
            ))
            .overlay(Image(systemName: "photo").font(.system(size: 24)).foregroundColor(theme.textTertiary))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.glassBorder, lineWidth: 1))
            .frame(width: 60, height: 80)
    }

    // MARK: - Processing center

    private var processingCenter: some View {
        let total = importViewModel.imageQueue.count
        let done = importViewModel.imageQueue.filter { $0.status == .completed || $0.status == .failed }.count

        return VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [theme.accentBlue.opacity(0.4), Color.clear],
                        center: .center, startRadius: 0, endRadius: 60
                    ))
                    .frame(width: 120, height: 120)
                    .blur(radius: 8)
                    .opacity(importViewModel.isAnalyzing ? 0.25 : 0.1)
                    .scaleEffect(importViewModel.isAnalyzing ? 1.2 : 0.8)
                    .animation(
                        importViewModel.isAnalyzing
                            ? .easeInOut(duration: 3).repeatForever(autoreverses: true)
                            : .default,
                        value: importViewModel.isAnalyzing
                    )

                CloudFloatView()
            }

            if importViewModel.isAnalyzing && total > 0 {
                Text("\(done) / \(total) processed")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(theme.textSecondary)
                    .frame(height: 20)
                    .animation(.easeInOut(duration: 0.2), value: done)
            } else {
                Text(importViewModel.isAnalyzing ? statusPhrases[statusPhraseIndex] : L("analyzing_ready"))
                    .id(statusPhraseIndex)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(theme.textSecondary)
                    .frame(height: 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .animation(.easeInOut(duration: 0.35), value: statusPhraseIndex)
                    .animation(.easeInOut(duration: 0.2), value: importViewModel.isAnalyzing)
            }
        }
        .padding(.vertical, 20)
    }

    // MARK: - Progress stepper

    private var progressStepper: some View {
        HStack {
            stepView(label: L("analyzing_upload"), isCompleted: true, isActive: false)
            progressLine
            stepView(label: L("analyzing_extract"), isCompleted: !importViewModel.isAnalyzing, isActive: importViewModel.isAnalyzing)
            progressLine
            stepView(label: L("analyzing_review"), isCompleted: false, isActive: false)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 24)
    }

    private func stepView(label: String, isCompleted: Bool, isActive: Bool) -> some View {
        VStack(spacing: 8) {
            Circle()
                .fill(isCompleted || isActive ? theme.accentGreen : Color.white.opacity(0.5))
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(isActive ? Color.white : theme.glassBorder, lineWidth: 2))
                .scaleEffect(isActive ? 1.2 : 1)
                .shadow(color: isActive ? theme.accentGreen.opacity(0.5) : .clear, radius: 6)
                .animation(.easeInOut(duration: 0.3), value: isActive)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isActive || isCompleted ? theme.textPrimary : theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var progressLine: some View {
        Rectangle()
            .fill(Color.white.opacity(0.3))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Extraction list

    private var extractionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("analyzing_live"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(theme.textTertiary)
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
                    if importViewModel.isAnalyzing {
                        ShimmerRowView()
                            .padding(.vertical, 14)
                    }
                    if !importViewModel.isAnalyzing && extractedItems.isEmpty {
                        if importViewModel.duplicatesSkippedCount > 0 {
                            VStack(spacing: 6) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 28))
                                    .foregroundColor(theme.accentGreen)
                                Text(L("analyzing_all_duplicates"))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(theme.textSecondary)
                                Text("\(importViewModel.duplicatesSkippedCount) \(L("analyzing_duplicates_skipped"))")
                                    .font(.system(size: 12))
                                    .foregroundColor(theme.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        } else if let err = importViewModel.errorMessage {
                            Text(err)
                                .font(.system(size: 13))
                                .foregroundColor(theme.textSecondary)
                                .padding()
                        } else if let msg = importViewModel.resultMessage {
                            Text(msg)
                                .font(.system(size: 13))
                                .foregroundColor(theme.textSecondary)
                                .padding()
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(theme.glassBg)
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(theme.glassBorder, lineWidth: 1))
                .shadow(color: Color(red: 0.118, green: 0.176, blue: 0.141).opacity(0.06), radius: 32, x: 0, y: 8)
        )
    }

    private func extractionRow(item: ParsedTransactionItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(categoryColor(for: item).opacity(0.18))
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: categoryIcon(for: item)).font(.system(size: 20)).foregroundColor(categoryColor(for: item)))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.glassHighlight, lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.merchant ?? "Transaction")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                        Spacer()
                        Text(formatAmount(item.amount, item.currency))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                    }
                    Text(categoryLabel(for: item))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.textTertiary)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 4)

            Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1)
        }
    }

    // MARK: - Footer

    private var footerAction: some View {
        Button {
            importViewModel.addProcessedToPending()
            onConfirm()
        } label: {
            HStack(spacing: 8) {
                if importViewModel.isAnalyzing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(theme.textTertiary)
                }
                Text(importViewModel.isAnalyzing ? L("analyzing_processing") : L("analyzing_confirm"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(
                        (importViewModel.isAnalyzing || extractedItems.isEmpty)
                            ? theme.textTertiary
                            : theme.textPrimary
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.3))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.5), lineWidth: 1))
        )
        .disabled(importViewModel.isAnalyzing || extractedItems.isEmpty)
        .padding(.top, 20)
    }

    // MARK: - Helpers

    private func startThumbShuffle() {
        Task { @MainActor in
            while true {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                let count = importViewModel.imageQueue.count
                guard count >= 2 else { continue }
                let maxSlot = min(count - 1, 2)
                guard maxSlot >= 1 else { continue }
                let a = Int.random(in: 0...maxSlot)
                var b = Int.random(in: 0...maxSlot)
                while b == a { b = Int.random(in: 0...maxSlot) }
                withAnimation(.spring(response: 0.52, dampingFraction: 0.7)) {
                    thumbOrder.swapAt(a, b)
                }
            }
        }
    }

    private func startStatusPhraseCycling() {
        Task { @MainActor in
            statusPhraseIndex = 0
            while importViewModel.isAnalyzing {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard importViewModel.isAnalyzing else { break }
                if statusPhraseIndex < statusPhrases.count - 1 {
                    withAnimation(.easeInOut(duration: 0.35)) { statusPhraseIndex += 1 }
                }
            }
        }
    }

    private func revealItemsStaggered(startFrom: Int) {
        Task { @MainActor in
            for i in startFrom..<extractedItems.count {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                    visibleItemCount = i + 1
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    private func categoryIcon(for item: ParsedTransactionItem) -> String {
        if let cid = item.categoryId, !cid.isEmpty, cid != "other" {
            return CategoryIconHelper.iconName(categoryId: cid)
        }
        return "creditcard.fill"
    }

    private func categoryColor(for item: ParsedTransactionItem) -> Color {
        if let cid = item.categoryId, !cid.isEmpty, cid != "other",
           let cat = CategoryStore.byId(cid) {
            return cat.color
        }
        return theme.textSecondary
    }

    private func categoryLabel(for item: ParsedTransactionItem) -> String {
        if let cid = item.categoryId, !cid.isEmpty, cid != "other",
           let cat = CategoryStore.byId(cid) {
            return cat.name
        }
        return "Other"
    }

    private func formatAmount(_ amount: Double, _ currency: String) -> String {
        AppFormatters.currency(code: currency).string(from: NSNumber(value: amount)) ?? "\(amount) \(currency)"
    }
}

// MARK: - Supporting views

private struct CloudFloatView: View {
    @Environment(ThemeProvider.self) private var theme
    @State private var offset: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color.white.opacity(0.9), Color.white.opacity(0.2)],
                    center: .topLeading, startRadius: 0, endRadius: 45
                ))
                .frame(width: 80, height: 80)
                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 24, x: 0, y: 8)
            Image(systemName: "cloud.fill")
                .font(.system(size: 40))
                .foregroundColor(theme.textPrimary)
        }
        .offset(y: offset)
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { offset = -12 }
        }
    }
}

private struct ShimmerRowView: View {
    @State private var phase: CGFloat = -1.0

    private var shimmer: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.12), location: 0),
                .init(color: Color.white.opacity(0.38), location: 0.45),
                .init(color: Color.white.opacity(0.12), location: 1),
            ],
            startPoint: UnitPoint(x: phase, y: 0.5),
            endPoint: UnitPoint(x: phase + 1, y: 0.5)
        )
    }

    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 16).fill(shimmer).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    RoundedRectangle(cornerRadius: 4).fill(shimmer).frame(width: 120, height: 14)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4).fill(shimmer).frame(width: 40, height: 14)
                }
                RoundedRectangle(cornerRadius: 4).fill(shimmer).frame(width: 60, height: 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }
}
