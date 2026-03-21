//
//  ExtractionDebugReportListView.swift
//  Airy
//
//  Debug UI: list of per-screenshot extraction reports (source, counts).
//

import SwiftUI
import UIKit

private struct ShareSheetItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ExtractionDebugReportListView: View {
    let reports: [ExtractionDebugReport]
    @State private var shareItem: ShareSheetItem? = nil
    @State private var exportError: Bool = false

    var body: some View {
        Group {
            if reports.isEmpty {
                ContentUnavailableView(
                    "No extraction run yet",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Import one or more screenshots to see per-image debug reports here.")
                )
            } else {
                List {
                    ForEach(reports) { report in
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                row("Source", report.source.rawValue)
                                row("Image sent to GPT", report.imageSentToGPT ? "Yes" : "No")
                                row("Extracted transactions", "\(report.extractedTransactions)")
                                row("Removed by duplicate", "\(report.removedByDuplicate)")
                                row("Finally shown", "\(report.finallyShown)")
                                if let prefix = report.imageHashPrefix, !prefix.isEmpty {
                                    row("Image hash", prefix)
                                }
                            }
                            .padding(.vertical, 4)
                        } header: {
                            Text("Screenshot #\(report.imageIndex + 1)")
                                .font(.headline)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Extraction Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !reports.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if let url = ImportViewModel.shared.exportDebugReportsAsCSV() {
                            shareItem = ShareSheetItem(url: url)
                        } else {
                            exportError = true
                        }
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(url: item.url)
        }
        .alert("Export failed", isPresented: $exportError) {
            Button("OK", role: .cancel) {}
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    NavigationStack {
        ExtractionDebugReportListView(reports: [
            ExtractionDebugReport(
                imageIndex: 0,
                source: .gptVision,
                imageSentToGPT: true,
                extractedTransactions: 6,
                removedByDuplicate: 0,
                finallyShown: 6,
                imageHashPrefix: "a1b2c3d4"
            )
        ])
    }
}
