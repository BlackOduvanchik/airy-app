//
//  ImportDataView.swift
//  Airy
//
//  Import Data page: file picker, column mapping, detected categories, transaction import.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Document Picker

private struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            UTType.commaSeparatedText,
            UTType(filenameExtension: "csv") ?? .commaSeparatedText
        ], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}

// MARK: - Main View

struct ImportDataView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeProvider.self) private var theme
    @State private var viewModel = ImportDataViewModel()
    @State private var showDocumentPicker = false
    @State private var selectedColumnItem: ColumnIndexItem?
    @State private var showSuccessAlert = false
    @State private var selectedCategory: CategoryNameItem?

    var body: some View {
        ZStack {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    currencySection
                    fileSection
                    if viewModel.hasFile {
                        columnMappingSection
                        if !viewModel.detectedCategories.isEmpty {
                            categoriesSection
                        }
                    }
                    if viewModel.hasFile {
                        continueButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)

            if viewModel.isImporting {
                importingOverlay
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            ToolbarItem(placement: .principal) {
                Text(L("import_title"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { url in
                viewModel.parseCSV(from: url)
            }
        }
        .sheet(item: $selectedColumnItem) { item in
            ColumnMappingSheet(viewModel: viewModel, columnIndex: item.id)
                .environment(theme)
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
        }
        .sheet(item: $selectedCategory) { item in
            CategoryActionSheet(viewModel: viewModel, categoryName: item.id)
                .environment(theme)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        }
        .alert(L("import_complete"), isPresented: $showSuccessAlert) {
            Button(L("common_ok")) { dismiss() }
        } message: {
            Text("\(viewModel.importedCount) \(L("import_success"))")
        }
        .alert(L("common_error"), isPresented: Binding(
            get: { viewModel.importError != nil },
            set: { if !$0 { viewModel.importError = nil } }
        )) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(viewModel.importError ?? "")
        }
        .onChange(of: viewModel.importFinished) { _, finished in
            if finished {
                viewModel.importFinished = false
                showSuccessAlert = true
            }
        }
    }

    // MARK: - Currency Section

    private var currencySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("import_base_currency"))
            NavigationLink {
                CurrencyPickerView(baseCurrency: $viewModel.importCurrency)
            } label: {
                glassPanel {
                    HStack {
                        Text("\(viewModel.importCurrency) · \(currencyName(viewModel.importCurrency))")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(theme.textTertiary)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 56)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func currencyName(_ code: String) -> String {
        let names: [String: String] = [
            "AED": "UAE Dirham", "ARS": "Argentine Peso", "AUD": "Australian Dollar",
            "BRL": "Brazilian Real", "CAD": "Canadian Dollar", "CHF": "Swiss Franc",
            "CNY": "Chinese Yuan", "CZK": "Czech Koruna", "DKK": "Danish Krone",
            "EUR": "Euro", "GBP": "British Pound", "HKD": "Hong Kong Dollar",
            "HUF": "Hungarian Forint", "IDR": "Indonesian Rupiah", "ILS": "Israeli Shekel",
            "INR": "Indian Rupee", "JPY": "Japanese Yen", "KRW": "South Korean Won",
            "MXN": "Mexican Peso", "MYR": "Malaysian Ringgit", "NOK": "Norwegian Krone",
            "NZD": "New Zealand Dollar", "PHP": "Philippine Peso", "PLN": "Polish Zloty",
            "RON": "Romanian Leu", "RUB": "Russian Ruble", "SAR": "Saudi Riyal",
            "SEK": "Swedish Krona", "SGD": "Singapore Dollar", "THB": "Thai Baht",
            "TRY": "Turkish Lira", "TWD": "Taiwan Dollar", "UAH": "Ukrainian Hryvnia",
            "USD": "US Dollar", "VND": "Vietnamese Dong", "ZAR": "South African Rand"
        ]
        return names[code] ?? code
    }

    // MARK: - File Section

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("import_file"))
            glassPanel {
                if viewModel.hasFile {
                    fileLoadedContent
                } else {
                    fileUploadContent
                }
            }
        }
    }

    private var fileUploadContent: some View {
        Button {
            showDocumentPicker = true
        } label: {
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(theme.isDark ? 0.15 : 1))
                        .frame(width: 56, height: 56)
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(theme.accentGreen)
                }

                VStack(spacing: 4) {
                    Text(L("import_choose_csv"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                    Text(L("import_tap_browse"))
                        .font(.system(size: 13))
                        .foregroundColor(theme.textSecondary)
                }

                Text(L("import_choose_file"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.accentGreen)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(theme.accentGreen, lineWidth: 1.5)
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .padding(.horizontal, 24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .foregroundColor(Color.white.opacity(0.4))
                    .padding(4)
            )
        }
        .buttonStyle(.plain)
    }

    private var fileLoadedContent: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(theme.isDark ? 0.15 : 1))
                        .frame(width: 48, height: 48)
                        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 3)
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 22))
                        .foregroundColor(theme.accentGreen)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.fileName ?? "")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)
                    Text("\(viewModel.fileSize ?? "") · Ready to import")
                        .font(.system(size: 13))
                        .foregroundColor(theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                showDocumentPicker = true
            } label: {
                Text(L("import_change_file"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.accentGreen)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(theme.accentGreen, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    // MARK: - Column Mapping Section

    private var columnMappingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(viewModel.transactionCount) \(L("import_detected"))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.accentGreen)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(theme.accentGreen.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 12)

            sectionCaption(L("import_column_map"))
            glassPanel {
                ForEach(Array(viewModel.columns.enumerated()), id: \.element.id) { index, col in
                    mappingRow(col: col, isLast: index == viewModel.columns.count - 1)
                }
            }
        }
    }

    private func mappingRow(col: CSVColumnInfo, isLast: Bool) -> some View {
        Button {
            selectedColumnItem = ColumnIndexItem(id: col.id)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(col.header.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(theme.textTertiary)
                        .tracking(0.3)
                    Text(col.preview)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Text(col.mapping.displayName)
                        .font(.system(size: 13))
                        .foregroundColor(col.mapping == .skip ? theme.textTertiary : theme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(theme.isDark ? 0.1 : 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(16)
            .contentShape(Rectangle())
            .overlay(
                Group {
                    if !isLast {
                        Rectangle()
                            .fill(Color.white.opacity(theme.isDark ? 0.06 : 0.3))
                            .frame(height: 1)
                    }
                },
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Categories Section

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionCaption(L("import_categories"))
            glassPanel {
                FlowLayout(spacing: 8) {
                    ForEach(viewModel.detectedCategories, id: \.self) { cat in
                        categoryChip(cat)
                    }
                }
                .padding(16)
            }

            // Detected subcategories from subcategory column
            if !viewModel.detectedSubcategories.isEmpty {
                sectionCaption(L("import_subcategories"))
                    .padding(.top, 14)
                glassPanel {
                    FlowLayout(spacing: 8) {
                        ForEach(viewModel.detectedSubcategories, id: \.name) { sub in
                            subcategoryChip(sub.name, parentCategory: sub.rowCategory)
                        }
                    }
                    .padding(16)
                }
            }

            // Legend
            HStack(spacing: 16) {
                legendDot(color: theme.accentGreen, label: L("import_cat_new"))
                legendDot(color: theme.accentBlue, label: L("import_cat_sub"))
                legendDot(color: Color(hex: CategoryStore.defaultColorAmber) ?? .orange, label: L("import_cat_existing"))
                legendDot(color: theme.textTertiary, label: L("import_cat_skip"))
            }
            .padding(.top, 10)
            .padding(.horizontal, 4)
        }
    }

    private func subcategoryChip(_ name: String, parentCategory: String?) -> some View {
        let allSubs = SubcategoryStore.load()
        let isExisting = allSubs.contains(where: { $0.name.lowercased() == name.lowercased() })
        let chipColor = isExisting ? (Color(hex: CategoryStore.defaultColorAmber) ?? .orange) : theme.accentBlue
        let parentLabel = parentCategory ?? ""

        return HStack(spacing: 6) {
            Circle()
                .fill(chipColor)
                .frame(width: 8, height: 8)
            if !parentLabel.isEmpty {
                Text(parentLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.textTertiary)
                Text("→")
                    .font(.system(size: 10))
                    .foregroundColor(theme.textTertiary)
            }
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(chipColor.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(chipColor.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func categoryChip(_ name: String) -> some View {
        let action = viewModel.categoryActions[name] ?? .importAsCategory
        let chipColor = categoryChipColor(for: action)
        let isSkip = action == .skip

        return Button {
            selectedCategory = CategoryNameItem(id: name)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(chipColor)
                    .frame(width: 8, height: 8)
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSkip ? theme.textTertiary : theme.textPrimary)
                    .strikethrough(isSkip, color: theme.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(chipColor.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(chipColor.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func categoryChipColor(for action: CategoryImportAction) -> Color {
        switch action {
        case .importAsCategory:
            return theme.accentGreen
        case .importAsSubcategory:
            return theme.accentBlue
        case .mapToExisting(let categoryId):
            return CategoryStore.byId(categoryId)?.color ?? Color(hex: CategoryStore.defaultColorAmber) ?? .orange
        case .skip:
            return theme.textTertiary
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(theme.textTertiary)
        }
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button {
            Task { _ = await viewModel.importTransactions() }
        } label: {
            Text("Continue")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(theme.accentGreen)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .shadow(color: theme.accentGreen.opacity(0.3), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .disabled(!viewModel.hasRequiredMappings)
        .opacity(viewModel.hasRequiredMappings ? 1 : 0.5)
        .padding(.top, 8)
    }

    // MARK: - Importing Overlay

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(theme.accentGreen)
                Text(L("import_importing"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(theme.textPrimary)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }

    // MARK: - Helpers

    private func sectionCaption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.5)
            .foregroundColor(theme.textTertiary)
            .padding(.bottom, 8)
    }

    private func glassPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(theme.isDark ? AnyShapeStyle(theme.glassBg) : AnyShapeStyle(.ultraThinMaterial))
        .overlay(theme.isDark ? nil : theme.glassBg.opacity(0.5).allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(theme.glassBorder, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: theme.isDark ? Color.black.opacity(0.4) : theme.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Column Index Wrapper

private struct ColumnIndexItem: Identifiable {
    let id: Int
}

// MARK: - Column Mapping Sheet

private struct ColumnMappingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeProvider.self) private var theme
    @Bindable var viewModel: ImportDataViewModel
    let columnIndex: Int

    private var column: CSVColumnInfo? {
        viewModel.columns.first(where: { $0.id == columnIndex })
    }

    var body: some View {
        ZStack {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("import_map_column"))
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(0.5)
                            .foregroundColor(theme.textTertiary)
                        if let col = column {
                            Text("\(col.header) → \(col.preview)")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(theme.textPrimary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(theme.textTertiary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(CSVColumnMapping.allCases.enumerated()), id: \.element) { index, mapping in
                            let isSelected = column?.mapping == mapping
                            let isLast = index == CSVColumnMapping.allCases.count - 1
                            Button {
                                if let idx = viewModel.columns.firstIndex(where: { $0.id == columnIndex }) {
                                    viewModel.columns[idx].mapping = mapping
                                }
                                dismiss()
                            } label: {
                                HStack(spacing: 16) {
                                    Text(mapping.displayName)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(theme.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    ZStack {
                                        Circle()
                                            .stroke(isSelected ? theme.accentGreen : theme.textTertiary, lineWidth: 2)
                                            .frame(width: 22, height: 22)
                                        if isSelected {
                                            Circle()
                                                .fill(theme.accentGreen)
                                                .frame(width: 10, height: 10)
                                        }
                                    }
                                }
                                .padding(.horizontal, 24)
                                .frame(height: 52)
                                .contentShape(Rectangle())
                                .overlay(
                                    Group {
                                        if !isLast {
                                            Rectangle()
                                                .fill(Color.white.opacity(theme.isDark ? 0.06 : 0.15))
                                                .frame(height: 1)
                                        }
                                    },
                                    alignment: .bottom
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, pos) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

// MARK: - Category Name Wrapper

private struct CategoryNameItem: Identifiable {
    let id: String
}

// MARK: - Category Action Sheet

private struct CategoryActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeProvider.self) private var theme
    @Bindable var viewModel: ImportDataViewModel
    let categoryName: String

    @State private var existingCategories: [Category] = []

    private var action: CategoryImportAction {
        viewModel.categoryActions[categoryName] ?? .importAsCategory
    }

    private var txCount: Int {
        viewModel.transactionCount(forCategory: categoryName)
    }

    var body: some View {
        ZStack {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                sheetHeader

                ScrollView {
                    VStack(spacing: 10) {
                        // Option 1: Create as Category
                        optionCard(
                            icon: "plus.circle.fill",
                            iconColor: theme.accentGreen,
                            title: L("import_create_cat"),
                            subtitle: L("import_create_cat_sub"),
                            isSelected: action == .importAsCategory
                        ) {
                            viewModel.categoryActions[categoryName] = .importAsCategory
                        }

                        // Option 2: Create as Subcategory
                        optionCard(
                            icon: "arrow.turn.down.right",
                            iconColor: theme.accentBlue,
                            title: L("import_create_subcat"),
                            subtitle: L("import_create_subcat_sub"),
                            isSelected: isSubcategoryAction
                        ) {
                            let firstId = existingCategories.first?.id ?? "other"
                            viewModel.categoryActions[categoryName] = .importAsSubcategory(parentId: firstId)
                        }

                        if isSubcategoryAction {
                            categoryPickerList(selectedId: subcategoryParentId) { id in
                                viewModel.categoryActions[categoryName] = .importAsSubcategory(parentId: id)
                            }
                        }

                        // Option 3: Map to Existing
                        optionCard(
                            icon: "arrow.right.circle.fill",
                            iconColor: Color(hex: CategoryStore.defaultColorAmber) ?? .orange,
                            title: L("import_map_existing"),
                            subtitle: L("import_map_existing_sub"),
                            isSelected: isMapAction
                        ) {
                            let firstId = existingCategories.first?.id ?? "other"
                            viewModel.categoryActions[categoryName] = .mapToExisting(categoryId: firstId)
                        }

                        if isMapAction {
                            categoryPickerList(selectedId: mappedCategoryId) { id in
                                viewModel.categoryActions[categoryName] = .mapToExisting(categoryId: id)
                            }
                        }

                        // Option 4: Skip
                        optionCard(
                            icon: "xmark.circle.fill",
                            iconColor: theme.textTertiary,
                            title: L("common_skip"),
                            subtitle: L("import_skip_sub"),
                            isSelected: action == .skip
                        ) {
                            viewModel.categoryActions[categoryName] = .skip
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: viewModel.categoryActions[categoryName])
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear {
            existingCategories = CategoryStore.load()
        }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("import_map_category"))
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(theme.textTertiary)
                Text(categoryName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
            }
            Spacer()
            HStack(spacing: 12) {
                Text("\(txCount) \(L("import_txns"))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.accentGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(theme.accentGreen.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.textTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Option Card

    private func optionCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    Circle()
                        .stroke(isSelected ? theme.accentGreen : theme.textTertiary.opacity(0.5), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(theme.accentGreen)
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .padding(16)
            .background(isSelected ? iconColor.opacity(0.08) : Color.white.opacity(theme.isDark ? 0.06 : 0.3))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? iconColor.opacity(0.3) : Color.white.opacity(theme.isDark ? 0.08 : 0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category Picker

    private func categoryPickerList(selectedId: String, onSelect: @escaping (String) -> Void) -> some View {
        VStack(spacing: 0) {
            ForEach(existingCategories) { cat in
                Button {
                    onSelect(cat.id)
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(cat.color)
                            .frame(width: 10, height: 10)
                        Text(cat.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                        Spacer()
                        if cat.id == selectedId {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(theme.accentGreen)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, 20)
        .background(Color.white.opacity(theme.isDark ? 0.04 : 0.2))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(theme.isDark ? 0.06 : 0.15), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
    }

    // MARK: - Helpers

    private var isSubcategoryAction: Bool {
        if case .importAsSubcategory = action { return true }
        return false
    }

    private var isMapAction: Bool {
        if case .mapToExisting = action { return true }
        return false
    }

    private var subcategoryParentId: String {
        if case .importAsSubcategory(let id) = action { return id }
        return existingCategories.first?.id ?? "other"
    }

    private var mappedCategoryId: String {
        if case .mapToExisting(let id) = action { return id }
        return existingCategories.first?.id ?? "other"
    }
}
