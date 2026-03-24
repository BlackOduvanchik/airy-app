//
//  NewSubcategorySheetView.swift
//  Airy
//
//  Sheet for creating or editing a subcategory. Matches NewCategorySheetView design.
//

import SwiftUI

struct NewSubcategorySheetView: View {
    @Environment(ThemeProvider.self) private var theme
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
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        sectionLabel(L("newsub_name"))
                        nameField

                        sectionLabel(L("newsub_parent"))
                        parentSelectButton
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)

                submitButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { OnboardingGradientBackground().ignoresSafeArea() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(isEditing ? L("newsub_edit") : L("newsub_new"))
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
        .sheet(isPresented: $showParentPicker) {
            ParentCategoryPickerSheet(selectedParentId: Binding(
                get: { selectedParentId },
                set: { selectedParentId = $0 }
            ))
            .themed(theme)
        }
        .onAppear {
            selectedParentId = existing?.parentCategoryId ?? initialParentCategoryId
            if let existing {
                name = existing.name
            }
        }
    }

    // MARK: - Components

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(theme.textTertiary)
            .tracking(0.5)
            .padding(.leading, 4)
            .padding(.bottom, 10)
    }

    private var nameField: some View {
        TextField("", text: $name, prompt: Text(L("newsub_placeholder")).foregroundStyle(theme.textTertiary))
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
                    Image(systemName: parentCategory.map { CategoryIconHelper.iconName(categoryId: $0.id) } ?? "folder")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(parentCategory?.color ?? theme.textTertiary)
                }
                Text(parentCategory?.name ?? L("common_none"))
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

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            Text(isEditing ? L("newsub_save") : L("newsub_create"))
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
