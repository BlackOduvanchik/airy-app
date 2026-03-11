//
//  NewSubcategorySheetView.swift
//  Airy
//
//  Sheet for creating a new custom subcategory.
//

import SwiftUI

struct NewSubcategorySheetView: View {
    let parentCategoryId: String
    let parentDisplayName: String
    var onCreate: (Subcategory) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TextField("Subcategory name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .autocapitalization(.words)

                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let sub = Subcategory(name: trimmed, parentCategoryId: parentCategoryId)
                    SubcategoryStore.add(sub)
                    onCreate(sub)
                    dismiss()
                } label: {
                    Text("Create Subcategory")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .background(OnboardingDesign.accentGreen)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
            }
            .padding(24)
            .navigationTitle("New Subcategory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
