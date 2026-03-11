//
//  CategoriesSheetView.swift
//  Airy
//
//  Modal for "Others" category: search, list, New subcategory.
//

import SwiftUI

struct CategoriesSheetView: View {
    let parentCategoryId: String
    let parentDisplayName: String
    let items: [SubcategoryDisplayItem]
    var onSelect: (SubcategoryDisplayItem) -> Void
    var onNewCategory: (Subcategory) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showNewSubcategory = false

    private var filteredItems: [SubcategoryDisplayItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { $0.displayName.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(OnboardingDesign.textTertiary)
                    TextField("Search categories...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(12)
                .background(Color.white.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.7), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredItems) { item in
                            Button {
                                onSelect(item)
                                dismiss()
                            } label: {
                                HStack(spacing: 16) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(Color.white.opacity(0.6))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: "tag.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(OnboardingDesign.accentGreen)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.displayName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(OnboardingDesign.textPrimary)
                                    }
                                    Spacer()
                                }
                                .padding(14)
                                .background(Color.white.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 16)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.85, green: 0.88, blue: 0.90),
                        Color(red: 0.56, green: 0.73, blue: 0.65).opacity(0.5)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New") {
                        showNewSubcategory = true
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showNewSubcategory) {
                NewSubcategorySheetView(
                    parentCategoryId: parentCategoryId,
                    parentDisplayName: parentDisplayName
                ) { sub in
                    onNewCategory(sub)
                }
            }
        }
    }
}
