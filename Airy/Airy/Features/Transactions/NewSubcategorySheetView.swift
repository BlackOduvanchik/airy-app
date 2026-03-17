//
//  NewSubcategorySheetView.swift
//  Airy
//
//  Sheet for creating or editing a subcategory. Matches Edit Category design.
//

import SwiftUI

struct NewSubcategorySheetView: View {
    let initialParentCategoryId: String
    let parentDisplayName: String
    var existing: Subcategory? = nil
    var onCreate: ((Subcategory) -> Void)? = nil
    var onUpdate: ((Subcategory) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedParentId: String?
    @State private var showParentPicker = false

    private var isEditing: Bool { existing != nil }

    private var parentCategory: Category? {
        guard let id = selectedParentId else { return nil }
        return CategoryStore.byId(id)
    }

    var body: some View {
        VStack(spacing: 0) {
            handleBar
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("Name")
                    nameField

                    sectionLabel("Parent category")
                    parentSelectButton

                    submitButton
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
            ParentCategoryPickerSheet(selectedParentId: Binding(
                get: { selectedParentId },
                set: { selectedParentId = $0 }
            ))
        }
        .onAppear {
            selectedParentId = existing?.parentCategoryId ?? initialParentCategoryId
            if let existing {
                name = existing.name
            }
        }
    }

    // MARK: - Components

    private var handleBar: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.black.opacity(0.08))
            .frame(width: 36, height: 5)
            .padding(.top, 16)
            .padding(.bottom, 20)
    }

    private var header: some View {
        HStack {
            Text(isEditing ? "Edit Sub Category" : "New Sub Category")
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(OnboardingDesign.textPrimary)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(OnboardingDesign.textPrimary)
                    .frame(width: 40, height: 40)
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

    private var nameField: some View {
        TextField("e.g. Coffee shops", text: $name)
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
                    Image(systemName: parentCategory.map { CategoryIconHelper.iconName(categoryId: $0.id) } ?? "folder")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(parentCategory?.color ?? OnboardingDesign.textTertiary)
                }
                Text(parentCategory?.name ?? "None")
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

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            Text(isEditing ? "Save Changes" : "Create Sub Category")
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
        let parentId = selectedParentId ?? initialParentCategoryId

        if isEditing, var updated = existing {
            updated.name = trimmed
            updated.parentCategoryId = parentId
            onUpdate?(updated)
        } else {
            let sub = Subcategory(name: trimmed, parentCategoryId: parentId)
            onCreate?(sub)
        }
        dismiss()
    }
}
