//
//  ThemePickerSheetView.swift
//  Airy
//
//  Full-screen theme picker: search bar, 2-column grid of all color themes.
//

import SwiftUI

struct ThemePickerSheetView: View {
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTheme: ColorTheme
    @State private var searchText = ""

    private var filteredThemes: [ColorTheme] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return ColorTheme.allCases }
        return ColorTheme.allCases.filter { $0.displayName.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                ScrollView {
                    let columns = [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ]
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredThemes, id: \.self) { t in
                            themeCard(t)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
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
                    Text(L("themes_title"))
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(theme.textTertiary)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundColor(theme.textTertiary)
            TextField("", text: $searchText, prompt: Text(L("themes_search")).foregroundStyle(theme.textTertiary))
                .font(.system(size: 15))
                .foregroundColor(theme.textPrimary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(Color.white.opacity(theme.isDark ? 0.05 : 0.3))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(theme.glassBorder, lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    // MARK: - Theme Card

    private func themeCard(_ t: ColorTheme) -> some View {
        let isSelected = selectedTheme == t
        return Button {
            selectedTheme = t
            dismiss()
        } label: {
            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    Rectangle().fill(t.leftColor)
                    Rectangle().fill(t.rightColor)
                }
                .frame(height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(t.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(isSelected
                ? Color.white.opacity(theme.isDark ? 0.12 : 0.6)
                : Color.white.opacity(theme.isDark ? 0.05 : 0.3))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? theme.accentGreen : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
