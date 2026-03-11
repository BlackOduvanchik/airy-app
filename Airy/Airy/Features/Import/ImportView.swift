//
//  ImportView.swift
//  Airy
//

import SwiftUI
import PhotosUI

enum ImportSource {
    case gallery
    case clipboard
}

struct ImportView: View {
    var initialSource: ImportSource = .gallery
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var viewModel = ImportViewModel()
    @State private var didAttemptClipboard = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if viewModel.isProcessing {
                    ProgressView("Processing…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if initialSource == .clipboard && !didAttemptClipboard {
                    ProgressView("Reading from clipboard…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if initialSource == .clipboard && viewModel.resultMessage == "No image in clipboard" {
                    VStack(spacing: 16) {
                        Text("No image in clipboard")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        PhotosPicker(
                            selection: $selectedItems,
                            maxSelectionCount: 3,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label("Choose from Gallery instead", systemImage: "photo.on.rectangle.angled")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 3,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Choose from Gallery", systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isProcessing)
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
            .onChange(of: selectedItems) { _, new in
                guard !new.isEmpty else { return }
                let items = new
                Task {
                    await viewModel.processImages(items)
                    await MainActor.run { selectedItems = [] }
                }
            }
            .task {
                if initialSource == .clipboard && !didAttemptClipboard {
                    didAttemptClipboard = true
                    let ok = await viewModel.processImageFromClipboard()
                    if !ok {
                        await MainActor.run { viewModel.resultMessage = "No image in clipboard" }
                    }
                }
            }
        }
    }
}

#Preview {
    ImportView()
}
