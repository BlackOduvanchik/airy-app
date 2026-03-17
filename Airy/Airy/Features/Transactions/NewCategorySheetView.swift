//
//  NewCategorySheetView.swift
//  Airy
//
//  Sheet for creating a new category or subcategory. Matches design spec.
//

import SwiftUI

private let designColors: [String] = [
    "#67A082", "#7B9DAB", "#C4956A", "#E07A7A",
    "#9B7EC8", "#E8A838", "#5E7A6B", "#4A90A4",
    "#6B9B7A", "#B87D5B", "#D4A574", "#8B7EC8",
    "#5B8A9E", "#E07A5F", "#81B29A", "#3D5A80",
]

struct NewCategorySheetView: View {
    var existing: Category? = nil
    var onCreate: (Category) -> Void
    var onCreateSubcategory: ((Subcategory) -> Void)?
    var onUpdate: ((Category) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var shortDescription = ""
    @State private var selectedIcon = "creditcard.fill"
    @State private var selectedColorHex = "#67A082"
    @State private var parentCategoryId: String? = nil
    @State private var showParentPicker = false
    @State private var showIconLibrary = false
    @State private var quickPickIcons: [String] = []

    private var parentCategory: Category? {
        guard let id = parentCategoryId else { return nil }
        return CategoryStore.byId(id)
    }

    private var isSubcategoryMode: Bool { parentCategoryId != nil }
    private var isEditMode: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        CategoryPreviewCard(
                            name: name,
                            shortDescription: shortDescription,
                            selectedIcon: selectedIcon,
                            selectedColorHex: selectedColorHex
                        )
                        .padding(.bottom, 24)

                        sectionLabel("Name")
                        inputField(placeholder: "e.g. Subscriptions", text: $name)

                        sectionLabel("Short description")
                        inputField(placeholder: "e.g. Netflix, Spotify, iCloud", text: $shortDescription)

                        sectionLabel("Icon")
                        CategoryIconGrid(
                            selectedIcon: $selectedIcon,
                            quickPickIcons: quickPickIcons,
                            onShowLibrary: { showIconLibrary = true }
                        )

                        if !isEditMode {
                            sectionLabel("Parent category")
                            parentSelectButton
                        }

                        sectionLabel("Icon color")
                        CategoryColorRow(selectedColorHex: $selectedColorHex)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
                createButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.956, green: 0.969, blue: 0.961).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(isEditMode ? "EDIT CATEGORY" : "NEW CATEGORY")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(OnboardingDesign.textTertiary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showParentPicker) {
            parentPickerSheet
        }
        .sheet(isPresented: $showIconLibrary) {
            IconLibraryView(selectedIcon: $selectedIcon) {
                showIconLibrary = false
            }
        }
        .onAppear {
            if quickPickIcons.isEmpty {
                quickPickIcons = Array(SFSymbolsCatalog.allSymbols.filter { !SFSymbolsCatalog.isLetter($0) }.shuffled().prefix(5))
            }
            if let e = existing {
                name = e.name
                let icon = e.iconName ?? defaultIconForCategoryId(e.id)
                selectedIcon = SFSymbolsCatalog.allSymbols.contains(icon) ? icon : "tag.fill"
                selectedColorHex = e.colorHex
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(OnboardingDesign.textTertiary)
            .tracking(0.5)
            .padding(.leading, 4)
            .padding(.bottom, 10)
    }

    private func inputField(placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 15))
            .foregroundColor(OnboardingDesign.textPrimary)
            .padding(14)
            .padding(.horizontal, 2)
            .background(Color.white.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
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
                        .foregroundColor(parentCategory?.color ?? OnboardingDesign.textTertiary)
                }
                Text(parentCategory?.name ?? "None (top-level)")
                    .font(.system(size: 15, weight: parentCategory != nil ? .medium : .regular))
                    .foregroundColor(parentCategory != nil ? OnboardingDesign.textPrimary : OnboardingDesign.textTertiary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(OnboardingDesign.textTertiary)
            }
            .padding(13)
            .padding(.horizontal, 3)
            .background(Color.white.opacity(0.4))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.7), lineWidth: 1))
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
            Text(isEditMode ? "Save Changes" : "Create Category")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(16)
        }
        .background(OnboardingDesign.textPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
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
    let name: String
    let shortDescription: String
    let selectedIcon: String
    let selectedColorHex: String

    var body: some View {
        let displayName = name.isEmpty ? "Category name" : name
        let displaySub = shortDescription.isEmpty ? "Short description" : shortDescription
        let color = Color(hex: selectedColorHex) ?? OnboardingDesign.accentGreen

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
                    .foregroundColor(OnboardingDesign.textPrimary)
                Text(displaySub)
                    .font(.system(size: 12))
                    .foregroundColor(OnboardingDesign.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Circle()
                .fill(Color(red: 0.956, green: 0.969, blue: 0.961))
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color(red: 0.89, green: 0.91, blue: 0.90), lineWidth: 1.5))
        }
        .padding(14)
        .padding(.horizontal, 2)
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(OnboardingDesign.accentGreen.opacity(0.2), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color(red: 0.118, green: 0.176, blue: 0.141).opacity(0.04), radius: 16, x: 0, y: 4)
    }
}

/// Icon grid — only re-renders when selectedIcon or quickPickIcons change, not on text/focus changes.
private struct CategoryIconGrid: View {
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
                    .foregroundColor(isSelected ? OnboardingDesign.accentGreen : OnboardingDesign.textSecondary)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .background(isSelected ? Color.white : Color.white.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? OnboardingDesign.accentGreen : Color.white.opacity(0.6), lineWidth: isSelected ? 1.5 : 1)
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
                    .foregroundColor(OnboardingDesign.textTertiary)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .background(Color.white.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
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
    @Binding var selectedColorHex: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 8), spacing: 12) {
            ForEach(designColors, id: \.self) { hex in
                let isSelected = selectedColorHex == hex
                Button {
                    selectedColorHex = hex
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: hex) ?? .gray)
                            .frame(width: 32, height: 32)
                        if isSelected {
                            Circle()
                                .stroke(OnboardingDesign.textPrimary, lineWidth: 1.5)
                                .frame(width: 40, height: 40)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .padding(.bottom, 22)
    }
}

// MARK: - Parent Category Picker

struct ParentCategoryPickerSheet: View {
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
                        parentOption(id: nil, name: "None", sub: "Top-level category", color: nil, icon: "minus.circle")
                            .padding(.bottom, 6)

                        Rectangle()
                            .fill(Color.black.opacity(0.06))
                            .frame(height: 1)
                            .padding(.vertical, 6)

                        ForEach(categories) { cat in
                            parentOption(id: cat.id, name: cat.name, sub: subcategoryPreview(for: cat), color: cat.color, icon: iconForCategory(cat))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }

                Button {
                    dismiss()
                } label: {
                    Text("Confirm")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                }
                .background(OnboardingDesign.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.956, green: 0.969, blue: 0.961).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("PARENT CATEGORY")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(OnboardingDesign.textTertiary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
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
                        .foregroundColor(color ?? OnboardingDesign.textTertiary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textPrimary)
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundColor(OnboardingDesign.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    ZStack {
                        Circle()
                            .fill(color ?? OnboardingDesign.accentGreen)
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(12)
            .padding(.horizontal, 2)
            .background(isSelected ? Color.white : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? OnboardingDesign.accentGreen.opacity(0.25) : Color.clear, lineWidth: 1.5)
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
