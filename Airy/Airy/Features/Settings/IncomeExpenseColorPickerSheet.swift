//
//  IncomeExpenseColorPickerSheet.swift
//  Airy
//
//  Bottom sheet for picking Income or Expense display color.
//

import SwiftUI

struct IncomeExpenseColorPickerSheet: View {
    enum Mode { case income, expense }

    @Environment(ThemeProvider.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var selectedHex: String
    let mode: Mode

    private let palette: [String] = [
        // Pastel
        "#BFE8D2", "#C9D8C5", "#BFE7E3", "#C7DBF7", "#D1D7FA", "#DCCEF8",
        "#F6D1DC", "#F8D6BF", "#F6E7B8", "#EBC9B8", "#D8D2E8", "#E7D1C8",
        // Vivid
        "#34C27A", "#4D8F63", "#22B8B0", "#4A90E2", "#6C7CF0", "#9B6DF2",
        "#EC6FA9", "#F28A6A", "#E9B949", "#D9825B", "#B85FD6", "#D97C8E",
        // Bold
        "#111111", "#FF3B30", "#2F80FF", "#7ED957", "#FF4FA3", "#FF7A1A",
    ]

    init(mode: Mode) {
        self.mode = mode
        let hex = mode == .income ? AppearanceStore.incomeColorHex : AppearanceStore.expenseColorHex
        _selectedHex = State(initialValue: hex)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                paletteSection(
                    title: mode == .income ? L("colorpicker_income") : L("colorpicker_expense"),
                    selectedHex: $selectedHex
                )
                .padding(.top, 8)

                Spacer()

                applyButton
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    theme.bgTop.ignoresSafeArea()
                    Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(L("colorpicker_title"))
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(theme.textTertiary)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Palette Section

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    private func paletteSection(title: String, selectedHex: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(theme.textTertiary)

            LazyVGrid(columns: gridColumns, spacing: 14) {
                ForEach(palette, id: \.self) { hex in
                    colorSwatch(hex: hex, isSelected: selectedHex.wrappedValue.uppercased() == hex.uppercased()) {
                        selectedHex.wrappedValue = hex
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Swatch

    private func colorSwatch(hex: String, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        let color = Color(hex: hex) ?? .gray
        return Button(action: onTap) {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(Color.white.opacity(theme.isDark ? 0.15 : 1), lineWidth: 2))
                .shadow(color: color.opacity(0.3), radius: 4, x: 0, y: 2)
                .scaleEffect(isSelected ? 1.2 : 1.0)
                .overlay(
                    isSelected ?
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                        : nil
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Apply

    private var applyButton: some View {
        Button {
            switch mode {
            case .income:
                AppearanceStore.incomeColorHex = selectedHex
            case .expense:
                AppearanceStore.expenseColorHex = selectedHex
            }
            theme.refreshIncomeExpenseColors()
            dismiss()
        } label: {
            Text(L("colorpicker_apply"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(theme.accentGreen)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: theme.accentGreen.opacity(0.3), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}
