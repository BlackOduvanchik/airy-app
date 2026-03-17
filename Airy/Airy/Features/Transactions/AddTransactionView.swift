//
//  AddTransactionView.swift
//  Airy
//
//  Manual add or edit transaction: sheet design with amount, type toggle, categories, date/time, note.
//

import SwiftUI

private struct TimeButtonAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct DateButtonAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct AddTransactionView: View {
    var transaction: Transaction?
    /// Initial transaction type when creating new (e.g. "income" for Add Income flow).
    var initialType: String?
    /// Frozen quick pick order captured when sheet opened. If nil, uses LastUsedCategoriesStore at init.
    var initialQuickPickOrder: [String]? = nil
    /// Called after a successful save (e.g. to pop parent when editing).
    var onSuccess: (() -> Void)?
    /// Pending transaction from Review screen; when set, uses same UI but confirms with overrides.
    var pendingTransaction: PendingTransaction?
    var pendingRememberMerchant: Bool = true
    var onConfirmPending: ((ConfirmPendingOverrides, Bool) -> Void)?
    var onCancelPending: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: AddTransactionViewModel
    @State private var showDatePicker = false
    @State private var showTimePicker = false
    @State private var showCustomKeyboard = false
    @State private var calculatorExpression = ""
    @State private var showCategoriesSheet = false
    @State private var rememberRule: Bool = true
    @State private var isDeleting = false
    @State private var frozenQuickPickOrder: [String] = []
    @State private var pickedFromOthersThisSession: String? = nil
    @FocusState private var isNoteFocused: Bool

    init(transaction: Transaction? = nil, initialType: String? = nil, initialQuickPickOrder: [String]? = nil, onSuccess: (() -> Void)? = nil) {
        self.transaction = transaction
        self.initialType = initialType
        self.initialQuickPickOrder = initialQuickPickOrder
        self.onSuccess = onSuccess
        self.pendingTransaction = nil
        self.pendingRememberMerchant = true
        self.onConfirmPending = nil
        self.onCancelPending = nil
        _viewModel = State(initialValue: AddTransactionViewModel(existing: transaction, initialType: initialType))
        _frozenQuickPickOrder = State(initialValue: (initialQuickPickOrder?.isEmpty == false) ? initialQuickPickOrder! : LastUsedCategoriesStore.forQuickPick())
    }

    init(pendingTransaction: PendingTransaction, rememberMerchant: Bool, onConfirm: @escaping (ConfirmPendingOverrides, Bool) -> Void, onCancel: @escaping () -> Void, initialQuickPickOrder: [String]? = nil) {
        self.transaction = nil
        self.initialType = nil
        self.initialQuickPickOrder = initialQuickPickOrder
        self.onSuccess = nil
        self.pendingTransaction = pendingTransaction
        self.pendingRememberMerchant = rememberMerchant
        self.onConfirmPending = onConfirm
        self.onCancelPending = onCancel
        let payload = pendingTransaction.decodedPayload
        _viewModel = State(initialValue: AddTransactionViewModel(existing: nil, initialType: nil, fromPayload: payload))
        _rememberRule = State(initialValue: rememberMerchant)
        _frozenQuickPickOrder = State(initialValue: (initialQuickPickOrder?.isEmpty == false) ? initialQuickPickOrder! : LastUsedCategoriesStore.forQuickPick())
    }

    private var displayAmountResult: String {
        String(format: "%.2f", evaluateAmountExpression(calculatorExpression) ?? 0)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                OnboardingGradientBackground()
                    .ignoresSafeArea()

                sheetContent

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
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                                showCustomKeyboard = false
                            }
                        }
                    )
                }
                .ignoresSafeArea(edges: .bottom)
                .opacity(showCustomKeyboard ? 1 : 0)
                .scaleEffect(showCustomKeyboard ? 1 : 0.94, anchor: .bottom)
                .allowsHitTesting(showCustomKeyboard)
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: showCustomKeyboard)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.sheetTitle != "New Entry" {
                        Text(viewModel.sheetTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(0.5)
                            .foregroundColor(OnboardingDesign.textTertiary)
                    } else {
                        Menu {
                            ForEach(AddTransactionViewModel.currencies, id: \.self) { code in
                                Button("\(code) ($)") { viewModel.selectedCurrency = code }
                            }
                        } label: {
                            Text("\(viewModel.selectedCurrency) ($)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(OnboardingDesign.textSecondary)
                        }
                        .disabled(viewModel.isEditMode)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if pendingTransaction != nil {
                            onCancelPending?()
                            dismiss()
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled(showTimePicker || showDatePicker)
        .sensoryFeedback(.success, trigger: viewModel.didSucceed) { _, new in new }
        .onChange(of: viewModel.didSucceed) { _, ok in
            if ok {
                dismiss()
                onSuccess?()
            }
        }
        .onAppear {
            guard !viewModel.isEditMode, !viewModel.isPendingEditMode else { return }
            showCustomKeyboard = true
        }
    }

    private var sheetContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        amountSection
                        typeToggle
                    }
                    subscriptionSection
                    categorySection
                    formFields
                    if pendingTransaction != nil {
                        rememberRuleRow
                    }
                    Spacer(minLength: 24)
                }
                .offset(y: viewModel.isSubscription && isNoteFocused ? -56 : 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: viewModel.isSubscription && isNoteFocused)
            }
            .scrollDismissesKeyboard(.interactively)
            actionBar
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 40)
        .ignoresSafeArea(edges: .bottom)
        .overlay {
            if showTimePicker || showDatePicker {
                Color.black.opacity(0.001)
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showTimePicker = false
                            showDatePicker = false
                        }
                    }
            }
        }
        .overlayPreferenceValue(TimeButtonAnchorKey.self) { anchor in
            if showTimePicker, let anchor {
                GeometryReader { geo in
                    let rect = geo[anchor]
                    TimePickerPopoverView(dateTime: $viewModel.dateTime) {
                        withAnimation(.easeOut(duration: 0.2)) { showTimePicker = false }
                    }
                    .position(x: rect.minX + 70, y: rect.minY - 90)
                }
                .allowsHitTesting(true)
            }
        }
        .overlayPreferenceValue(DateButtonAnchorKey.self) { anchor in
            if showDatePicker, let anchor {
                GeometryReader { geo in
                    let rect = geo[anchor]
                    DatePickerPopoverView(dateTime: $viewModel.dateTime) {
                        withAnimation(.easeOut(duration: 0.2)) { showDatePicker = false }
                    }
                    .position(x: rect.midX, y: rect.minY - 90)
                }
                .allowsHitTesting(true)
            }
        }
    }


    private var amountSection: some View {
        VStack(spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { showCustomKeyboard = true }
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
        .padding(.bottom, 20)
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
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 11)
                                .fill(viewModel.transactionType == type ? Color.white : Color.clear)
                                .shadow(color: viewModel.transactionType == type ? Color.black.opacity(0.05) : .clear, radius: 4, x: 0, y: 2)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.bottom, 16)
    }

    private var subscriptionToggleAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.8)
    }

    private var subscriptionSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(viewModel.isSubscription ? OnboardingDesign.accentGreen.opacity(0.15) : Color.white.opacity(0.5))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(OnboardingDesign.textSecondary)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monthly Subscription")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textPrimary)
                    Text("Track as recurring payment")
                        .font(.system(size: 12))
                        .foregroundColor(OnboardingDesign.textTertiary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.isSubscription },
                    set: { newValue in
                        withAnimation(subscriptionToggleAnimation) {
                            viewModel.isSubscription = newValue
                        }
                    }
                ))
                    .labelsHidden()
                    .tint(OnboardingDesign.accentGreen)
            }
            .padding(14)
            .background(viewModel.isSubscription ? Color.white.opacity(0.55) : Color.white.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(viewModel.isSubscription ? OnboardingDesign.accentGreen.opacity(0.35) : Color.white.opacity(0.4), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(subscriptionToggleAnimation) {
                    viewModel.isSubscription.toggle()
                }
            }

            if viewModel.isSubscription {
                HStack(spacing: 6) {
                    ForEach(["weekly", "monthly", "yearly"], id: \.self) { interval in
                        Button {
                            viewModel.subscriptionInterval = interval
                        } label: {
                            Text(interval.capitalized)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(viewModel.subscriptionInterval == interval ? OnboardingDesign.textPrimary : OnboardingDesign.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(viewModel.subscriptionInterval == interval ? Color.white : Color.white.opacity(0.3))
                                        .shadow(color: viewModel.subscriptionInterval == interval ? Color.black.opacity(0.05) : .clear, radius: 4, x: 0, y: 2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(viewModel.subscriptionInterval == interval ? OnboardingDesign.accentGreen.opacity(0.3) : Color.white.opacity(0.4), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 8)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }
        }
        .animation(subscriptionToggleAnimation, value: viewModel.isSubscription)
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
                let displayedIds: [String] = {
                    if let picked = pickedFromOthersThisSession {
                        return [picked] + Array(frozenQuickPickOrder.filter { $0 != picked }.prefix(2))
                    }
                    if let sel = viewModel.selectedCategoryId, !frozenQuickPickOrder.contains(sel), sel != "other" {
                        return [sel] + Array(frozenQuickPickOrder.suffix(2))
                    }
                    return Array(frozenQuickPickOrder)
                }()
                ForEach(displayedIds, id: \.self) { catId in
                    if let sel = viewModel.selectedCategoryId, sel == catId,
                       let subId = viewModel.selectedSubcategoryId,
                       let sub = SubcategoryStore.forParent(catId).first(where: { $0.id == subId }) {
                        categoryPillForSubcategory(categoryId: catId, subcategoryName: sub.name)
                    } else if viewModel.selectedCategoryId == catId && viewModel.selectedSubcategoryId == nil {
                        categoryPillForCategory(categoryId: catId)
                    } else {
                        categoryPill(categoryId: catId, isOther: false)
                    }
                }
                categoryPill(categoryId: "other", isOther: true)
            }
            .padding(.horizontal, 1)
        }
        .sheet(isPresented: $showCategoriesSheet) {
            CategoriesSheetView(
                onSelect: { catId, subId in
                    viewModel.selectCategory(categoryId: catId, subcategoryId: subId)
                    if !frozenQuickPickOrder.contains(catId) && catId != "other" {
                        pickedFromOthersThisSession = catId
                    }
                    showCategoriesSheet = false
                },
                initialCategoryId: viewModel.selectedCategoryId,
                initialSubcategoryId: viewModel.selectedSubcategoryId,
                showHandle: false
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(red: 0.956, green: 0.969, blue: 0.961))
        }
        .padding(.bottom, 24)
    }

    private func categoryPillForCategory(categoryId: String) -> some View {
        let displayName = CategoryStore.byId(categoryId)?.name ?? quickPickLabel(for: categoryId)
        let icon = CategoryIconHelper.iconName(categoryId: categoryId)
        let color = CategoryIconHelper.color(categoryId: categoryId)
        return Button {
            showCategoriesSheet = true
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(color)
                }
                Text(displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(OnboardingDesign.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(OnboardingDesign.accentGreen, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func categoryPillForSubcategory(categoryId: String, subcategoryName: String) -> some View {
        let icon = CategoryIconHelper.iconName(categoryId: categoryId)
        let color = CategoryIconHelper.color(categoryId: categoryId)
        return Button {
            showCategoriesSheet = true
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(color)
                }
                Text(subcategoryName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(OnboardingDesign.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(OnboardingDesign.accentGreen, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func categoryPill(categoryId: String, isOther: Bool) -> some View {
        let displayName = quickPickLabel(for: categoryId)
        let icon = CategoryIconHelper.iconName(categoryId: categoryId)
        let color = CategoryIconHelper.color(categoryId: categoryId)
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
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(color)
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
        CategoryStore.byId(categoryId)?.name ?? CategoryIconHelper.displayName(categoryId: categoryId)
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            if pendingTransaction != nil {
                inputRow(icon: "building.2", placeholder: "Merchant", text: Binding(
                    get: { viewModel.merchant },
                    set: { viewModel.merchant = $0 }
                ))
            }
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showDatePicker = true }
                } label: {
                    inputRowDisplay(icon: "calendar", text: dateFormatted)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(showDatePicker ? OnboardingDesign.accentGreen : Color.clear, lineWidth: 1)
                )
                .anchorPreference(key: DateButtonAnchorKey.self, value: .bounds) { $0 }

                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showTimePicker = true }
                } label: {
                    inputRowDisplay(icon: "clock", text: timeFormatted)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(showTimePicker ? OnboardingDesign.accentGreen : Color.clear, lineWidth: 1)
                )
                .anchorPreference(key: TimeButtonAnchorKey.self, value: .bounds) { $0 }
            }

            noteInputRow
        }
        .padding(.bottom, 24)
    }

    private var noteInputRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "pencil")
                .font(.system(size: 18))
                .foregroundColor(OnboardingDesign.textTertiary)
            TextField("Add a note...", text: $viewModel.note)
                .font(.system(size: 15))
                .foregroundColor(OnboardingDesign.textPrimary)
                .focused($isNoteFocused)
        }
        .padding(16)
        .contentShape(Rectangle())
        .background(Color.white.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.4), lineWidth: 1))
        .id("noteInput")
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

    private var rememberRuleRow: some View {
        HStack {
            Text("Remember rule for \(viewModel.merchant.isEmpty ? "this merchant" : viewModel.merchant)")
                .font(.system(size: 12))
                .foregroundColor(OnboardingDesign.textTertiary)
            Spacer()
            Toggle("", isOn: $rememberRule)
                .labelsHidden()
                .tint(OnboardingDesign.accentGreen)
        }
        .padding(.vertical, 12)
        .padding(.bottom, 8)
    }

    private var actionBar: some View {
        VStack(spacing: 12) {
            if let err = viewModel.errorMessage {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
            }
            if viewModel.isEditMode, let tx = viewModel.existingTransaction {
                deleteButton(transactionId: tx.id)
            }
            Button {
                if viewModel.isPendingEditMode, let onConfirm = onConfirmPending {
                    guard let amt = viewModel.amount, amt > 0 else {
                        viewModel.errorMessage = "Enter a valid amount"
                        return
                    }
                    viewModel.errorMessage = nil
                    let overrides = viewModel.buildPendingOverrides()
                    onConfirm(overrides, rememberRule)
                    dismiss()
                } else {
                    Task { await viewModel.submit() }
                }
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
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private func deleteButton(transactionId: String) -> some View {
        Button {
            Task { await performDelete(id: transactionId) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                Text("Delete Transaction")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(OnboardingDesign.textDanger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(OnboardingDesign.textDanger.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(OnboardingDesign.textDanger.opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .disabled(isDeleting)
        .opacity(isDeleting ? 0.6 : 1)
        .buttonStyle(.plain)
    }

    private func performDelete(id: String) async {
        isDeleting = true
        defer { Task { @MainActor in isDeleting = false } }
        do {
            try LocalDataStore.shared.deleteTransaction(id: id)
            await MainActor.run {
                dismiss()
                onSuccess?()
            }
        } catch {
            await MainActor.run {
                viewModel.errorMessage = error.localizedDescription
            }
        }
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
        isSubscription: false, subscriptionInterval: nil, sourceType: "manual", createdAt: nil, updatedAt: nil
    ))
}
