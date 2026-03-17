//
//  ExtractionDebugReportListView.swift
//  Airy
//
//  Debug UI: list of per-screenshot extraction reports (source, counts, completion status).
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
                                row("Raw row-like blocks", "\(report.rawRowLikeBlocks)")
                                row("Transaction-like row estimate", "\(report.transactionLikeRowEstimate)")
                                row("Strong amount row count", "\(report.strongAmountRowCount)")
                                row("Repeated row cluster count", "\(report.repeatedRowClusterCount)")
                                row("Extracted transactions", "\(report.extractedTransactions)")
                                row("Coverage score", String(format: "%.2f", report.coverageScore))
                                row("Extraction status", report.extractionStatus.rawValue)
                                row("Screen type", report.screenType.rawValue)
                                row("Field completeness score", String(format: "%.2f", report.fieldCompletenessScore))
                                row("Completion confidence", String(format: "%.2f", report.completionConfidence))
                                if let reason = report.completionReason, !reason.isEmpty {
                                    row("Completion reason", reason)
                                }
                                if let expected = report.expectedTransactionCountPrimarySignal {
                                    row("Expected transaction count (primary)", "\(expected)")
                                }
                                row("Removed by validation", "\(report.removedByValidation)")
                                row("Removed by duplicate", "\(report.removedByDuplicate)")
                                row("Finally shown", "\(report.finallyShown)")
                                if let outcome = report.localRuleOutcome {
                                    row("Local rule outcome", outcome.rawValue)
                                }
                                row("Fallback triggered", report.fallbackTriggered ? "Yes" : "No")
                                if let ruleId = report.matchedRuleId, !ruleId.isEmpty {
                                    row("Matched rule id", String(ruleId.prefix(8)) + "...")
                                }
                                if let stage = report.matchedRuleTrustStage {
                                    row("Matched rule trust stage", stage.rawValue)
                                }
                                if let reason = report.reasonLocalRulesDidNotAbstain, !reason.isEmpty {
                                    row("Reason local abstained", reason)
                                }
                                if let familyId = report.layoutFamilyId, !familyId.isEmpty {
                                    row("Layout family id", String(familyId.prefix(8)) + "...")
                                }
                                row("Did local help screen type", report.didLocalRulesHelpScreenType ? "Yes" : "No")
                                row("Did local help row grouping", report.didLocalRulesHelpRowGrouping ? "Yes" : "No")
                                row("Local assist confidence", String(format: "%.2f", report.localAssistConfidence))
                                if let reasonFail = report.reasonForHardFail, !reasonFail.isEmpty {
                                    row("Reason for hard fail", reasonFail)
                                }
                                if let matchedId = report.matchedLayoutFamilyId, !matchedId.isEmpty {
                                    row("Matched layout family id", String(matchedId.prefix(8)) + "...")
                                }
                                row("Did layout family match", report.didLayoutFamilyMatch ? "Yes" : "No")
                                row("Did local improve row grouping", report.didLocalImproveRowGrouping ? "Yes" : "No")
                                row("Did local improve expected transaction count", report.didLocalImproveExpectedTransactionCount ? "Yes" : "No")
                                row("Did local reduce need for GPT", report.didLocalReduceNeedForGPT ? "Yes" : "No")
                                row("Local structure assist confidence", String(format: "%.2f", report.localStructureAssistConfidence))
                                if let sim = report.layoutFamilySimilarityScore {
                                    row("Layout family similarity score", String(format: "%.2f", sim))
                                }
                                if let size = report.familyClusterSize {
                                    row("Family cluster size", "\(size)")
                                }
                                row("Was family reused", report.wasFamilyReused ? "Yes" : "No")
                                row("Was family merged", report.wasFamilyMerged ? "Yes" : "No")
                                if let why = report.whyNewFamilyWasCreated, !why.isEmpty {
                                    row("Why new family was created", why)
                                }
                                row("Local assist confidence computed", report.localAssistConfidenceComputed ? "Yes" : "No")
                                if let reason = report.familyReuseReason, !reason.isEmpty {
                                    row("Family reuse reason", reason)
                                }
                                if let features = report.matchedStructuralFeatures, !features.isEmpty {
                                    row("Matched structural features", features)
                                }
                                if let rejected = report.rejectedStructuralFeatures, !rejected.isEmpty {
                                    row("Rejected structural features", rejected)
                                }
                                if let threshold = report.familyReuseThresholdUsed, !threshold.isEmpty {
                                    row("Family reuse threshold used", threshold)
                                }
                                row("Was strong reuse", report.wasStrongReuse ? "Yes" : "No")
                                row("Was weak reuse", report.wasWeakReuse ? "Yes" : "No")
                                if let reason = report.familyRejectionReason, !reason.isEmpty {
                                    row("Family rejection reason", reason)
                                }
                                if let exceeded = report.familyToleranceExceeded, !exceeded.isEmpty {
                                    row("Family tolerance exceeded", exceeded)
                                }
                                if let size = report.familyProfileSize {
                                    row("Family profile size", "\(size)")
                                }
                                if let variance = report.familyProfileVariance, !variance.isEmpty {
                                    row("Family profile variance", variance)
                                }
                                if let n = report.localRowsGrouped {
                                    row("Local rows grouped", "\(n)")
                                }
                                if let n = report.localRowsParsed {
                                    row("Local rows parsed", "\(n)")
                                }
                                if let n = report.localValidAmountCount {
                                    row("Local valid amount count", "\(n)")
                                }
                                if let n = report.localValidMerchantCount {
                                    row("Local valid merchant count", "\(n)")
                                }
                                if let c = report.localExtractionConfidence {
                                    row("Local extraction confidence", String(format: "%.2f", c))
                                }
                                if let decision = report.localExtractionDecision, !decision.isEmpty {
                                    row("Local extraction decision", decision)
                                }
                                if let reason = report.reasonGPTFallbackTriggered {
                                    row("Reason GPT fallback triggered", reason.rawValue)
                                }
                                if let reason = report.reasonGPTFallbackNotTriggered {
                                    row("Reason GPT not triggered", reason.rawValue)
                                }
                                if let prefix = report.imageHashPrefix, !prefix.isEmpty {
                                    row("Image hash", prefix)
                                }
                                row("Template store count", "\(report.templateStoreCount)")
                                row("Template match tried", report.templateMatchTried ? "Yes" : "No")
                                if report.templateMatchTried {
                                    row("Template best confidence", String(format: "%.3f", report.templateMatchBestConfidence))
                                }
                                row("Template derived", report.templateDerived ? "Yes" : "No")
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
                rawRowLikeBlocks: 32,
                transactionLikeRowEstimate: 6,
                strongAmountRowCount: 6,
                repeatedRowClusterCount: 6,
                extractedTransactions: 6,
                coverageScore: 1.0,
                extractionStatus: .complete,
                removedByValidation: 1,
                removedByDuplicate: 0,
                finallyShown: 6,
                imageHashPrefix: "a1b2c3d4",
                screenType: .transactionList,
                fieldCompletenessScore: 0.95,
                completionConfidence: 0.92,
                completionReason: "extracted 6 vs 6 clusters; field score 0.95",
                expectedTransactionCountPrimarySignal: 6
            )
        ])
    }
}
