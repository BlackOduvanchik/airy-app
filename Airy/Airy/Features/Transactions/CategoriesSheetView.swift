//
//  CategoriesSheetView.swift
//  Airy
//
//  Full categories picker: expandable list, subcategories, colors. Edit/New actions.
//

import SwiftUI
import UniformTypeIdentifiers

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
    @State private var categoryToEdit: Category?
    @State private var selectedParentForSubcategory: Category?
    @State private var selectedCategoryId: String?
    @State private var selectedSubcategoryId: String?
    @State private var editExpandedCategoryIds: Set<String> = []
    @State private var subcategoryToEdit: Subcategory?
    @State private var subcategoryToDelete: Subcategory?
    @State private var showDeleteSubcategoryConfirm = false
    @State private var draggingCategoryId: String?

    private var filteredCategories: [Category] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return categories }
        return categories.filter {
            $0.name.lowercased().contains(q) ||
            SubcategoryStore.forParent($0.id).contains { $0.name.lowercased().contains(q) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                categoryList
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.956, green: 0.969, blue: 0.961).ignoresSafeArea())
            .onDrop(of: [UTType.text], isTargeted: nil) { _ in
                draggingCategoryId = nil
                return false
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onDismiss?()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("CATEGORIES")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(OnboardingDesign.textTertiary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showEditMode.toggle(); draggingCategoryId = nil } } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewCategory = true } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
        }
        .presentationDragIndicator(showHandle ? .visible : .hidden)
        .onAppear {
            CategoryStore.ensureDefaults()
            categories = CategoryStore.load()
            selectedCategoryId = initialCategoryId
            selectedSubcategoryId = initialSubcategoryId
            expandedCategoryIds = []
        }
        .sheet(item: $categoryToEdit) { cat in
            NewCategorySheetView(
                existing: cat,
                onCreate: { _ in },
                onUpdate: { updated in
                    CategoryStore.update(updated)
                    categories = CategoryStore.load()
                }
            )
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
                    initialParentCategoryId: parent.id,
                    parentDisplayName: parent.name,
                    onCreate: { sub in
                        SubcategoryStore.add(sub)
                        expandedCategoryIds.insert(sub.parentCategoryId)
                        editExpandedCategoryIds.insert(sub.parentCategoryId)
                        categories = CategoryStore.load()
                    }
                )
            }
        }
        .sheet(item: $subcategoryToEdit) { sub in
            let parentName = CategoryStore.byId(sub.parentCategoryId)?.name ?? ""
            NewSubcategorySheetView(
                initialParentCategoryId: sub.parentCategoryId,
                parentDisplayName: parentName,
                existing: sub,
                onUpdate: { updated in
                    if sub.name != updated.name {
                        LocalDataStore.shared.renameSubcategory(from: sub.name, to: updated.name, inCategory: sub.parentCategoryId)
                    }
                    if sub.parentCategoryId != updated.parentCategoryId {
                        // Parent changed — move subcategory to new parent
                        LocalDataStore.shared.clearSubcategory(named: sub.name, inCategory: sub.parentCategoryId)
                    }
                    SubcategoryStore.update(updated)
                    categories = CategoryStore.load()
                }
            )
        }
        .confirmationDialog(
            "Delete Subcategory",
            isPresented: $showDeleteSubcategoryConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let sub = subcategoryToDelete {
                    LocalDataStore.shared.clearSubcategory(named: sub.name, inCategory: sub.parentCategoryId)
                    SubcategoryStore.delete(id: sub.id)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        categories = CategoryStore.load()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Transactions will stay in the parent category.")
        }
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
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(categories) { cat in
                            VStack(alignment: .leading, spacing: 0) {
                                editModeCategoryRow(cat)
                                if editExpandedCategoryIds.contains(cat.id) {
                                    editModeSubcategoryList(for: cat)
                                }
                            }
                            .onDrag {
                                draggingCategoryId = cat.id
                                return NSItemProvider(object: cat.id as NSString)
                            }
                            .onDrop(of: [UTType.text], delegate: CategoryDropDelegate(
                                targetCategoryId: cat.id,
                                categories: $categories,
                                draggingCategoryId: $draggingCategoryId
                            ))
                            .opacity(draggingCategoryId == cat.id ? 0.4 : 1.0)
                            .animation(nil, value: draggingCategoryId)
                        }
                    }
                    .padding(.bottom, 40)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredCategories) { cat in
                            categoryItem(cat)
                        }
                    }
                    .padding(.bottom, 40)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func editModeCategoryRow(_ cat: Category) -> some View {
        let isAccentBlueCategory = cat.colorHex == CategoryStore.defaultColorBlue
        let subcategories = SubcategoryStore.forParent(cat.id)
        let hasSubcategories = !subcategories.isEmpty
        let isExpanded = editExpandedCategoryIds.contains(cat.id)
        return Button {
            if hasSubcategories {
                withAnimation(.easeInOut(duration: 0.3)) {
                    if isExpanded {
                        editExpandedCategoryIds.remove(cat.id)
                    } else {
                        editExpandedCategoryIds.insert(cat.id)
                    }
                }
            } else {
                categoryToEdit = cat
            }
        } label: {
            HStack(spacing: 14) {
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
                if hasSubcategories {
                    Text("\(subcategories.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(OnboardingDesign.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.6))
                        .clipShape(Capsule())
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isExpanded ? OnboardingDesign.accentBlue : OnboardingDesign.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 28, height: 28)
                }
                Button {
                    categoryToEdit = cat
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(OnboardingDesign.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
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
        .buttonStyle(.plain)
    }

    private func editModeSubcategoryList(for cat: Category) -> some View {
        let subcategories = SubcategoryStore.forParent(cat.id)
        return VStack(spacing: 6) {
            ForEach(subcategories) { sub in
                editModeSubcategoryRow(sub, parentCategory: cat)
            }
            Button {
                selectedParentForSubcategory = cat
                showNewSubcategory = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(OnboardingDesign.accentBlue.opacity(0.8))
                    Text("Add subcategory")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(OnboardingDesign.accentBlue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 48)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .transition(.opacity)
    }

    private func editModeSubcategoryRow(_ sub: Subcategory, parentCategory: Category) -> some View {
        HStack(spacing: 10) {
            Button {
                subcategoryToDelete = sub
                showDeleteSubcategoryConfirm = true
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)

            Circle()
                .fill(parentCategory.color)
                .frame(width: 8, height: 8)

            Text(sub.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(OnboardingDesign.textPrimary)

            Spacer()

            Image(systemName: "pencil")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(OnboardingDesign.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            subcategoryToEdit = sub
        }
    }

    private func deleteCategory(_ cat: Category) {
        guard categories.count > 1 else { return }
        let targetId: String? = cat.id == "other"
            ? categories.first { $0.id != "other" }?.id
            : (categories.first { $0.id == "other" }?.id ?? categories.first { $0.id != cat.id }?.id)
        guard let target = targetId else { return }
        LocalDataStore.shared.reassignTransactions(fromCategory: cat.id, toCategory: target)
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
            Button {
                if hasSubcategories {
                    _ = withAnimation(.easeInOut(duration: 0.3)) {
                        expandedCategoryIds.insert(cat.id)
                    }
                } else {
                    selectedCategoryId = cat.id
                    selectedSubcategoryId = nil
                    onSelect(cat.id, nil)
                    dismiss()
                }
            } label: {
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
            }
            .buttonStyle(.plain)

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

// MARK: - Drag & Drop

private struct CategoryDropDelegate: DropDelegate {
    let targetCategoryId: String
    @Binding var categories: [Category]
    @Binding var draggingCategoryId: String?

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingCategoryId,
              dragging != targetCategoryId,
              let fromIndex = categories.firstIndex(where: { $0.id == dragging }),
              let toIndex = categories.firstIndex(where: { $0.id == targetCategoryId })
        else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            categories.move(fromOffsets: IndexSet(integer: fromIndex),
                            toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        CategoryStore.reorder(categories)
        draggingCategoryId = nil
        return true
    }

    func dropExited(info: DropInfo) {}

    func validateDrop(info: DropInfo) -> Bool { true }
}
