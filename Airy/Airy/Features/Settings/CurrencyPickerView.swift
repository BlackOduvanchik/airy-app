//
//  CurrencyPickerView.swift
//  Airy
//
//  Full-screen currency picker: favorites on top, all currencies alphabetical below.
//

import SwiftUI

struct CurrencyPickerView: View {
    @Binding var baseCurrency: String
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeProvider.self) private var theme

    @State private var favorites: Set<String> = Self.loadFavorites()
    @State private var showInfoAlert = false
    @State private var searchText = ""
    @State private var debouncedSearch = ""

    // MARK: - Currency catalog

    private static let allCurrencies: [(code: String, name: String)] = [
        ("AED", "UAE Dirham"), ("ARS", "Argentine Peso"), ("AUD", "Australian Dollar"),
        ("BRL", "Brazilian Real"), ("CAD", "Canadian Dollar"), ("CHF", "Swiss Franc"),
        ("CNY", "Chinese Yuan"), ("CZK", "Czech Koruna"), ("DKK", "Danish Krone"),
        ("EUR", "Euro"), ("GBP", "British Pound"), ("HKD", "Hong Kong Dollar"),
        ("HUF", "Hungarian Forint"), ("IDR", "Indonesian Rupiah"), ("ILS", "Israeli Shekel"),
        ("INR", "Indian Rupee"), ("JPY", "Japanese Yen"), ("KRW", "South Korean Won"),
        ("MXN", "Mexican Peso"), ("MYR", "Malaysian Ringgit"), ("NOK", "Norwegian Krone"),
        ("NZD", "New Zealand Dollar"), ("PHP", "Philippine Peso"), ("PLN", "Polish Zloty"),
        ("RON", "Romanian Leu"), ("RUB", "Russian Ruble"), ("SAR", "Saudi Riyal"),
        ("SEK", "Swedish Krona"), ("SGD", "Singapore Dollar"), ("THB", "Thai Baht"),
        ("TRY", "Turkish Lira"), ("TWD", "Taiwan Dollar"), ("UAH", "Ukrainian Hryvnia"),
        ("USD", "US Dollar"), ("VND", "Vietnamese Dong"), ("ZAR", "South African Rand")
    ]

    // MARK: - Favorites persistence

    private static let favKey = "airy_favoriteCurrencies"

    private static func loadFavorites() -> Set<String> {
        guard let arr = UserDefaults.standard.array(forKey: favKey) as? [String] else {
            return [BaseCurrencyStore.baseCurrency]
        }
        var set = Set(arr)
        set.insert(BaseCurrencyStore.baseCurrency)
        return set
    }

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favorites), forKey: Self.favKey)
    }

    // MARK: - Computed lists

    private func matches(_ currency: (code: String, name: String)) -> Bool {
        guard !debouncedSearch.isEmpty else { return true }
        let q = debouncedSearch.lowercased()
        return currency.code.lowercased().contains(q) || currency.name.lowercased().contains(q)
    }

    private var favoriteCurrencies: [(code: String, name: String)] {
        Self.allCurrencies.filter { favorites.contains($0.code) && matches($0) }
    }

    private var filteredAllCurrencies: [(code: String, name: String)] {
        Self.allCurrencies.filter { matches($0) }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    searchSection
                    if !favoriteCurrencies.isEmpty {
                        favoritesSection
                    }
                    allCurrenciesSection
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
                Text(L("currency_title"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showInfoAlert = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .alert(L("currency_exchange_title"), isPresented: $showInfoAlert) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(L("currency_exchange_message"))
        }
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(300))
            debouncedSearch = searchText
        }
    }

    // MARK: - Search

    private var searchSection: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundColor(theme.textTertiary)
                .padding(.leading, 16)
                .accessibilityHidden(true)
            TextField("", text: $searchText, prompt: Text(L("currency_search")).foregroundStyle(theme.textTertiary))
                .font(.system(size: 15))
                .foregroundColor(theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.leading, 44)
                .padding(.vertical, 14)
                .background(Color.white.opacity(theme.isDark ? 0.05 : 0.3))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        }
    }

    // MARK: - Sections

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("currency_favorites"))
            glassPanel {
                ForEach(Array(favoriteCurrencies.enumerated()), id: \.element.code) { index, currency in
                    currencyRow(
                        code: currency.code,
                        name: currency.name,
                        isSelected: currency.code == baseCurrency,
                        isFavorite: true,
                        showBottomBorder: index < favoriteCurrencies.count - 1
                    )
                }
            }
        }
    }

    private var allCurrenciesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("currency_all"))
            glassPanel {
                ForEach(Array(filteredAllCurrencies.enumerated()), id: \.element.code) { index, currency in
                    currencyRow(
                        code: currency.code,
                        name: currency.name,
                        isSelected: currency.code == baseCurrency,
                        isFavorite: favorites.contains(currency.code),
                        showBottomBorder: index < filteredAllCurrencies.count - 1
                    )
                }
            }
        }
    }

    // MARK: - Row

    private func currencyRow(code: String, name: String, isSelected: Bool, isFavorite: Bool, showBottomBorder: Bool) -> some View {
        HStack(spacing: 12) {
            // Heart button
            Button {
                if isFavorite && code != baseCurrency {
                    favorites.remove(code)
                } else {
                    favorites.insert(code)
                }
                saveFavorites()
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 16))
                    .foregroundColor(isFavorite ? theme.accentGreen : theme.textTertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Currency info (tappable to select)
            Button {
                baseCurrency = code
                BaseCurrencyStore.baseCurrency = code
                favorites.insert(code)
                saveFavorites()
            } label: {
                HStack(spacing: 8) {
                    Text(code)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                    Text(name)
                        .font(.system(size: 13))
                        .foregroundColor(theme.textSecondary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(theme.accentGreen)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
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

    // MARK: - Helpers

    private func sectionCaption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.5)
            .foregroundColor(theme.textTertiary)
            .padding(.bottom, 8)
    }

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
