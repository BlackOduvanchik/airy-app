//
//  TransactionReviewCard.swift
//  Airy
//
//  Transaction card for review screen. Matches design: normal, low confidence, duplicate variants.
//

import SwiftUI

struct TransactionReviewCard: View {
    let merchant: String
    let amount: Double
    let currency: String
    let date: String
    let time: String?
    let isIncome: Bool
    let categoryLabel: String
    let categoryIcon: String
    let isLowConfidence: Bool
    let confidencePercent: Double?
    let isDuplicate: Bool
    let duplicateSeenText: String?
    @Binding var rememberRule: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                if isLowConfidence {
                    warningChip
                }
                if isDuplicate, let text = duplicateSeenText {
                    duplicateBanner(text: text)
                }
                mainRow
                pillRow
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            ruleRow
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(cardBorderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: Color(red: 0.118, green: 0.176, blue: 0.141).opacity(0.06), radius: 32, x: 0, y: 8)
    }

    private var warningChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(Color(red: 0.70, green: 0.49, blue: 0.24))
            Text("LOW CONFIDENCE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(red: 0.70, green: 0.49, blue: 0.24))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(red: 0.851, green: 0.627, blue: 0.357).opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.bottom, 8)
    }

    private func duplicateBanner(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 14))
                .foregroundColor(Color(red: 0.70, green: 0.49, blue: 0.24))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Color(red: 0.70, green: 0.49, blue: 0.24))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.851, green: 0.627, blue: 0.357).opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(red: 0.851, green: 0.627, blue: 0.357).opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4]))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var mainRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(merchant)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(OnboardingDesign.textPrimary)
                Text(formattedDate)
                    .font(.system(size: 13))
                    .foregroundColor(OnboardingDesign.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                typeBadge
                Text(formatAmount)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(isIncome ? OnboardingDesign.accentGreen : OnboardingDesign.textPrimary)
            }
        }
    }

    private var typeBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: isIncome ? "arrow.down" : "arrow.up")
                .font(.system(size: 9, weight: .bold))
            Text(isIncome ? "Income" : "Expense")
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.04)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(isIncome ? Color(red: 0.29, green: 0.56, blue: 0.42).opacity(0.15) : Color(red: 0.75, green: 0.31, blue: 0.23).opacity(0.1))
        .foregroundColor(isIncome ? Color(red: 0.29, green: 0.56, blue: 0.42) : Color(red: 0.75, green: 0.31, blue: 0.23))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var pillRow: some View {
        HStack {
            categoryPill
            Spacer()
            if isLowConfidence, let pct = confidencePercent {
                confidenceBar(percent: pct)
            }
        }
    }

    private var categoryPill: some View {
        HStack(spacing: 6) {
            Image(systemName: categoryIcon)
                .font(.system(size: 14))
            Text(categoryLabel)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(OnboardingDesign.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 100)
                .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private func confidenceBar(percent: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(OnboardingDesign.accentAmber)
                    .frame(width: geo.size.width * min(1, max(0, percent / 100)), height: 4)
            }
        }
        .frame(width: 60, height: 4)
    }

    private var ruleRow: some View {
        HStack {
            Text("Remember rule for \(merchant)")
                .font(.system(size: 12))
                .foregroundColor(OnboardingDesign.textTertiary)
            Spacer()
            Toggle("", isOn: $rememberRule)
                .labelsHidden()
                .tint(OnboardingDesign.accentGreen)
        }
        .padding(.top, 12)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(height: 1),
            alignment: .top
        )
    }

    private var cardBackground: some View {
        Group {
            if isLowConfidence {
                Color(red: 0.851, green: 0.627, blue: 0.357).opacity(0.08)
            } else {
                OnboardingDesign.glassBg
            }
        }
    }

    private var cardBorderColor: Color {
        isLowConfidence ? Color(red: 0.851, green: 0.627, blue: 0.357).opacity(0.3) : OnboardingDesign.glassBorder
    }

    private var formattedDate: String {
        guard let payloadDate = date.isEmpty ? nil : date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let d = formatter.date(from: String(payloadDate.prefix(10))) else { return payloadDate }
        let cal = Calendar.current
        if cal.isDateInToday(d) {
            if let t = time, !t.isEmpty {
                return "Today, \(formatTime(t))"
            }
            return "Today"
        } else if cal.isDateInYesterday(d) {
            if let t = time, !t.isEmpty {
                return "Yesterday, \(formatTime(t))"
            }
            return "Yesterday"
        }
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: d)
    }

    private func formatTime(_ t: String) -> String {
        let parts = t.split(separator: ":")
        if parts.count >= 2 {
            let h = Int(parts[0]) ?? 0
            let m = Int(parts[1]) ?? 0
            let am = h < 12 ? "AM" : "PM"
            let h12 = h % 12 == 0 ? 12 : h % 12
            return String(format: "%d:%02d %@", h12, m, am)
        }
        return t
    }

    private var formatAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.isEmpty ? "USD" : currency
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f %@", amount, currency)
        return isIncome ? "+" + formatted : formatted
    }
}
