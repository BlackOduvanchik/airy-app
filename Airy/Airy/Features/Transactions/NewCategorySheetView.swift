//
//  NewCategorySheetView.swift
//  Airy
//
//  Sheet for creating a new category or subcategory. Matches design spec.
//

import SwiftUI

private let designColors: [String] = [
    // Pastel
    "#BFE8D2", "#C9D8C5", "#BFE7E3", "#C7DBF7", "#D1D7FA", "#DCCEF8",
    "#F6D1DC", "#F8D6BF", "#F6E7B8", "#EBC9B8", "#D8D2E8", "#E7D1C8",
    // Vivid
    "#34C27A", "#4D8F63", "#22B8B0", "#4A90E2", "#6C7CF0", "#9B6DF2",
    "#EC6FA9", "#F28A6A", "#E9B949", "#D9825B", "#B85FD6", "#D97C8E",
    // Bold
    "#111111", "#FF3B30", "#2F80FF", "#7ED957", "#FF4FA3", "#FF7A1A",
]

struct NewCategorySheetView: View {
    @Environment(ThemeProvider.self) private var theme
    var existing: Category? = nil
    var onCreate: (Category) -> Void
    var onCreateSubcategory: ((Subcategory) -> Void)?
    var onUpdate: ((Category) -> Void)?
    var onDelete: ((Category) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var shortDescription = ""
    @State private var selectedIcon = "creditcard.fill"
    @State private var selectedColorHex = "#34C27A"
    @State private var parentCategoryId: String? = nil
    @State private var showParentPicker = false
    @State private var showIconLibrary = false
    @State private var showDeleteConfirm = false
    @State private var quickPickIcons: [String] = []
    @State private var didAppear = false

    private var parentCategory: Category? {
        guard let id = parentCategoryId else { return nil }
        return CategoryStore.byId(id)
    }

    private var isSubcategoryMode: Bool { parentCategoryId != nil }
    private var isEditMode: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        CategoryPreviewCard(
                            name: name,
                            shortDescription: shortDescription,
                            selectedIcon: selectedIcon,
                            selectedColorHex: selectedColorHex
                        )
                        .padding(.bottom, 24)

                        sectionLabel(L("newcat_name"))
                        inputField(placeholder: L("newcat_name_placeholder"), text: $name)

                        sectionLabel(L("newcat_description"))
                        inputField(placeholder: L("newcat_desc_placeholder"), text: $shortDescription)

                        sectionLabel(L("newcat_icon"))
                        CategoryIconGrid(
                            selectedIcon: $selectedIcon,
                            quickPickIcons: quickPickIcons,
                            onShowLibrary: { showIconLibrary = true }
                        )

                        if !isEditMode {
                            sectionLabel(L("newcat_parent"))
                            parentSelectButton
                        }

                        sectionLabel(L("newcat_color"))
                        CategoryColorRow(selectedColorHex: $selectedColorHex)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                if isEditMode {
                    deleteCategoryButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
                createButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { OnboardingGradientBackground().ignoresSafeArea() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(isEditMode ? L("newcat_edit") : L("newcat_new"))
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(theme.textTertiary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .alert(L("newcat_delete_title"), isPresented: $showDeleteConfirm) {
            Button(L("newcat_delete_confirm"), role: .destructive) {
                guard let cat = existing else { return }
                onDelete?(cat)
                dismiss()
            }
            Button(L("cancel"), role: .cancel) {}
        } message: {
            Text(L("newcat_delete_message"))
        }
        .sheet(isPresented: $showParentPicker) {
            parentPickerSheet
                .environment(theme)
        }
        .sheet(isPresented: $showIconLibrary) {
            IconLibraryView(selectedIcon: $selectedIcon) {
                showIconLibrary = false
            }
            .environment(theme)
        }
        .onAppear {
            guard !didAppear else { return }
            didAppear = true
            if quickPickIcons.isEmpty {
                quickPickIcons = Array(SFSymbolsCatalog.allSymbols.filter { !SFSymbolsCatalog.isLetter($0) }.shuffled().prefix(5))
            }
            if let e = existing {
                name = e.name
                let icon = e.iconName ?? defaultIconForCategoryId(e.id)
                selectedIcon = SFSymbolsCatalog.contains(icon) ? icon : "tag.fill"
                selectedColorHex = e.colorHex
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(theme.textTertiary)
            .tracking(0.5)
            .padding(.leading, 4)
            .padding(.bottom, 10)
    }

    private func inputField(placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(theme.textTertiary))
            .font(.system(size: 15))
            .foregroundColor(theme.textPrimary)
            .padding(14)
            .padding(.horizontal, 2)
            .background(Color.white.opacity(theme.isDark ? 0.08 : 0.6))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(theme.isDark ? 0.12 : 0.8), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.bottom, 22)
    }

    private var parentSelectButton: some View {
        Button {
            showParentPicker = true
        } label: {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(parentCategory?.color.opacity(0.12) ?? Color.black.opacity(0.05))
                        .frame(width: 30, height: 30)
                    Image(systemName: parentCategory.map { iconForCategory($0) } ?? "folder")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(parentCategory?.color ?? theme.textTertiary)
                }
                Text(parentCategory?.name ?? L("newcat_parent_none"))
                    .font(.system(size: 15, weight: parentCategory != nil ? .medium : .regular))
                    .foregroundColor(parentCategory != nil ? theme.textPrimary : theme.textTertiary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(theme.textTertiary)
            }
            .padding(13)
            .padding(.horizontal, 3)
            .background(Color.white.opacity(theme.isDark ? 0.06 : 0.4))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(theme.isDark ? 0.10 : 0.7), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 22)
    }

    private func iconForCategory(_ cat: Category) -> String {
        cat.iconName ?? defaultIconForCategoryId(cat.id)
    }

    private func defaultIconForCategoryId(_ id: String) -> String {
        switch id {
        case "food": return "cart.fill"
        case "transport": return "car.fill"
        case "housing", "bills": return "house.fill"
        case "health": return "heart.fill"
        case "shopping": return "bag.fill"
        default: return "tag.fill"
        }
    }

    private var parentPickerSheet: some View {
        ParentCategoryPickerSheet(selectedParentId: $parentCategoryId)
    }

    private var createButton: some View {
        Button {
            submit()
        } label: {
            Text(isEditMode ? L("newcat_save") : L("newcat_create"))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(theme.isDark ? Color.white.opacity(0.15) : theme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
    }

    private var deleteCategoryButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .medium))
                Text(L("newcat_delete"))
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(theme.textDanger)
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(theme.textDanger.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(theme.textDanger.opacity(0.15), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = existing {
            let updated = Category(id: existing.id, name: trimmed, colorHex: selectedColorHex, iconName: selectedIcon)
            onUpdate?(updated)
        } else if let parentId = parentCategoryId, let _ = CategoryStore.byId(parentId) {
            let sub = Subcategory(name: trimmed, parentCategoryId: parentId)
            onCreateSubcategory?(sub)
        } else {
            let cat = Category(name: trimmed, colorHex: selectedColorHex, iconName: selectedIcon)
            onCreate(cat)
        }
        dismiss()
    }
}

// MARK: - Extracted subviews (prevent re-render on text/focus changes)

/// Preview card — only re-renders when its inputs change, not on focusedField changes.
private struct CategoryPreviewCard: View {
    @Environment(ThemeProvider.self) private var theme
    let name: String
    let shortDescription: String
    let selectedIcon: String
    let selectedColorHex: String

    var body: some View {
        let displayName = name.isEmpty ? "Category name" : name
        let displaySub = shortDescription.isEmpty ? "Short description" : shortDescription
        let color = Color(hex: selectedColorHex) ?? theme.accentGreen

        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(color.opacity(0.1))
                    .frame(width: 44, height: 44)
                if SFSymbolsCatalog.isLetter(selectedIcon) {
                    Text(SFSymbolsCatalog.letterValue(selectedIcon))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(color)
                } else {
                    Image(systemName: selectedIcon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(color)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                Text(displaySub)
                    .font(.system(size: 12))
                    .foregroundColor(theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Circle()
                .fill(theme.bgTop.opacity(0.5))
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(theme.glassBorder, lineWidth: 1.5))
        }
        .padding(14)
        .padding(.horizontal, 2)
        .background(Color.white.opacity(theme.isDark ? 0.08 : 1))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.accentGreen.opacity(0.2), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.118, green: 0.176, blue: 0.141).opacity(0.04), radius: 16, x: 0, y: 4)
    }
}

/// Icon grid — only re-renders when selectedIcon or quickPickIcons change, not on text/focus changes.
private struct CategoryIconGrid: View {
    @Environment(ThemeProvider.self) private var theme
    @Binding var selectedIcon: String
    let quickPickIcons: [String]
    var onShowLibrary: () -> Void

    private var icons: [String] {
        if quickPickIcons.contains(selectedIcon) {
            return quickPickIcons
        }
        return [selectedIcon] + Array(quickPickIcons.prefix(4))
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
            ForEach(icons, id: \.self) { iconId in
                let isSelected = selectedIcon == iconId
                Button {
                    selectedIcon = iconId
                } label: {
                    Group {
                        if SFSymbolsCatalog.isLetter(iconId) {
                            Text(SFSymbolsCatalog.letterValue(iconId))
                                .font(.system(size: 18, weight: .bold))
                        } else {
                            Image(systemName: iconId)
                                .font(.system(size: 20, weight: .medium))
                        }
                    }
                    .foregroundColor(isSelected ? theme.accentGreen : theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .background(isSelected ? Color.white.opacity(theme.isDark ? 0.15 : 1) : Color.white.opacity(theme.isDark ? 0.06 : 0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? theme.accentGreen : Color.white.opacity(theme.isDark ? 0.08 : 0.6), lineWidth: isSelected ? 1.5 : 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            Button {
                onShowLibrary()
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .background(Color.white.opacity(theme.isDark ? 0.06 : 0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(theme.isDark ? 0.08 : 0.6), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 22)
    }
}

/// Color row — only re-renders when selectedColorHex changes, not on text/focus/icon changes.
private struct CategoryColorRow: View {
    @Environment(ThemeProvider.self) private var theme
    @Binding var selectedColorHex: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
            ForEach(designColors, id: \.self) { hex in
                let isSelected = selectedColorHex == hex
                let color = Color(hex: hex) ?? .gray
                Button {
                    selectedColorHex = hex
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .shadow(color: color.opacity(0.3), radius: 4, x: 0, y: 2)
                        .scaleEffect(isSelected ? 1.15 : 1.0)
                        .overlay(
                            isSelected ?
                                Circle()
                                    .stroke(theme.textPrimary, lineWidth: 2)
                                    .scaleEffect(1.35)
                                : nil
                        )
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 22)
    }
}

// MARK: - Parent Category Picker

struct ParentCategoryPickerSheet: View {
    @Environment(ThemeProvider.self) private var theme
    @Binding var selectedParentId: String?
    @Environment(\.dismiss) private var dismiss

    private var categories: [Category] {
        CategoryStore.load().filter { $0.id != "other" }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 4) {
                        parentOption(id: nil, name: L("common_none"), sub: L("categories_top_level"), color: nil, icon: "minus.circle")
                            .padding(.bottom, 6)

                        Rectangle()
                            .fill(theme.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                            .frame(height: 1)
                            .padding(.vertical, 6)

                        ForEach(categories) { cat in
                            parentOption(id: cat.id, name: cat.name, sub: subcategoryPreview(for: cat), color: cat.color, icon: iconForCategory(cat))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)

                Button {
                    dismiss()
                } label: {
                    Text(L("common_confirm"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(theme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { OnboardingGradientBackground().ignoresSafeArea() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L("categories_parent"))
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(theme.textTertiary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func parentOption(id: String?, name: String, sub: String, color: Color?, icon: String) -> some View {
        let isSelected = (id == nil && selectedParentId == nil) || (id == selectedParentId)
        return Button {
            selectedParentId = id
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(color?.opacity(0.12) ?? Color.black.opacity(0.05))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(color ?? theme.textTertiary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundColor(theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    ZStack {
                        Circle()
                            .fill(color ?? theme.accentGreen)
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(12)
            .padding(.horizontal, 2)
            .background(isSelected ? Color.white.opacity(theme.isDark ? 0.12 : 1) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? theme.accentGreen.opacity(0.25) : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: isSelected ? Color(red: 0.118, green: 0.176, blue: 0.141).opacity(0.06) : .clear, radius: 8, x: 0, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subcategoryPreview(for cat: Category) -> String {
        let subs = SubcategoryStore.forParent(cat.id)
        return subs.isEmpty ? "—" : subs.prefix(3).map { $0.name }.joined(separator: ", ")
    }

    private func iconForCategory(_ cat: Category) -> String {
        cat.iconName ?? {
            switch cat.id {
            case "food": return "cart.fill"
            case "transport": return "car.fill"
            case "housing", "bills": return "house.fill"
            case "health": return "heart.fill"
            case "shopping": return "bag.fill"
            default: return "tag.fill"
            }
        }()
    }
}
