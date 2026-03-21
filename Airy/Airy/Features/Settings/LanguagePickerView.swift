//
//  LanguagePickerView.swift
//  Airy
//
//  In-app language picker — glass-morphism style matching CurrencyPickerView.
//

import SwiftUI

struct LanguagePickerView: View {
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    glassPanel {
                        ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element.id) { index, lang in
                            languageRow(
                                language: lang,
                                isSelected: lang == LanguageManager.shared.current,
                                showBottomBorder: index < AppLanguage.allCases.count - 1
                            )
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
                Text(L("language_title"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
            }
        }
    }

    // MARK: - Row

    private func languageRow(language: AppLanguage, isSelected: Bool, showBottomBorder: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                LanguageManager.shared.set(language)
            }
        } label: {
            HStack(spacing: 14) {
                Text(language.flag)
                    .font(.system(size: 28))
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(language.nativeName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                    Text(language.englishName)
                        .font(.system(size: 12))
                        .foregroundColor(theme.textTertiary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.accentGreen)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
