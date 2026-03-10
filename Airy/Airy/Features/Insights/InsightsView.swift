//
//  InsightsView.swift
//  Airy
//
//  AI spending analysis: Money Mirror, comparison, yearly chart, what changed, insights, anomaly, subscription trend.
//

import SwiftUI

struct InsightsView: View {
    @State private var viewModel = InsightsViewModel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                OnboardingGradientBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        headerSection
                        aiCardSection
                        comparisonRowSection
                        yearlyChartSection
                        whatChangedSection
                        insightMirrorSections
                        anomalyCardSection
                        subscriptionTrendSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $viewModel.showPaywall) {
                PaywallView()
            }
            .task { await viewModel.load() }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("INSIGHTS")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundColor(OnboardingDesign.textTertiary)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.9), Color.white.opacity(0.2)],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 30
                        )
                    )
                    .frame(width: 48, height: 48)
                Image(systemName: "cloud.fill")
                    .font(.system(size: 24))
                    .foregroundColor(OnboardingDesign.textPrimary)
            }
            .padding(.bottom, 8)
            Text("Your Money Mirror")
                .font(.system(size: 34, weight: .light))
                .tracking(-0.5)
                .lineSpacing(4)
                .foregroundColor(OnboardingDesign.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
        .padding(.bottom, 2)
    }

    // MARK: - AI card

    private var aiCardSection: some View {
        Group {
            if viewModel.isLoading && viewModel.summary.isEmpty {
                insightsGlassPanel {
                    HStack(alignment: .center, spacing: 14) {
                        ProgressView()
                        Text("Analyzing…")
                            .font(.system(size: 14))
                            .foregroundColor(OnboardingDesign.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            } else {
                insightsGlassPanel {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20))
                            .foregroundColor(OnboardingDesign.accentBlue)
                        Text(viewModel.summary.isEmpty ? "Your spending insights will appear here." : viewModel.summary)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .foregroundColor(OnboardingDesign.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Comparison row (This Month / Last Month)

    private var comparisonRowSection: some View {
        HStack(spacing: 12) {
            comparisonTile(
                caption: "This Month",
                amount: viewModel.thisMonthSpent,
                isPrimary: true,
                deltaPercent: viewModel.deltaPercent
            )
            comparisonTile(
                caption: "Last Month",
                amount: viewModel.lastMonthSpent,
                isPrimary: false,
                deltaPercent: nil
            )
        }
    }

    private func comparisonTile(caption: String, amount: Double, isPrimary: Bool, deltaPercent: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(OnboardingDesign.textTertiary)
            Text(formatCurrency(amount))
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(isPrimary ? OnboardingDesign.textPrimary : OnboardingDesign.textTertiary)
            if let delta = deltaPercent, isPrimary {
                deltaChip(down: delta < 0, value: abs(Int(delta.rounded())))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .modifier(InsightsGlassModifier())
    }

    private func deltaChip(down: Bool, value: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: down ? "chevron.down" : "chevron.up")
                .font(.system(size: 10, weight: .bold))
            Text("\(value)%")
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundColor(down ? OnboardingDesign.accentGreen : OnboardingDesign.accentAmber)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Yearly overview chart

    private var yearlyChartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("YEARLY OVERVIEW")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundColor(OnboardingDesign.textTertiary)
            yearlyChartView
                .frame(height: 120)
                .padding(.top, 16)
            HStack {
                ForEach(Array(["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"].enumerated()), id: \.offset) { index, m in
                    Text(m)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(index == 5 ? OnboardingDesign.textPrimary : OnboardingDesign.textTertiary)
                    if index < 11 { Spacer(minLength: 0) }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
        }
        .padding(24)
        .padding(.horizontal, 4)
        .modifier(InsightsGlassModifier())
    }

    private var yearlyChartView: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pts: [(CGFloat, CGFloat)] = [
                (0, 0.67), (0.09, 0.58), (0.17, 0.75), (0.26, 0.5), (0.34, 0.33), (0.44, 0.38),
                (0.52, 0.58), (0.61, 0.42), (0.70, 0.54), (0.78, 0.62), (0.87, 0.54), (1, 0.58)
            ]
            ZStack(alignment: .topLeading) {
                Path { p in
                    guard pts.count >= 2 else { return }
                    let xs = pts.map { $0.0 * w }
                    let ys = pts.map { (1 - $0.1) * h }
                    p.move(to: CGPoint(x: xs[0], y: ys[0]))
                    for i in 1..<pts.count { p.addLine(to: CGPoint(x: xs[i], y: ys[i])) }
                    p.addLine(to: CGPoint(x: xs.last!, y: h))
                    p.addLine(to: CGPoint(x: xs[0], y: h))
                    p.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [OnboardingDesign.accentGreen.opacity(0.3), OnboardingDesign.accentGreen.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                Path { p in
                    let xs = pts.map { $0.0 * w }
                    let ys = pts.map { (1 - $0.1) * h }
                    p.move(to: CGPoint(x: xs[0], y: ys[0]))
                    for i in 1..<pts.count { p.addLine(to: CGPoint(x: xs[i], y: ys[i])) }
                }
                .stroke(OnboardingDesign.accentGreen, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(OnboardingDesign.accentGreen, lineWidth: 2))
                    .position(x: w * 0.44, y: (1 - 0.38) * h)
            }
        }
    }

    // MARK: - What Changed (horizontal pills)

    private var whatChangedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT CHANGED")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundColor(OnboardingDesign.textTertiary)
                .padding(.leading, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    deltaPill(emoji: "🍱", label: "Dining", delta: -14, up: false)
                    deltaPill(emoji: "🛍️", label: "Shopping", delta: 22, up: true)
                    deltaPill(emoji: "✈️", label: "Travel", delta: -8, up: false)
                    deltaPill(emoji: "📺", label: "Subs", delta: 5, up: true)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func deltaPill(emoji: String, label: String, delta: Int, up: Bool) -> some View {
        HStack(spacing: 8) {
            Text(emoji)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(OnboardingDesign.textPrimary)
            Text("\(up ? "+" : "")\(delta)%")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(up ? OnboardingDesign.accentAmber : OnboardingDesign.accentGreen)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.4))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Insight mirror cards (from API)

    private var insightMirrorSections: some View {
        Group {
            ForEach(Array(viewModel.insights.enumerated()), id: \.offset) { _, item in
                insightsGlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 18))
                            .foregroundColor(OnboardingDesign.accentBlue)
                        Text(item.body)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .foregroundColor(OnboardingDesign.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }
            }
            if viewModel.insights.isEmpty && !viewModel.isLoading {
                insightsGlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 18))
                            .foregroundColor(OnboardingDesign.accentBlue)
                        Text("You tend to overspend on weekends — avg $94 vs $41 weekdays.")
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .foregroundColor(OnboardingDesign.textPrimary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Anomaly card

    private var anomalyCardSection: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "triangle.exclamationmark.fill")
                .font(.system(size: 24))
                .foregroundColor(OnboardingDesign.accentAmber)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Uber Eats")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textPrimary)
                    Spacer()
                    Text("$187")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(OnboardingDesign.accentAmber)
                }
                Text("2.4× your usual spend this week")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(OnboardingDesign.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(Color.orange.opacity(0.08))
        .overlay(
            Rectangle()
                .fill(OnboardingDesign.accentAmber)
                .frame(width: 4),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    // MARK: - Subscription trend

    private var subscriptionTrendSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SUBSCRIPTION TREND")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundColor(OnboardingDesign.textTertiary)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach([0.4, 0.35, 0.45, 0.5, 0.75, 0.9], id: \.self) { h in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(h >= 0.7 ? OnboardingDesign.accentBlue : OnboardingDesign.bgBottomLeft.opacity(0.4))
                        .frame(height: 60 * h)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 60)
            .padding(.top, 20)
            Text("Up $12 since March · 2 new trials detected")
                .font(.system(size: 13))
                .foregroundColor(OnboardingDesign.textSecondary)
                .padding(.top, 16)
        }
        .padding(24)
        .padding(.horizontal, 4)
        .modifier(InsightsGlassModifier())
    }

    // MARK: - Helpers

    private func insightsGlassPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .modifier(InsightsGlassModifier())
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}

// MARK: - Glass modifier for insights

private struct InsightsGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .overlay(OnboardingDesign.glassBg.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
            )
            .shadow(color: OnboardingDesign.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
    }
}

#Preview {
    InsightsView()
}
