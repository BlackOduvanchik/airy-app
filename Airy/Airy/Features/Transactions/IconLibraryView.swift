//
//  IconLibraryView.swift
//  Airy
//
//  Full-screen sheet to pick an SF Symbol: search, category tabs, sectioned grid. Used from New Category.
//

import SwiftUI

struct IconLibraryView: View {
    @Binding var selectedIcon: String
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedTab = "All"

    private let tabIds = ["All"] + SFSymbolsCatalog.categoryOrder

    private var filteredBySearch: [String: [String]] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            return SFSymbolsCatalog.byCategory
        }
        var result: [String: [String]] = [:]
        for (cat, symbols) in SFSymbolsCatalog.byCategory {
            let filtered = symbols.filter { $0.lowercased().contains(q) }
            if !filtered.isEmpty {
                result[cat] = filtered
            }
        }
        return result
    }

    private var sectionsToShow: [(name: String, symbols: [String])] {
        let data = filteredBySearch
        if selectedTab == "All" {
            return SFSymbolsCatalog.categoryOrder.compactMap { cat in
                guard let symbols = data[cat], !symbols.isEmpty else { return nil }
                return (cat, symbols)
            }
        }
        guard let symbols = data[selectedTab], !symbols.isEmpty else {
            return []
        }
        return [(selectedTab, symbols)]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchSection
                tabsSection
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 32) {
                        ForEach(sectionsToShow, id: \.name) { section in
                            sectionView(title: section.name, symbols: section.symbols)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }

                Button {
                    onDismiss()
                    dismiss()
                } label: {
                    Text("Select Icon")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(OnboardingDesign.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.956, green: 0.969, blue: 0.961).ignoresSafeArea())
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
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("ICON LIBRARY")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(OnboardingDesign.textTertiary)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var searchSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(OnboardingDesign.textTertiary)
            TextField("Search 500+ icons...", text: $searchText)
                .font(.system(size: 16))
                .foregroundColor(OnboardingDesign.textPrimary)
        }
        .padding(14)
        .padding(.leading, 14)
        .background(Color.white.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.8), lineWidth: 1)
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
                            .foregroundColor(selectedTab == tab ? .white : OnboardingDesign.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedTab == tab ? OnboardingDesign.textPrimary : Color.black.opacity(0.04))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 16)
    }

    private func sectionView(title: String, symbols: [String]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.1)
                .foregroundColor(OnboardingDesign.textTertiary)
                .padding(.leading, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                ForEach(symbols, id: \.self) { symbol in
                    iconCard(symbol: symbol)
                }
            }
        }
    }

    private func iconCard(symbol: String) -> some View {
        let isSelected = selectedIcon == symbol
        return Button {
            selectedIcon = symbol
        } label: {
            Group {
                if SFSymbolsCatalog.isLetter(symbol) {
                    Text(SFSymbolsCatalog.letterValue(symbol))
                        .font(.system(size: 22, weight: .bold))
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 24, weight: .medium))
                }
            }
            .foregroundColor(isSelected ? OnboardingDesign.accentGreen : OnboardingDesign.textPrimary)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.5))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? OnboardingDesign.accentGreen : Color.white.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: isSelected ? OnboardingDesign.accentGreen.opacity(0.1) : .clear, radius: 16, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    IconLibraryView(selectedIcon: .constant("heart.fill"), onDismiss: {})
}
