//
//  NewCategorySheetView.swift
//  Airy
//
//  Sheet for creating a new category or subcategory. Matches design spec.
//

import SwiftUI

private let designIconOptions: [String] = [
    "creditcard.fill", "dollarsign", "face.smiling", "briefcase.fill",
    "shield.fill", "square.grid.3x3", "heart.fill", "bolt.fill",
    "clock.fill", "archivebox.fill", "cloud.fill", "gift.fill",
    "cart.fill", "car.fill", "house.fill", "bag.fill",
    "star.fill", "flag.fill", "book.fill", "gamecontroller.fill",
    "tv.fill", "phone.fill", "envelope.fill", "airplane",
    "cup.and.saucer.fill", "fork.knife", "leaf.fill", "flame.fill",
]

private let designColors: [String] = [
    "#67A082", "#7B9DAB", "#C4956A", "#E07A7A",
    "#9B7EC8", "#E8A838", "#5E7A6B", "#4A90A4",
    "#6B9B7A", "#B87D5B", "#D4A574", "#8B7EC8",
    "#5B8A9E", "#E07A5F", "#81B29A", "#3D5A80",
]

struct NewCategorySheetView: View {
    var onCreate: (Category) -> Void
    var onCreateSubcategory: ((Subcategory) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var shortDescription = ""
    @State private var selectedIcon = "creditcard.fill"
    @State private var selectedColorHex = "#67A082"
    @State private var parentCategoryId: String? = nil
    @State private var showParentPicker = false
    @FocusState private var focusedField: Field?

    enum Field { case name, description }

    private var parentCategory: Category? {
        guard let id = parentCategoryId else { return nil }
        return CategoryStore.byId(id)
    }

    private var isSubcategoryMode: Bool { parentCategoryId != nil }

    var body: some View {
        VStack(spacing: 0) {
            handleBar
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("Name")
                    inputField(placeholder: "e.g. Subscriptions", text: $name, field: .name)

                    sectionLabel("Short description")
                    inputField(placeholder: "e.g. Netflix, Spotify, iCloud", text: $shortDescription, field: .description)

                    sectionLabel("Icon")
                    iconGrid

                    sectionLabel("Parent category")
                    parentSelectButton

                    sectionLabel("Icon color")
                    colorRow

                    sectionLabel("Preview")
                        .padding(.bottom, 10)
                    previewCard
                        .padding(.bottom, 24)

                    createButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(sheetBackground)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 40, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 40))
            .overlay(
                UnevenRoundedRectangle(topLeadingRadius: 40, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 40)
                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: Color(red: 0.118, green: 0.176, blue: 0.141).opacity(0.1), radius: 40, x: 0, y: -8)
        .sheet(isPresented: $showParentPicker) {
            parentPickerSheet
        }
    }

    private var handleBar: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.black.opacity(0.08))
            .frame(width: 36, height: 5)
            .padding(.top, 16)
            .padding(.bottom, 20)
    }

    private var header: some View {
        HStack {
            Text("New Category")
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(OnboardingDesign.textPrimary)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(OnboardingDesign.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private var sheetBackground: some View {
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: 40, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 40)
                .fill(.ultraThinMaterial)
            UnevenRoundedRectangle(topLeadingRadius: 40, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 40)
                .fill(Color(red: 0.956, green: 0.969, blue: 0.961).opacity(0.98))
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

    private func inputField(placeholder: String, text: Binding<String>, field: Field) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 15))
            .foregroundColor(OnboardingDesign.textPrimary)
            .padding(14)
            .padding(.horizontal, 2)
            .focused($focusedField, equals: field)
            .background(focusedField == field ? Color.white : Color.white.opacity(0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(focusedField == field ? OnboardingDesign.accentGreen : Color.white.opacity(0.7), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.bottom, 22)
    }

    private var iconGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
            ForEach(designIconOptions, id: \.self) { iconId in
                let isSelected = selectedIcon == iconId
                Button {
                    selectedIcon = iconId
                } label: {
                    Image(systemName: iconId)
                        .font(.system(size: 20, weight: .medium))
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
        }
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

    private var colorRow: some View {
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

    private var previewCard: some View {
        let displayName = name.isEmpty ? "Category name" : name
        let displaySub = shortDescription.isEmpty ? "Short description" : shortDescription
        let color = Color(hex: selectedColorHex) ?? OnboardingDesign.accentGreen

        return HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(color.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: selectedIcon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(color)
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

    private var createButton: some View {
        Button {
            submit()
        } label: {
            Text("Create Category")
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

        if let parentId = parentCategoryId, let _ = CategoryStore.byId(parentId) {
            let sub = Subcategory(name: trimmed, parentCategoryId: parentId)
            onCreateSubcategory?(sub)
        } else {
            let cat = Category(name: trimmed, colorHex: selectedColorHex, iconName: selectedIcon)
            onCreate(cat)
        }
        dismiss()
    }
}

// MARK: - Parent Category Picker

private struct ParentCategoryPickerSheet: View {
    @Binding var selectedParentId: String?
    @Environment(\.dismiss) private var dismiss

    private var categories: [Category] {
        CategoryStore.load().filter { $0.id != "other" }
    }

    var body: some View {
        ZStack {
            Color(red: 0.118, green: 0.176, blue: 0.141).opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 36, height: 5)
                    .padding(.top, 16)
                    .padding(.bottom, 20)

                HStack {
                    Text("Parent Category")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(OnboardingDesign.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(OnboardingDesign.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(Color.black.opacity(0.05))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

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
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 44)
            }
            .background(
                Color(red: 0.956, green: 0.969, blue: 0.961).opacity(0.99)
                    .background(.ultraThinMaterial)
            )
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 40, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 40))
            .overlay(
                UnevenRoundedRectangle(topLeadingRadius: 40, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 40)
                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: Color(red: 0.118, green: 0.176, blue: 0.141).opacity(0.12), radius: 40, x: 0, y: -8)
            .onTapGesture { }
        }
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
