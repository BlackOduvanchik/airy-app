//
//  AddTransactionView.swift
//  Airy
//
//  Manual add or edit transaction: sheet design with amount, type toggle, categories, date/time, note.
//

import SwiftUI

struct AddTransactionView: View {
    var transaction: Transaction?
    /// Initial transaction type when creating new (e.g. "income" for Add Income flow).
    var initialType: String?
    /// Called after a successful save (e.g. to pop parent when editing).
    var onSuccess: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AddTransactionViewModel
    @State private var showDatePicker = false
    @State private var showTimePicker = false
    @State private var showCustomKeyboard = false
    @State private var calculatorExpression = ""
    @State private var showCategoriesSheet = false

    init(transaction: Transaction? = nil, initialType: String? = nil, onSuccess: (() -> Void)? = nil) {
        self.transaction = transaction
        self.initialType = initialType
        self.onSuccess = onSuccess
        _viewModel = State(initialValue: AddTransactionViewModel(existing: transaction, initialType: initialType))
    }

    private var displayAmountResult: String {
        String(format: "%.2f", evaluateAmountExpression(calculatorExpression) ?? 0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingGradientBackground()
                .ignoresSafeArea()

            sheetContent

            if showCustomKeyboard {
                VStack {
                    Spacer()
                    AmountKeyboardView(
                        expression: $calculatorExpression,
                        amountText: $viewModel.amountText,
                        transactionType: $viewModel.transactionType,
                        selectedCurrency: $viewModel.selectedCurrency,
                        currencies: AddTransactionViewModel.currencies,
                        onDismiss: {
                            if !calculatorExpression.isEmpty {
                                viewModel.amountText = displayAmountResult
                                calculatorExpression = ""
                            }
                            withAnimation(.easeInOut(duration: 0.32)) { showCustomKeyboard = false }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .animation(.easeInOut(duration: 0.32), value: showCustomKeyboard)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onChange(of: viewModel.didSucceed) { _, ok in
            if ok {
                dismiss()
                onSuccess?()
            }
        }
    }

    private var sheetContent: some View {
        VStack(spacing: 0) {
            handleBar
            headerActions
            amountSection
            typeToggle
            categorySection
            formFields
            Spacer(minLength: 16)
            actionBar
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 40)
        .background(
            RoundedRectangle(cornerRadius: 40)
                .fill(Color.white.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 40)
                        .stroke(Color.white.opacity(0.7), lineWidth: 1)
                )
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private var handleBar: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.black.opacity(0.1))
            .frame(width: 36, height: 5)
            .padding(.bottom, 24)
    }

    private var headerActions: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(OnboardingDesign.textSecondary)
                    .frame(width: 40, height: 40)
            }
            Spacer()
            Text(viewModel.sheetTitle)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(OnboardingDesign.textPrimary)
            Spacer()
            Color.clear
                .frame(width: 40, height: 40)
        }
        .padding(.bottom, 20)
    }

    private var amountSection: some View {
        VStack(spacing: 8) {
            Menu {
                ForEach(AddTransactionViewModel.currencies, id: \.self) { code in
                    Button("\(code) ($)") { viewModel.selectedCurrency = code }
                }
            } label: {
                Text("\(viewModel.selectedCurrency) ($)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(OnboardingDesign.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white, lineWidth: 1))
            }
            .disabled(viewModel.isEditMode)

            if viewModel.isEditMode {
                TextField("0.00", text: $viewModel.amountText)
                    .font(.system(size: 56, weight: .light))
                    .tracking(-2)
                    .foregroundColor(OnboardingDesign.textPrimary)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.32)) { showCustomKeyboard = true }
                } label: {
                    VStack(spacing: 4) {
                        if showCustomKeyboard && !calculatorExpression.isEmpty {
                            Text(displayAmountResult)
                                .font(.system(size: 56, weight: .light))
                                .tracking(-2)
                                .foregroundColor(OnboardingDesign.textPrimary)
                            Text(calculatorExpression)
                                .font(.system(size: 15))
                                .foregroundColor(OnboardingDesign.textSecondary)
                        } else {
                            Text(viewModel.amountText.isEmpty ? "0.00" : viewModel.amountText)
                                .font(.system(size: 56, weight: .light))
                                .tracking(-2)
                                .foregroundColor(OnboardingDesign.textPrimary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 30)
    }

    private var typeToggle: some View {
        HStack(spacing: 0) {
            ForEach(["expense", "income"], id: \.self) { type in
                Button {
                    viewModel.transactionType = type
                } label: {
                    Text(type == "expense" ? "Expense" : "Income")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(viewModel.transactionType == type ? OnboardingDesign.textPrimary : OnboardingDesign.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 11)
                                .fill(viewModel.transactionType == type ? Color.white : Color.clear)
                                .shadow(color: viewModel.transactionType == type ? Color.black.opacity(0.05) : .clear, radius: 4, x: 0, y: 2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.bottom, 24)
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CATEGORY")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(OnboardingDesign.textTertiary)
                .padding(.leading, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(viewModel.lastUsedCategoryIds, id: \.self) { catId in
                    categoryPill(categoryId: catId, isOther: false)
                }
                categoryPill(categoryId: "other", isOther: true)
            }
        }
        .sheet(isPresented: $showCategoriesSheet) {
            CategoriesSheetView(
                onSelect: { catId, subId in
                    viewModel.selectCategory(categoryId: catId, subcategoryId: subId)
                    showCategoriesSheet = false
                },
                initialCategoryId: viewModel.selectedCategoryId,
                initialSubcategoryId: viewModel.selectedSubcategoryId,
                showHandle: false
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .padding(.bottom, 24)
    }

    private func categoryPill(categoryId: String, isOther: Bool) -> some View {
        let cat = CategoryStore.byId(categoryId)
        let displayName = quickPickLabel(for: categoryId)
        let isSelected: Bool = {
            if isOther { return viewModel.selectedCategoryId == "other" && viewModel.selectedSubcategoryId == nil }
            return viewModel.selectedCategoryId == categoryId && viewModel.selectedSubcategoryId == nil
        }()

        return Button {
            if isOther {
                showCategoriesSheet = true
            } else {
                viewModel.selectCategory(categoryId: categoryId, subcategoryId: nil)
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 32, height: 32)
                    Image(systemName: iconName(for: categoryId))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isSelected ? (cat?.color ?? OnboardingDesign.accentGreen) : OnboardingDesign.textSecondary)
                }
                Text(displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(OnboardingDesign.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? OnboardingDesign.accentGreen : Color.white.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func quickPickLabel(for categoryId: String) -> String {
        switch categoryId {
        case "food": return "Food"
        case "transport": return "Travel"
        case "housing": return "Home"
        case "other": return "Other"
        default: return CategoryStore.byId(categoryId)?.name ?? categoryId.capitalized
        }
    }

    private func iconName(for categoryId: String) -> String {
        switch categoryId {
        case "food": return "cart.fill"
        case "transport": return "car.fill"
        case "housing": return "house.fill"
        case "other": return "plus.circle.fill"
        default: return "tag.fill"
        }
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    showDatePicker = true
                } label: {
                    inputRowDisplay(icon: "calendar", text: dateFormatted)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                Button {
                    showTimePicker = true
                } label: {
                    inputRowDisplay(icon: "clock", text: timeFormatted)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }

            inputRow(icon: "pencil", placeholder: "Add a note...", text: $viewModel.note)
        }
        .sheet(isPresented: $showDatePicker) {
            DateTimePickerSheetView(dateTime: $viewModel.dateTime, components: .date)
        }
        .sheet(isPresented: $showTimePicker) {
            DateTimePickerSheetView(dateTime: $viewModel.dateTime, components: .hourAndMinute)
        }
        .padding(.bottom, 24)
    }

    private var dateFormatted: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: viewModel.dateTime)
    }

    private var timeFormatted: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: viewModel.dateTime)
    }

    private func inputRow(icon: String, placeholder: String = "", text: Binding<String>, action: @escaping () -> Void = {}) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(OnboardingDesign.textTertiary)
            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .foregroundColor(OnboardingDesign.textPrimary)
        }
        .padding(16)
        .background(Color.white.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.4), lineWidth: 1))
    }

    private func inputRowDisplay(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(OnboardingDesign.textTertiary)
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(OnboardingDesign.textPrimary)
            Spacer()
        }
        .padding(16)
        .background(Color.white.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.4), lineWidth: 1))
    }

    private var actionBar: some View {
        VStack(spacing: 12) {
            if let err = viewModel.errorMessage {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
            }
            Button {
                Task { await viewModel.submit() }
            } label: {
                Text(viewModel.primaryButtonTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(OnboardingDesign.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 10)
            }
            .disabled(viewModel.isSubmitting || viewModel.amountText.isEmpty)
            .opacity(viewModel.isSubmitting ? 0.7 : 1)
        }
        .padding(.top, 20)
    }
}

// MARK: - Date/Time picker sheet

private struct DateTimePickerSheetView: View {
    @Binding var dateTime: Date
    let components: DatePickerComponents
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker("", selection: $dateTime, displayedComponents: components)
                .labelsHidden()
                .datePickerStyle(.wheel)
                .padding()
            Spacer()
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

#Preview("New") {
    AddTransactionView()
}

#Preview("Edit") {
    AddTransactionView(transaction: Transaction(
        id: "1", type: "expense", amountOriginal: 12.99, currencyOriginal: "USD",
        amountBase: 12.99, baseCurrency: "USD", merchant: "Coffee", title: "Morning coffee",
        transactionDate: "2025-03-10", transactionTime: "09:30", category: "food", subcategory: nil,
        isSubscription: false, sourceType: "manual", createdAt: nil, updatedAt: nil
    ))
}
