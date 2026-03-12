//
//  CategoriesSheetView.swift
//  Airy
//
//  Full categories picker: expandable list, subcategories, colors. Edit/New actions.
//

import SwiftUI

struct CategoriesSheetView: View {
    /// Selected: (categoryId, subcategoryId?). subcategoryId nil = category itself selected.
    var onSelect: (String, String?) -> Void
    var onDismiss: (() -> Void)?
    var initialCategoryId: String?
    var initialSubcategoryId: String?
    /// When false, hides the top handle (e.g. when presented as sheet over another sheet).
    var showHandle: Bool = true
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var expandedCategoryIds: Set<String> = []
    @State private var categories: [Category] = CategoryStore.load()
    @State private var showNewCategory = false
    @State private var showNewSubcategory = false
    @State private var showEditMode = false
    @State private var selectedParentForSubcategory: Category?
    @State private var selectedCategoryId: String?
    @State private var selectedSubcategoryId: String?

    private var filteredCategories: [Category] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return categories }
        return categories.filter {
            $0.name.lowercased().contains(q) ||
            SubcategoryStore.forParent($0.id).contains { $0.name.lowercased().contains(q) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showHandle {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 36, height: 5)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
            } else {
                Spacer().frame(height: 24)
            }
            header
            searchBar
            categoryList
        }
        .padding(.horizontal, 20)
        .padding(.top, showHandle ? 0 : 8)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 40,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 40
                )
                .fill(Color(red: 0.956, green: 0.969, blue: 0.961))
            )
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 40,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 40
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 40,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 40
                )
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: Color(red: 0.118, green: 0.176, blue: 0.141).opacity(0.08), radius: 24, x: 0, y: -4)
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            CategoryStore.ensureDefaults()
            categories = CategoryStore.load()
            selectedCategoryId = initialCategoryId
            selectedSubcategoryId = initialSubcategoryId
            expandedCategoryIds = []
        }
        .sheet(isPresented: $showNewCategory) {
            NewCategorySheetView(
                onCreate: { cat in
                    CategoryStore.add(cat)
                    categories = CategoryStore.load()
                },
                onCreateSubcategory: { sub in
                    SubcategoryStore.add(sub)
                    if let parent = CategoryStore.byId(sub.parentCategoryId) {
                        expandedCategoryIds.insert(parent.id)
                    }
                    categories = CategoryStore.load()
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showNewSubcategory) {
            if let parent = selectedParentForSubcategory {
                NewSubcategorySheetView(
                    parentCategoryId: parent.id,
                    parentDisplayName: parent.name
                ) { sub in
                    SubcategoryStore.add(sub)
                    expandedCategoryIds.insert(parent.id)
                    categories = CategoryStore.load()
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Categories")
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(OnboardingDesign.textPrimary)
            Spacer()
            HStack(spacing: 8) {
                Button {
                    showEditMode.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .bold))
                        Text("Edit")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(OnboardingDesign.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.02), lineWidth: 1))
                }
                Button {
                    showNewCategory = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                        Text("New")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.122, green: 0.157, blue: 0.137))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(.bottom, 20)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundColor(OnboardingDesign.textTertiary)
            TextField("Search categories...", text: $searchText)
                .font(.system(size: 15))
                .foregroundColor(OnboardingDesign.textPrimary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.clear, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 8, x: 0, y: 2)
        .padding(.bottom, 24)
    }

    private var categoryList: some View {
        Group {
            if showEditMode {
                List {
                    ForEach(categories) { cat in
                        editModeCategoryRow(cat)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if cat.id != "other" {
                                    Button(role: .destructive) {
                                        deleteCategory(cat)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                    .onMove { from, to in
                        categories.move(fromOffsets: from, toOffset: to)
                        CategoryStore.reorder(categories)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredCategories) { cat in
                            categoryItem(cat)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func editModeCategoryRow(_ cat: Category) -> some View {
        let isAccentBlueCategory = cat.colorHex == CategoryStore.defaultColorBlue
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isAccentBlueCategory ? OnboardingDesign.accentBlue.opacity(0.08) : Self.iconBoxBg)
                    .frame(width: 40, height: 40)
                Image(systemName: iconName(for: cat))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(cat.color)
            }
            Text(cat.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(OnboardingDesign.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        )
    }

    private func deleteCategory(_ cat: Category) {
        guard cat.id != "other" else { return }
        LocalDataStore.shared.reassignTransactionsToOther(fromCategory: cat.id)
        CategoryStore.delete(id: cat.id)
        categories = CategoryStore.load()
    }

    private static let iconBoxBg = Color(red: 0.956, green: 0.969, blue: 0.961)

    private func categoryItem(_ cat: Category) -> some View {
        let subcategories = SubcategoryStore.forParent(cat.id)
        let hasSubcategories = !subcategories.isEmpty
        let isExpanded = expandedCategoryIds.contains(cat.id)
        let isCategorySelected = selectedCategoryId == cat.id && selectedSubcategoryId == nil
        let isAccentBlueCategory = cat.colorHex == CategoryStore.defaultColorBlue

        return VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isAccentBlueCategory ? OnboardingDesign.accentBlue.opacity(0.08) : Self.iconBoxBg)
                            .frame(width: 48, height: 48)
                        Image(systemName: iconName(for: cat))
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(cat.color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cat.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(OnboardingDesign.textPrimary)
                        if hasSubcategories {
                            Text(subcategories.map { $0.name }.joined(separator: ", "))
                                .font(.system(size: 12))
                                .foregroundColor(OnboardingDesign.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if isCategorySelected && !hasSubcategories {
                        ZStack {
                            Circle()
                                .fill(OnboardingDesign.accentGreen)
                                .frame(width: 24, height: 24)
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.trailing, 4)
                    }
                    if hasSubcategories {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(isExpanded ? OnboardingDesign.accentBlue : cat.color)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let _ = withAnimation(.easeInOut(duration: 0.3)) {
                                    if isExpanded {
                                        expandedCategoryIds.remove(cat.id)
                                    } else {
                                        expandedCategoryIds.insert(cat.id)
                                    }
                                }
                            }
                    }
                }
                .padding(4)
                .contentShape(Rectangle())
                .onTapGesture {
                    if hasSubcategories {
                        let _ = withAnimation(.easeInOut(duration: 0.3)) {
                            expandedCategoryIds.insert(cat.id)
                        }
                    } else {
                        selectedCategoryId = cat.id
                        selectedSubcategoryId = nil
                        onSelect(cat.id, nil)
                        dismiss()
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(isCategorySelected && !hasSubcategories ? Color.white : Color.white.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        isCategorySelected && !hasSubcategories ? OnboardingDesign.accentGreen :
                        isExpanded ? OnboardingDesign.accentBlue.opacity(0.3) : Color.white.opacity(0.6),
                        lineWidth: 1
                    )
            )

            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(subcategories) { sub in
                        let isSubSelected = selectedCategoryId == cat.id && selectedSubcategoryId == sub.id
                        HStack(spacing: 10) {
                            Circle()
                                .fill(OnboardingDesign.accentBlue)
                                .frame(width: 8, height: 8)
                            Text(sub.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(OnboardingDesign.accentBlue)
                            Spacer()
                            if isSubSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(OnboardingDesign.accentBlue)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isSubSelected ? Color.white : Color.white.opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isSubSelected ? OnboardingDesign.accentBlue.opacity(0.2) : Color.clear, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedCategoryId = cat.id
                            selectedSubcategoryId = sub.id
                            onSelect(cat.id, sub.id)
                            dismiss()
                        }
                    }
                    Button {
                        selectedParentForSubcategory = cat
                        showNewSubcategory = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(OnboardingDesign.accentBlue.opacity(0.8))
                            Text("Add subcategory")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(OnboardingDesign.accentBlue)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 62)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
        }
    }

    private func iconName(for cat: Category) -> String {
        CategoryIconHelper.iconName(categoryId: cat.id)
    }
}
