//
//  IconLibraryView.swift
//  Airy
//
//  Full-screen sheet to pick an SF Symbol: search, category tabs, sectioned grid. Used from New Category.
//

import SwiftUI

// MARK: - Equatable grid wrapper — lets SwiftUI skip the entire 360-card tree in one == check

private struct IconGrid: View, Equatable {
    let sectionNames: [String]
    let sectionSymbols: [[String]]
    let selectedIcon: String
    let isDark: Bool
    let accentGreen: Color
    let textPrimary: Color
    let textTertiary: Color
    let columns: [GridItem]
    let onSelect: (String) -> Void

    static func == (lhs: IconGrid, rhs: IconGrid) -> Bool {
        lhs.sectionNames == rhs.sectionNames &&
        lhs.sectionSymbols == rhs.sectionSymbols &&
        lhs.selectedIcon == rhs.selectedIcon &&
        lhs.isDark == rhs.isDark &&
        lhs.accentGreen == rhs.accentGreen &&
        lhs.textPrimary == rhs.textPrimary &&
        lhs.textTertiary == rhs.textTertiary
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(sectionNames.enumerated()), id: \.element) { idx, name in
                Section {
                    ForEach(sectionSymbols[idx], id: \.self) { symbol in
                        IconCard(
                            symbol: symbol,
                            isSelected: selectedIcon == symbol,
                            isDark: isDark,
                            accentGreen: accentGreen,
                            textPrimary: textPrimary,
                            onSelect: onSelect
                        )
                    }
                } header: {
                    Text(name.uppercased())
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(0.1)
                        .foregroundColor(textTertiary)
                        .padding(.leading, 4)
                        .padding(.top, 20)
                        .padding(.bottom, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - Single icon card — Equatable so body is skipped when nothing changed

private struct IconCard: View, Equatable {
    let symbol: String
    let isSelected: Bool
    let isDark: Bool
    let accentGreen: Color
    let textPrimary: Color
    let onSelect: (String) -> Void

    static func == (lhs: IconCard, rhs: IconCard) -> Bool {
        lhs.symbol == rhs.symbol &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isDark == rhs.isDark &&
        lhs.accentGreen == rhs.accentGreen &&
        lhs.textPrimary == rhs.textPrimary
    }

    var body: some View {
        Button { onSelect(symbol) } label: {
            Group {
                if SFSymbolsCatalog.isLetter(symbol) {
                    Text(SFSymbolsCatalog.letterValue(symbol))
                        .font(.system(size: 22, weight: .bold))
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 24, weight: .medium))
                }
            }
            .foregroundColor(isSelected ? accentGreen : textPrimary)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected
                          ? Color.white.opacity(isDark ? 0.15 : 1)
                          : Color.white.opacity(isDark ? 0.06 : 0.5))
                    .stroke(isSelected
                            ? accentGreen
                            : Color.white.opacity(isDark ? 0.10 : 0.8),
                            lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Main view

struct IconLibraryView: View {
    @Environment(ThemeProvider.self) private var theme
    @Binding var selectedIcon: String
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var selectedTab = "All"
    @State private var sectionNames: [String] = []
    @State private var sectionSymbols: [[String]] = []

    private let tabIds = ["All"] + SFSymbolsCatalog.categoryOrder
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    private func refilter() {
        let q = debouncedSearch.trimmingCharacters(in: .whitespaces).lowercased()
        let data: [String: [String]]
        if q.isEmpty {
            data = SFSymbolsCatalog.byCategory
        } else {
            var result: [String: [String]] = [:]
            for (cat, symbols) in SFSymbolsCatalog.byCategory {
                let filtered = symbols.filter {
                    $0.lowercased().contains(q) ||
                    (SFSymbolsCatalog.searchKeywordsLowercased[$0]?.contains(q) == true)
                }
                if !filtered.isEmpty {
                    result[cat] = filtered
                }
            }
            data = result
        }
        var names: [String] = []
        var symbols: [[String]] = []
        if selectedTab == "All" {
            for cat in SFSymbolsCatalog.categoryOrder {
                if let s = data[cat], !s.isEmpty {
                    names.append(cat)
                    symbols.append(s)
                }
            }
        } else if let s = data[selectedTab], !s.isEmpty {
            names = [selectedTab]
            symbols = [s]
        }
        sectionNames = names
        sectionSymbols = symbols
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchSection
                tabsSection
                ScrollView(.vertical, showsIndicators: false) {
                    IconGrid(
                        sectionNames: sectionNames,
                        sectionSymbols: sectionSymbols,
                        selectedIcon: selectedIcon,
                        isDark: theme.isDark,
                        accentGreen: theme.accentGreen,
                        textPrimary: theme.textPrimary,
                        textTertiary: theme.textTertiary,
                        columns: columns,
                        onSelect: { selectedIcon = $0 }
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)

                Button {
                    onDismiss()
                    dismiss()
                } label: {
                    Text(L("iconlib_select"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(theme.isDark ? Color.white.opacity(0.15) : theme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { OnboardingGradientBackground().ignoresSafeArea() }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onDismiss()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(L("iconlib_title"))
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(theme.textTertiary)
                }
            }
        }
        .onAppear { refilter() }
        .onChange(of: debouncedSearch) { refilter() }
        .onChange(of: selectedTab) { refilter() }
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(300))
            debouncedSearch = searchText
        }
    }

    private var searchSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(theme.textTertiary)
            TextField("", text: $searchText, prompt: Text(L("iconlib_search")).foregroundStyle(theme.textTertiary))
                .font(.system(size: 16))
                .foregroundColor(theme.textPrimary)
        }
        .padding(14)
        .padding(.leading, 14)
        .background(Color.white.opacity(theme.isDark ? 0.08 : 0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(theme.isDark ? 0.12 : 0.8), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.02), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var tabsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabIds, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(selectedTab == tab ? .white : theme.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedTab == tab ? theme.accentGreen : (theme.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 16)
    }
}

#Preview {
    IconLibraryView(selectedIcon: .constant("heart.fill"), onDismiss: {})
}
