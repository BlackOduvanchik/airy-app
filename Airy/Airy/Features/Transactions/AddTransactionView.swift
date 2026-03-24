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
    /// Frozen quick pick order captured when sheet opened. If nil, uses LastUsedCategoriesStore at init.
    var initialQuickPickOrder: [String]? = nil
    /// Called after a successful save (e.g. to pop parent when editing).
    var onSuccess: (() -> Void)?
    /// Pending transaction from Review screen; when set, uses same UI but confirms with overrides.
    var pendingTransaction: PendingTransaction?
    var pendingRememberMerchant: Bool = true
    var onConfirmPending: ((ConfirmPendingOverrides, Bool) -> Void)?
    var onCancelPending: (() -> Void)?
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: AddTransactionViewModel
    @State private var showCustomKeyboard = false
    @State private var calculatorExpression = ""
    @State private var showCategoriesSheet = false
    @State private var showCurrencySheet = false
    @State private var rememberRule: Bool = true
    @State private var isDeleting = false
    @State private var frozenQuickPickOrder: [String] = []
    @State private var pickedFromOthersThisSession: String? = nil
    @State private var didAppear = false
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

    init(pendingTransaction: PendingTransaction, rememberMerchant: Bool, matchedSubscriptionInterval: String? = nil, onConfirm: @escaping (ConfirmPendingOverrides, Bool) -> Void, onCancel: @escaping () -> Void, initialQuickPickOrder: [String]? = nil) {
        self.transaction = nil
        self.initialType = nil
        self.initialQuickPickOrder = initialQuickPickOrder
        self.onSuccess = nil
        self.pendingTransaction = pendingTransaction
        self.pendingRememberMerchant = rememberMerchant
        self.onConfirmPending = onConfirm
        self.onCancelPending = onCancel
        let payload = pendingTransaction.decodedPayload
        _viewModel = State(initialValue: AddTransactionViewModel(existing: nil, initialType: nil, fromPayload: payload, prefillSubscriptionInterval: matchedSubscriptionInterval))
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

                ZStack(alignment: .top) {
                    sheetContent

                    if showCustomKeyboard {
                        VStack {
                            Spacer()
                            AmountKeyboardView(
                                expression: $calculatorExpression,
                                amountText: $viewModel.amountText,
                                transactionType: $viewModel.transactionType,
                                selectedCurrency: $viewModel.selectedCurrency,
                                onDismiss: {
                                    print("[Tap] AddTransaction → Keyboard dismiss")
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
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.94, anchor: .bottom))
                        )
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !viewModel.isEditMode {
                        Button {
                            showCurrencySheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Text(viewModel.selectedCurrency)
                                    .font(.system(size: 14, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(theme.textSecondary)
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(viewModel.sheetTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(theme.textTertiary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if viewModel.isPendingEditMode {
                            onCancelPending?()
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(theme.textSecondary)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onChange(of: viewModel.didSucceed) { _, ok in
            if ok {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
                onSuccess?()
            }
        }
        .onAppear {
            guard !didAppear else { return }
            didAppear = true
            print("[Nav] AddTransaction (edit=\(viewModel.isEditMode) pending=\(viewModel.isPendingEditMode))")
            guard !viewModel.isEditMode, !viewModel.isPendingEditMode else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                    showCustomKeyboard = true
                }
            }
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
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.never)
            actionBar
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 40)
        .ignoresSafeArea(edges: .bottom)
    }


    private var amountSection: some View {
        VStack(spacing: 4) {
            Button {
                print("[Tap] AddTransaction → Amount input (open keyboard)")
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { showCustomKeyboard = true }
            } label: {
                VStack(spacing: 4) {
                    if showCustomKeyboard && !calculatorExpression.isEmpty {
                        Text(displayAmountResult)
                            .font(.system(size: 56, weight: .light))
                            .tracking(-2)
                            .foregroundColor(theme.textPrimary)
                        Text(calculatorExpression)
                            .font(.system(size: 15))
                            .foregroundColor(theme.textSecondary)
                    } else {
                        Text(viewModel.amountText.isEmpty ? "0.00" : viewModel.amountText)
                            .font(.system(size: 56, weight: .light))
                            .tracking(-2)
                            .foregroundColor(theme.textPrimary)
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
                    print("[Tap] AddTransaction → Type '\(type)'")
                    viewModel.transactionType = type
                } label: {
                    Text(type == "expense" ? L("common_expense") : L("common_income"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(viewModel.transactionType == type ? theme.textPrimary : theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 11)
                                .fill(viewModel.transactionType == type ? Color.white.opacity(theme.isDark ? 0.15 : 1) : Color.clear)
                                .shadow(color: viewModel.transactionType == type ? Color.black.opacity(0.05) : .clear, radius: 4, x: 0, y: 2)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(theme.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
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
                    .fill(viewModel.isSubscription ? theme.accentGreen.opacity(0.15) : Color.white.opacity(theme.isDark ? 0.08 : 0.5))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(theme.textSecondary)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("addtx_monthly_sub"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                    Text(L("addtx_recurring_hint"))
                        .font(.system(size: 12))
                        .foregroundColor(theme.textTertiary)
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
                    .tint(theme.accentGreen)
            }
            .padding(14)
            .background(viewModel.isSubscription ? Color.white.opacity(theme.isDark ? 0.10 : 0.55) : Color.white.opacity(theme.isDark ? 0.06 : 0.3))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(viewModel.isSubscription ? theme.accentGreen.opacity(0.35) : Color.white.opacity(theme.isDark ? 0.08 : 0.4), lineWidth: 1)
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
                            Text(interval == "weekly" ? L("addtx_weekly") : interval == "monthly" ? L("addtx_monthly") : L("addtx_yearly"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(viewModel.subscriptionInterval == interval ? theme.textPrimary : theme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(viewModel.subscriptionInterval == interval ? Color.white.opacity(theme.isDark ? 0.15 : 1) : Color.white.opacity(theme.isDark ? 0.06 : 0.3))
                                        .shadow(color: viewModel.subscriptionInterval == interval ? Color.black.opacity(0.05) : .clear, radius: 4, x: 0, y: 2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(viewModel.subscriptionInterval == interval ? theme.accentGreen.opacity(0.3) : Color.white.opacity(theme.isDark ? 0.08 : 0.4), lineWidth: 1)
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
            Text(L("addtx_category"))
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(theme.textTertiary)
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
                    categoryPill(categoryId: catId, isOther: false)
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
            .themed(theme)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(theme.bgTop)
        }
        .sheet(isPresented: $showCurrencySheet) {
            TransactionCurrencyPickerSheet(
                selectedCurrency: $viewModel.selectedCurrency
            )
            .themed(theme)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(theme.bgTop)
        }
        .padding(.bottom, 24)
    }

    private func categoryPill(categoryId: String, isOther: Bool) -> some View {
        let displayName = quickPickLabel(for: categoryId)
        let icon = CategoryIconHelper.iconName(categoryId: categoryId)
        let color = CategoryIconHelper.color(categoryId: categoryId)
        let isSelected: Bool = {
            if isOther { return viewModel.selectedCategoryId == "other" }
            return viewModel.selectedCategoryId == categoryId
        }()

        return Button {
            let label = CategoryIconHelper.displayName(categoryId: categoryId)
            print("[Tap] AddTransaction → Category '\(label)'")
            if isOther {
                showCategoriesSheet = true
            } else if isSelected {
                showCategoriesSheet = true
            } else {
                viewModel.selectCategory(categoryId: categoryId, subcategoryId: nil)
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(theme.isDark ? 0.08 : 0.5))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(color)
                }
                Text(displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isSelected ? Color.white.opacity(theme.isDark ? 0.15 : 1) : Color.white.opacity(theme.isDark ? 0.06 : 0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? theme.accentGreen : Color.white.opacity(theme.isDark ? 0.08 : 0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func quickPickLabel(for categoryId: String) -> String {
        if viewModel.selectedCategoryId == categoryId,
           let subId = viewModel.selectedSubcategoryId,
           let subName = SubcategoryStore.forParent(categoryId).first(where: { $0.id == subId })?.name {
            return subName
        }
        return CategoryStore.byId(categoryId)?.name ?? CategoryIconHelper.displayName(categoryId: categoryId)
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            if pendingTransaction != nil {
                inputRow(icon: "building.2", placeholder: L("addtx_merchant"), text: Binding(
                    get: { viewModel.merchant },
                    set: { viewModel.merchant = $0 }
                ))
            }
            HStack(spacing: 12) {
                IsolatedDatePicker(dateTime: $viewModel.dateTime, accentColor: theme.accentGreen, isDark: theme.isDark)

                IsolatedTimePicker(dateTime: $viewModel.dateTime, accentColor: theme.accentGreen, isDark: theme.isDark)
            }

            noteInputRow
        }
        .padding(.bottom, 24)
    }

    private var noteInputRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "pencil")
                .font(.system(size: 18))
                .foregroundColor(theme.textTertiary)
            TextField("", text: $viewModel.note, prompt: Text(L("addtx_note")).foregroundStyle(theme.textTertiary))
                .font(.system(size: 15))
                .foregroundColor(theme.textPrimary)
                .focused($isNoteFocused)
        }
        .padding(16)
        .contentShape(Rectangle())
        .background(Color.white.opacity(theme.isDark ? 0.06 : 0.3))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(theme.isDark ? 0.08 : 0.4), lineWidth: 1))
        .id("noteInput")
    }

    private func inputRow(icon: String, placeholder: String = "", text: Binding<String>, action: @escaping () -> Void = {}) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(theme.textTertiary)
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(theme.textTertiary))
                .font(.system(size: 15))
                .foregroundColor(theme.textPrimary)
        }
        .padding(16)
        .background(Color.white.opacity(theme.isDark ? 0.06 : 0.3))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(theme.isDark ? 0.08 : 0.4), lineWidth: 1))
    }

    private var rememberRuleRow: some View {
        HStack(spacing: 12) {
            Text(L("addtx_remember_rule", viewModel.merchant.isEmpty ? L("addtx_this_merchant") : viewModel.merchant))
                .font(.system(size: 12))
                .foregroundColor(theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Toggle("", isOn: $rememberRule)
                .labelsHidden()
                .tint(theme.accentGreen)
                .fixedSize()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
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
                print("[Tap] AddTransaction → Save")
                if viewModel.isPendingEditMode, let onConfirm = onConfirmPending {
                    guard let amt = viewModel.amount, amt > 0 else {
                        viewModel.errorMessage = L("addtx_invalid_amount")
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
                    .background(theme.isDark ? Color.white.opacity(0.15) : theme.textPrimary)
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
                Text(L("addtx_delete"))
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(theme.textDanger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(theme.textDanger.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(theme.textDanger.opacity(0.15), lineWidth: 1)
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

// MARK: - Currency picker sheet

struct TransactionCurrencyPickerSheet: View {
    @Binding var selectedCurrency: String
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeProvider.self) private var theme
    @State private var searchText = ""

    private var filteredCurrencies: [(code: String, name: String, symbol: String)] {
        guard !searchText.isEmpty else { return AddTransactionViewModel.currencies }
        let q = searchText.lowercased()
        return AddTransactionViewModel.currencies.filter {
            $0.code.lowercased().contains(q) || $0.name.lowercased().contains(q) || $0.symbol.contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search
            ZStack(alignment: .leading) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(theme.textTertiary)
                    .padding(.leading, 14)
                TextField("", text: $searchText, prompt: Text(L("currency_search")).foregroundStyle(theme.textTertiary))
                    .font(.system(size: 15))
                    .foregroundColor(theme.textPrimary)
                    .padding(.leading, 40)
                    .padding(.trailing, 14)
                    .padding(.vertical, 12)
            }
            .background(Color.white.opacity(theme.isDark ? 0.05 : 0.3))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(theme.glassBorder, lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(filteredCurrencies, id: \.code) { currency in
                        let isSelected = currency.code == selectedCurrency
                        Button {
                            selectedCurrency = currency.code
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Text(currency.symbol)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(isSelected ? .white : theme.accentGreen)
                                    .frame(width: 34, height: 34)
                                    .background(isSelected ? theme.accentGreen : theme.accentGreen.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(currency.code)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(theme.textPrimary)
                                    Text(currency.name)
                                        .font(.system(size: 12))
                                        .foregroundColor(theme.textTertiary)
                                }
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(theme.accentGreen)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(isSelected ? Color.white.opacity(theme.isDark ? 0.12 : 0.9) : Color.white.opacity(theme.isDark ? 0.04 : 0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(isSelected ? theme.accentGreen.opacity(0.3) : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
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
                Button(L("common_done")) { dismiss() }
            }
        }
    }
}

// MARK: - Isolated pickers (prevents @Observable re-renders from flooding haptic rate-limit)

private struct IsolatedTimePicker: View {
    @Binding var dateTime: Date
    let accentColor: Color
    let isDark: Bool

    @State private var local: Date = .now

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
            DatePicker("", selection: $local, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(isDark ? 0.06 : 0.3))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(isDark ? 0.08 : 0.4), lineWidth: 1))
        .onAppear { local = dateTime }
        .task(id: local) {
            try? await Task.sleep(for: .milliseconds(400))
            dateTime = local
        }
    }
}

private struct IsolatedDatePicker: View {
    @Binding var dateTime: Date
    let accentColor: Color
    let isDark: Bool

    @State private var local: Date = .now

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
            DatePicker("", selection: $local, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(isDark ? 0.06 : 0.3))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(isDark ? 0.08 : 0.4), lineWidth: 1))
        .onAppear { local = dateTime }
        .task(id: local) {
            try? await Task.sleep(for: .milliseconds(400))
            dateTime = local
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
