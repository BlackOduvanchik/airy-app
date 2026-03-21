//
//  ManageCategoriesView.swift
//  Airy
//
//  Manage Categories: move transactions between categories, create new categories/subcategories.
//

import SwiftUI

struct ManageCategoriesView: View {
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var categories: [Category] = []
    @State private var fromCategoryId: String?
    @State private var toCategoryId: String?
    @State private var showFromPicker = false
    @State private var showToPicker = false
    @State private var showNewCategory = false
    @State private var showNewSubcategory = false
    @State private var showMoveSuccess = false

    private var canMove: Bool {
        guard let from = fromCategoryId, let to = toCategoryId else { return false }
        return from != to
    }

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    moveSection
                    actionsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
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
                Text(L("manage_cat_title"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
            }
        }
        .onAppear { categories = CategoryStore.load() }
        .sheet(isPresented: $showFromPicker) {
            categoryPickerSheet(selected: $fromCategoryId, excluding: toCategoryId)
                .environment(theme)
        }
        .sheet(isPresented: $showToPicker) {
            categoryPickerSheet(selected: $toCategoryId, excluding: fromCategoryId)
                .environment(theme)
        }
        .sheet(isPresented: $showNewCategory) {
            NewCategorySheetView(onCreate: { cat in
                CategoryStore.add(cat)
                categories = CategoryStore.load()
            })
            .environment(theme)
        }
        .sheet(isPresented: $showNewSubcategory) {
            NewSubcategorySheetView(
                initialParentCategoryId: categories.first?.id ?? "",
                parentDisplayName: categories.first?.name ?? "",
                onCreate: { sub in
                    SubcategoryStore.add(sub)
                }
            )
            .environment(theme)
        }
        .sensoryFeedback(.success, trigger: showMoveSuccess)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("manage_cat_caption").uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(theme.textTertiary)
            Text(L("manage_cat_title"))
                .font(.system(size: 34, weight: .light))
                .tracking(-1)
                .foregroundColor(theme.textPrimary)
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    // MARK: - Move Section

    private var moveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("manage_cat_move_caption").uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(theme.textTertiary)

            VStack(spacing: 0) {
                categoryPickerRow(
                    label: L("manage_cat_from"),
                    categoryId: fromCategoryId,
                    showTopCorners: true
                ) {
                    showFromPicker = true
                }

                Divider()
                    .background(Color.white.opacity(theme.isDark ? 0.06 : 0.3))

                categoryPickerRow(
                    label: L("manage_cat_to"),
                    categoryId: toCategoryId,
                    showTopCorners: false
                ) {
                    showToPicker = true
                }
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

            moveButton

            if showMoveSuccess {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(theme.accentGreen)
                    Text(L("manage_cat_move_success"))
                        .font(.system(size: 13))
                        .foregroundColor(theme.accentGreen)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func categoryPickerRow(label: String, categoryId: String?, showTopCorners: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(theme.textTertiary)
                    .frame(width: 100, alignment: .leading)

                if let id = categoryId, let cat = CategoryStore.byId(id) {
                    let (bg, fg) = CategoryIconHelper.iconColors(categoryId: id)
                    Image(systemName: CategoryIconHelper.iconName(categoryId: id))
                        .font(.system(size: 14))
                        .foregroundColor(fg)
                        .frame(width: 28, height: 28)
                        .background(bg)
                        .clipShape(Circle())

                    Text(cat.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                } else {
                    Text(L("manage_cat_select"))
                        .font(.system(size: 15))
                        .foregroundColor(theme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.textTertiary)
            }
            .padding(.horizontal, 20)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var moveButton: some View {
        Button {
            guard let from = fromCategoryId, let to = toCategoryId, from != to else { return }
            LocalDataStore.shared.reassignTransactions(fromCategory: from, toCategory: to)
            withAnimation { showMoveSuccess = true }
            fromCategoryId = nil
            toCategoryId = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { showMoveSuccess = false }
            }
        } label: {
            Text(L("manage_cat_move_button"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(canMove ? theme.accentGreen : theme.accentGreen.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .shadow(color: theme.accentGreen.opacity(canMove ? 0.3 : 0), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!canMove)
        .padding(.top, 4)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            actionCard(
                icon: "plus.circle",
                title: L("manage_cat_new_cat"),
                subtitle: L("manage_cat_new_cat_desc")
            ) {
                showNewCategory = true
            }

            actionCard(
                icon: "folder.badge.plus",
                title: L("manage_cat_new_sub"),
                subtitle: L("manage_cat_new_sub_desc")
            ) {
                showNewSubcategory = true
            }
        }
        .padding(.top, 8)
    }

    private func actionCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(theme.accentGreen)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(theme.isDark ? 0.08 : 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(theme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.textTertiary)
            }
            .padding(24)
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
        .buttonStyle(.plain)
    }

    // MARK: - Category Picker Sheet

    private func categoryPickerSheet(selected: Binding<String?>, excluding: String?) -> some View {
        NavigationStack {
            ZStack {
                OnboardingGradientBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(categories) { cat in
                            if cat.id != excluding {
                                Button {
                                    selected.wrappedValue = cat.id
                                    showFromPicker = false
                                    showToPicker = false
                                } label: {
                                    HStack(spacing: 14) {
                                        let (bg, fg) = CategoryIconHelper.iconColors(categoryId: cat.id)
                                        Image(systemName: CategoryIconHelper.iconName(categoryId: cat.id))
                                            .font(.system(size: 16))
                                            .foregroundColor(fg)
                                            .frame(width: 36, height: 36)
                                            .background(bg)
                                            .clipShape(Circle())

                                        Text(cat.name)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(theme.textPrimary)

                                        Spacer()

                                        if selected.wrappedValue == cat.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(theme.accentGreen)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .frame(height: 56)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(L("manage_cat_select"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common_done")) {
                        showFromPicker = false
                        showToPicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
