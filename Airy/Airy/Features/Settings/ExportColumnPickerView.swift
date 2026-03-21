//
//  ExportColumnPickerView.swift
//  Airy
//
//  Toggle exportable columns on/off for CSV export.
//

import SwiftUI

struct ExportColumnPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeProvider.self) private var theme
    @Bindable var viewModel: ExportDataViewModel

    var body: some View {
        ZStack {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    glassPanel {
                        ForEach(Array(ExportDataViewModel.allColumns.enumerated()), id: \.element.id) { index, col in
                            let isOn = viewModel.selectedColumnIds.contains(col.id)
                            let isLast = index == ExportDataViewModel.allColumns.count - 1
                            toggleRow(col: col, isOn: isOn, showBottomBorder: !isLast)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            ToolbarItem(placement: .principal) {
                Text(L("columns_title"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
            }
        }
    }

    // MARK: - Row

    private func toggleRow(col: ExportColumn, isOn: Bool, showBottomBorder: Bool) -> some View {
        Button {
            viewModel.toggleColumn(col.id)
        } label: {
            HStack {
                Text(col.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isOn ? theme.accentGreen : theme.textTertiary)
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
            .contentShape(Rectangle())
            .overlay(
                Group {
                    if showBottomBorder {
                        Rectangle()
                            .fill(Color.white.opacity(theme.isDark ? 0.06 : 0.3))
                            .frame(height: 1)
                    }
                },
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Glass Panel

    private func glassPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(theme.isDark ? AnyShapeStyle(theme.glassBg) : AnyShapeStyle(.ultraThinMaterial))
        .overlay(theme.isDark ? nil : theme.glassBg.opacity(0.5).allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(theme.glassBorder, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: theme.isDark ? Color.black.opacity(0.4) : theme.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
    }
}
