//
//  AppearanceView.swift
//  Airy
//
//  Appearance settings: color theme, navigation type, income/expense colors.
//

import SwiftUI

struct AppearanceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeProvider.self) private var theme
    @State private var selectedMode: AppearanceMode = AppearanceStore.appearanceMode
    @State private var selectedLightTheme: ColorTheme = AppearanceStore.lightTheme
    @State private var selectedDarkTheme: ColorTheme = AppearanceStore.darkTheme
    @State private var selectedNavType: NavigationType = AppearanceStore.navigationType
    @State private var showLightThemeSheet = false
    @State private var showDarkThemeSheet = false
    @State private var showIncomeColorSheet = false
    @State private var showExpenseColorSheet = false
    @State private var colorVersion = 0
    @State private var selectedIncomeFormat: AmountDisplayFormat = AppearanceStore.incomeFormat
    @State private var selectedExpenseFormat: AmountDisplayFormat = AppearanceStore.expenseFormat

    private func displayedThemes(featured: [ColorTheme], selected: ColorTheme) -> [ColorTheme] {
        if featured.contains(selected) { return featured }
        return Array(featured.prefix(2)) + [selected]
    }

    var body: some View {
        ZStack {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    modeSection
                    themeSections
                    navigationSection
                    incomeSection
                    expenseSection
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
                Text(L("appearance_title"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
            }
        }
        .onChange(of: selectedNavType) { _, v in AppearanceStore.navigationType = v }
        .onChange(of: selectedMode) { _, newMode in
            withAnimation(.easeInOut(duration: 0.4)) {
                theme.setMode(newMode)
            }
        }
        .onChange(of: selectedLightTheme) { _, newTheme in
            withAnimation(.easeInOut(duration: 0.4)) {
                theme.setLightTheme(newTheme)
            }
        }
        .onChange(of: selectedDarkTheme) { _, newTheme in
            withAnimation(.easeInOut(duration: 0.4)) {
                theme.setDarkTheme(newTheme)
            }
        }
        .sheet(isPresented: $showLightThemeSheet) {
            ThemePickerSheetView(selectedTheme: $selectedLightTheme, filter: .light)
                .themed(theme)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showDarkThemeSheet) {
            ThemePickerSheetView(selectedTheme: $selectedDarkTheme, filter: .dark)
                .themed(theme)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showIncomeColorSheet, onDismiss: { colorVersion += 1 }) {
            IncomeExpenseColorPickerSheet(mode: .income)
                .themed(theme)
                .presentationDetents([.height(450)])
        }
        .sheet(isPresented: $showExpenseColorSheet, onDismiss: { colorVersion += 1 }) {
            IncomeExpenseColorPickerSheet(mode: .expense)
                .themed(theme)
                .presentationDetents([.height(450)])
        }
        .onChange(of: selectedIncomeFormat) { _, v in AppearanceStore.incomeFormat = v }
        .onChange(of: selectedExpenseFormat) { _, v in AppearanceStore.expenseFormat = v }
    }

    // MARK: - Appearance Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("appearance_mode"))
            glassPanel {
                HStack(spacing: 0) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Button {
                            selectedMode = mode
                        } label: {
                            Text(mode.displayName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(selectedMode == mode ? theme.textPrimary : theme.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    selectedMode == mode
                                        ? Color.white.opacity(theme.isDark ? 0.12 : 0.6)
                                        : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
            }
        }
    }

    // MARK: - Color Themes

    @ViewBuilder
    private var themeSections: some View {
        switch selectedMode {
        case .light:
            themeGrid(
                caption: L("appearance_color_theme"),
                featured: ColorTheme.featuredLight,
                selected: $selectedLightTheme,
                showSheet: $showLightThemeSheet
            )
        case .dark:
            themeGrid(
                caption: L("appearance_color_theme"),
                featured: ColorTheme.featuredDark,
                selected: $selectedDarkTheme,
                showSheet: $showDarkThemeSheet
            )
        case .auto:
            themeGrid(
                caption: L("appearance_light_theme"),
                featured: ColorTheme.featuredLight,
                selected: $selectedLightTheme,
                showSheet: $showLightThemeSheet
            )
            themeGrid(
                caption: L("appearance_dark_theme"),
                featured: ColorTheme.featuredDark,
                selected: $selectedDarkTheme,
                showSheet: $showDarkThemeSheet
            )
        }
    }

    private func themeGrid(caption: String, featured: [ColorTheme], selected: Binding<ColorTheme>, showSheet: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(caption)
            glassPanel {
                let columns = [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(displayedThemes(featured: featured, selected: selected.wrappedValue), id: \.self) { t in
                        themeCard(t, selected: selected)
                    }
                    moreThemesCard(showSheet: showSheet, isDarkSlot: featured.first?.isDark ?? false)
                }
                .padding(16)
            }
        }
    }

    private func themeCard(_ t: ColorTheme, selected: Binding<ColorTheme>) -> some View {
        let isSelected = selected.wrappedValue == t
        return Button {
            selected.wrappedValue = t
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

    private func moreThemesCard(showSheet: Binding<Bool>, isDarkSlot: Bool) -> some View {
        let previewThemes: [ColorTheme] = isDarkSlot
            ? [.midnightDark, .electricViolet, .berryBlast, .forestNight]
            : [.roseQuartz, .lavenderHaze, .coralReef, .tropicalTeal]
        return Button {
            showSheet.wrappedValue = true
        } label: {
            VStack(spacing: 10) {
                let cols = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]
                LazyVGrid(columns: cols, spacing: 4) {
                    ForEach(previewThemes, id: \.self) { t in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [t.leftColor, t.rightColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 28)
                    }
                }
                .frame(height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 4) {
                    Text(L("appearance_more_themes"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.textTertiary)
                }
            }
            .padding(12)
            .background(Color.white.opacity(theme.isDark ? 0.05 : 0.3))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(theme.glassBorder.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navigation Type

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("appearance_nav_type"))
            glassPanel {
                ForEach(Array(NavigationType.allCases.enumerated()), id: \.element) { index, navType in
                    radioRow(
                        navType: navType,
                        isSelected: selectedNavType == navType,
                        showBottomBorder: index < NavigationType.allCases.count - 1
                    )
                }
            }
        }
    }

    private func radioRow(navType: NavigationType, isSelected: Bool, showBottomBorder: Bool) -> some View {
        Button {
            selectedNavType = navType
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(navType.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                    Text(navType.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    Circle()
                        .stroke(isSelected ? theme.accentGreen : theme.textTertiary, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(theme.accentGreen)
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 72)
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

    // MARK: - Income Format & Color

    private var incomeSection: some View {
        let _ = colorVersion
        return VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("appearance_income_format"))
            glassPanel {
                ForEach(Array(AmountDisplayFormat.allCases.enumerated()), id: \.element) { index, fmt in
                    formatRow(
                        format: fmt,
                        sign: "+",
                        isSelected: selectedIncomeFormat == fmt,
                        showBottomBorder: true
                    ) {
                        selectedIncomeFormat = fmt
                    }
                }
                colorRow(hex: AppearanceStore.incomeColorHex, showBottomBorder: false) {
                    showIncomeColorSheet = true
                }
            }
        }
    }

    // MARK: - Expense Format & Color

    private var expenseSection: some View {
        let _ = colorVersion
        return VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("appearance_expense_format"))
            glassPanel {
                ForEach(Array(AmountDisplayFormat.allCases.enumerated()), id: \.element) { index, fmt in
                    formatRow(
                        format: fmt,
                        sign: "-",
                        isSelected: selectedExpenseFormat == fmt,
                        showBottomBorder: true
                    ) {
                        selectedExpenseFormat = fmt
                    }
                }
                colorRow(hex: AppearanceStore.expenseColorHex, showBottomBorder: false) {
                    showExpenseColorSheet = true
                }
            }
        }
    }

    private func formatRow(format: AmountDisplayFormat, sign: String, isSelected: Bool, showBottomBorder: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack {
                Text(format.example(sign: sign))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                Spacer()
                ZStack {
                    Circle()
                        .stroke(isSelected ? theme.accentGreen : theme.textTertiary, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(theme.accentGreen)
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 48)
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

    private func colorRow(hex: String, showBottomBorder: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack {
                Text(L("appearance_color"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                Spacer()
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Color.white.opacity(theme.isDark ? 0.15 : 1.0), lineWidth: 2))
                        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.textTertiary)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 64)
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
