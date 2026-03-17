//
//  AiryLiveActivity.swift
//  AiryWidgets
//
//  Dynamic Island + Lock Screen Live Activity for the import pipeline.
//

import SwiftUI
import WidgetKit
import ActivityKit

private let airyGreen = Color(red: 0.40, green: 0.63, blue: 0.51)

// MARK: - Lock Screen / Banner

struct AiryLiveActivityView: View {
    let context: ActivityViewContext<AiryImportAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            progressSection
            itemsSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.15))
                Image(systemName: "cloud.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Analyzing Receipts")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitleText)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            Text("LIVE")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(airyGreen)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(airyGreen.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: Progress

    private var progressSection: some View {
        VStack(alignment: .trailing, spacing: 6) {
            AiryProgressDots(processed: context.state.processed, total: context.state.total)
            Text(countText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: Items

    @ViewBuilder
    private var itemsSection: some View {
        VStack(spacing: 6) {
            if let item = context.state.lastCompletedItem {
                HStack {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(airyGreen)
                    Text(item.merchant)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Text(item.amount)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .opacity(0.65)
            }

            if context.state.processed < context.state.total {
                HStack {
                    Image(systemName: "arrow.2.circlepath")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Reading merchant…")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.12))
                        .frame(width: 40, height: 10)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: Computed text

    private var subtitleText: String {
        let t = context.state.total
        guard t > 0 else { return "Starting…" }
        let ratio = Double(context.state.processed) / Double(t)
        switch ratio {
        case ..<0.3: return "Scanning for data…"
        case ..<0.6: return "Identifying amounts…"
        case ..<0.9: return "Matching categories…"
        default:     return "Almost done…"
        }
    }

    private var countText: String {
        let p = context.state.processed
        let t = context.state.total
        if t == 0 { return "Starting…" }
        if p == t { return "\(t) processed" }
        return "\(p) of \(t) processed"
    }
}

// MARK: - Progress Dots

private struct AiryProgressDots: View {
    let processed: Int
    let total: Int

    private var displayCount: Int { min(max(total, 1), 7) }

    private var filledCount: Int {
        guard total > 0 else { return 0 }
        return Int(round(Double(processed) / Double(total) * Double(displayCount)))
    }

    private var fillFraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(processed) / CGFloat(total)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(height: 2)

                Rectangle()
                    .fill(airyGreen)
                    .frame(width: geo.size.width * fillFraction, height: 2)
                    .shadow(color: airyGreen.opacity(0.8), radius: 3)

                HStack(spacing: 0) {
                    ForEach(0..<displayCount, id: \.self) { i in
                        let isCompleted = i < filledCount - 1
                        let isActive = i == filledCount - 1 && processed < total
                        Circle()
                            .fill(isCompleted || isActive ? airyGreen : Color.white.opacity(0.2))
                            .frame(width: 6, height: 6)
                            .scaleEffect(isActive ? 1.4 : 1.0)
                            .shadow(color: isActive ? airyGreen : .clear, radius: 4)
                        if i < displayCount - 1 { Spacer() }
                    }
                }
            }
        }
        .frame(height: 10)
    }
}

// MARK: - Widget

struct AiryLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AiryImportAttributes.self) { context in
            AiryLiveActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.75))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "cloud.fill")
                        .foregroundStyle(.white)
                        .font(.title3)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text("Analyzing Receipts")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        if context.state.total > 0 {
                            Text("\(context.state.processed)/\(context.state.total)")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    AiryLiveActivityView(context: context)
                }
            } compactLeading: {
                Image(systemName: "cloud.fill")
                    .foregroundStyle(.white)
                    .font(.caption2)
            } compactTrailing: {
                Text("\(context.state.processed)/\(context.state.total)")
                    .foregroundStyle(.white)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "cloud.fill")
                    .foregroundStyle(.white)
            }
        }
    }
}
