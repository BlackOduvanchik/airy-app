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
    @State private var pendingSelection: [PhotosPickerItem] = []
    @State private var isLoadingSelection = false
    @Environment(ThemeProvider.self) private var theme
    @State private var viewModel = ImportViewModel()
    @State private var didAttemptClipboard = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if viewModel.isProcessing || isLoadingSelection {
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
                            maxSelectionCount: 30,
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
                        maxSelectionCount: 30,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Choose from Gallery", systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isProcessing || isLoadingSelection)
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
                    .themed(theme)
            }
            .onChange(of: selectedItems) { _, new in
                guard !new.isEmpty else { return }
                pendingSelection = new
                isLoadingSelection = true
            }
            .task(id: pendingSelection.count) {
                guard !pendingSelection.isEmpty else { return }
                let toProcess = pendingSelection
                await viewModel.processImages(toProcess)
                await MainActor.run {
                    if viewModel.pipelinePhase == .idle && viewModel.errorMessage == nil && viewModel.resultMessage == nil {
                        viewModel.resultMessage = "Import didn't start – try again"
                    }
                    selectedItems = []
                    pendingSelection = []
                    isLoadingSelection = false
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
