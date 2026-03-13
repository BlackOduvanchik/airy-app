//
//  AIParsingRulesSheetView.swift
//  Airy
//
//  Generate parsing rules from OCR sample via GPT. Rules saved locally, no AI at runtime.
//

import SwiftUI

struct AIParsingRulesSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var pastedOcr = ""
    @State private var useLastImport = true
    @State private var isGenerating = false
    @State private var message: String?
    @State private var messageIsError = false

    private let gptService = GPTRulesService()

    var body: some View {
        NavigationStack {
            ZStack {
                OnboardingGradientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        disclosureText
                        apiKeySection
                        ocrSourceSection
                        if let msg = message {
                            Text(msg)
                                .font(.system(size: 14))
                                .foregroundColor(messageIsError ? Color(red: 0.84, green: 0.43, blue: 0.43) : OnboardingDesign.textSecondary)
                        }
                        generateButton
                    }
                    .padding(20)
                }
            }
            .navigationTitle("AI Parsing Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            apiKey = KeychainHelper.loadOpenAIKey() ?? ""
            pastedOcr = ParsingRulesStore.shared.lastOcrSample ?? ""
        }
    }

    private var disclosureText: some View {
        Text("Your OCR sample will be sent to OpenAI to generate extraction rules. Rules are saved on device and used locally—no AI calls during import.")
            .font(.system(size: 13))
            .foregroundColor(OnboardingDesign.textSecondary)
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OpenAI API Key")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(OnboardingDesign.textPrimary)
            SecureField("sk-...", text: $apiKey)
                .textContentType(.password)
                .autocapitalization(.none)
                .padding(12)
                .background(Color.white.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Button("Save key") {
                KeychainHelper.saveOpenAIKey(apiKey)
                message = "Key saved"
                messageIsError = false
            }
            .font(.system(size: 13, weight: .medium))
        }
    }

    private var ocrSourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Use last import", isOn: $useLastImport)
                .tint(OnboardingDesign.accentGreen)
            if !useLastImport {
                Text("Paste OCR text from a bank screenshot:")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(OnboardingDesign.textPrimary)
                TextEditor(text: $pastedOcr)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color.white.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var generateButton: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await generateRules() }
            } label: {
                HStack {
                    if isGenerating {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isGenerating ? "Generating..." : "Generate rules")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(OnboardingDesign.accentGreen)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isGenerating || ocrTextToUse.isEmpty)
            .buttonStyle(.plain)
            Text("Saves rules for this screenshot format. Next time you import a similar image, the app will parse it locally without calling GPT.")
                .font(.system(size: 12))
                .foregroundColor(OnboardingDesign.textTertiary)
        }
    }

    private var ocrTextToUse: String {
        useLastImport ? (ParsingRulesStore.shared.lastOcrSample ?? "") : pastedOcr
    }

    private func generateRules() async {
        let text = ocrTextToUse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            await MainActor.run {
                message = "No OCR sample. Import a screenshot first or paste text."
                messageIsError = true
            }
            return
        }
        await MainActor.run {
            isGenerating = true
            message = nil
        }
        do {
            let rules = try await gptService.generateRules(ocrText: text)
            await MainActor.run {
                ParsingRulesStore.shared.saveForOcr(rules: rules, ocrText: text)
                message = "Rules saved. Next imports will use them locally."
                messageIsError = false
                isGenerating = false
            }
        } catch let err as GPTRulesError {
            await MainActor.run {
                message = err.errorDescription ?? err.localizedDescription
                messageIsError = true
                isGenerating = false
            }
        } catch {
            await MainActor.run {
                let nsErr = error as NSError
                var msg = nsErr.localizedDescription
                if msg.isEmpty || msg.contains("couldn't be completed") {
                    msg = nsErr.localizedFailureReason ?? nsErr.userInfo[NSLocalizedDescriptionKey] as? String ?? String(describing: error)
                }
                message = msg.isEmpty ? "Unknown error" : msg
                messageIsError = true
                isGenerating = false
            }
        }
    }
}
