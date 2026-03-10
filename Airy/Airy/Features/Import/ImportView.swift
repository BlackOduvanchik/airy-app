//
//  ImportView.swift
//  Airy
//

import SwiftUI
import PhotosUI

struct ImportView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var viewModel = ImportViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Choose photo", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isProcessing)
                if viewModel.isProcessing {
                    ProgressView("Processing…")
                }
                if let msg = viewModel.resultMessage {
                    Text(msg)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                if viewModel.pendingCount > 0 {
                    NavigationLink(destination: PendingReviewView()) {
                        Text("Review \(viewModel.pendingCount) pending")
                    }
                }
            }
            .padding()
            .navigationTitle("Import")
            .sheet(isPresented: $viewModel.showPaywall) {
                PaywallView()
            }
            .onChange(of: selectedItem) { _, new in
                guard let new = new else { return }
                Task { await viewModel.processImage(new) }
            }
        }
    }
}

#Preview {
    ImportView()
}
