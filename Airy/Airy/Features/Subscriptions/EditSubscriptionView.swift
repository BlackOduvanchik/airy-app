//
//  EditSubscriptionView.swift
//  Airy
//
//  Sheet for editing a subscription: icon/color branding, reminder, cost optimization, details.
//

import SwiftUI

struct EditSubscriptionView: View {
    let subscription: Subscription
    var onSave: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var vm: EditSubscriptionViewModel
    @State private var showIconLibrary = false
    @State private var selectedIconFromLibrary = ""
    @State private var showCancelConfirm = false
    @State private var showEditDetails = false

    init(subscription: Subscription, onSave: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        self.subscription = subscription
        self.onSave = onSave
        self.onCancel = onCancel
        self._vm = State(initialValue: EditSubscriptionViewModel(subscription: subscription))
        self._selectedIconFromLibrary = State(initialValue: subscription.iconLetter ?? String(subscription.merchant.prefix(1)).uppercased())
    }

    var body: some View {
        NavigationStack {
            sheetContent
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("EDIT SUBSCRIPTION")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(0.5)
                            .foregroundColor(OnboardingDesign.textTertiary)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            vm.save()
                            onSave?()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }

    private var sheetContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                heroSection
                if vm.isMonthly {
                    costOptimizationSection
                }
                iconBrandingSection
                reminderSection
                subscriptionDetailsSection
                cancelButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color(red: 0.956, green: 0.969, blue: 0.961).ignoresSafeArea())
        .sheet(isPresented: $showIconLibrary) {
            IconLibraryView(selectedIcon: $selectedIconFromLibrary, onDismiss: {
                guard !selectedIconFromLibrary.isEmpty else { return }
                if SFSymbolsCatalog.isLetter(selectedIconFromLibrary) {
                    vm.iconLetter = SFSymbolsCatalog.letterValue(selectedIconFromLibrary)
                } else {
                    // SF Symbol — store as-is
                    vm.iconLetter = selectedIconFromLibrary
                }
            })
        }
        .confirmationDialog("Delete Subscription?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("Delete Subscription", role: .destructive) {
                vm.cancelSubscription()
                onCancel?()
                dismiss()
            }
        } message: {
            Text("This will remove it from your subscriptions list. The transaction will remain in your history.")
        }
    }


    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 22)
                .fill(vm.iconColor)
                .frame(width: 80, height: 80)
                .overlay(
                    Group {
                        if vm.iconIsSFSymbol {
                            Image(systemName: vm.iconLetter)
                                .font(.system(size: 32, weight: .bold))
                        } else {
                            Text(vm.iconLetter)
                                .font(.system(size: 36, weight: .heavy))
                        }
                    }
                    .foregroundColor(.white)
                )
                .shadow(color: vm.iconColor.opacity(0.2), radius: 12, x: 0, y: 6)

            VStack(spacing: 4) {
                Text(vm.displayName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(OnboardingDesign.textPrimary)
                Text("\(vm.formattedMonthlyAmount)/mo \u{00B7} \(vm.billDayString)")
                    .font(.system(size: 14))
                    .foregroundColor(OnboardingDesign.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    // MARK: - Cost Optimization

    private var costOptimizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Cost Optimization")
            glassPanel {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundColor(OnboardingDesign.accentBlue)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(vm.formattedAnnualPrice)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(OnboardingDesign.textPrimary)
                        Text(vm.formattedMonthlySavings)
                            .font(.system(size: 14))
                            .foregroundColor(OnboardingDesign.accentGreen)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
    }

    // MARK: - Icon & Branding

    private var iconBrandingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Icon & Branding")
            glassPanel {
                VStack(spacing: 0) {
                    iconGrid
                        .padding(16)
                    Rectangle()
                        .fill(OnboardingDesign.glassBorder)
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                    colorRow
                        .padding(16)
                }
            }
        }
    }

    private var iconGrid: some View {
        let quickIcons = [vm.iconLetter] + vm.randomLetters
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
            ForEach(quickIcons, id: \.self) { icon in
                iconCell(icon, isSelected: vm.iconLetter == icon)
            }
            plusButton
        }
    }

    private func iconCell(_ icon: String, isSelected: Bool) -> some View {
        let isSF = icon.count > 1
        return Button {
            vm.iconLetter = icon
        } label: {
            Group {
                if isSF {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                } else {
                    Text(icon)
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .foregroundColor(isSelected ? OnboardingDesign.textPrimary : OnboardingDesign.textSecondary)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? OnboardingDesign.textPrimary : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var plusButton: some View {
        Button {
            selectedIconFromLibrary = vm.iconIsSFSymbol ? vm.iconLetter : "letter:\(vm.iconLetter)"
            showIconLibrary = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(OnboardingDesign.textTertiary)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.3))
                )
        }
        .buttonStyle(.plain)
    }

    private var colorRow: some View {
        let colors = EditSubscriptionViewModel.availableColors
        let rows = [colors.prefix(8), colors.suffix(from: 8)]
        return VStack(spacing: 10) {
            ForEach(0..<rows.count, id: \.self) { rowIdx in
                HStack(spacing: 0) {
                    ForEach(Array(rows[rowIdx]), id: \.self) { hex in
                        Spacer()
                        colorSwatch(hex)
                        Spacer()
                    }
                }
            }
        }
    }

    private func colorSwatch(_ hex: String) -> some View {
        let isActive = vm.selectedColorHex.uppercased() == hex.uppercased()
        let color = Color(hex: hex) ?? .gray
        return Button {
            vm.selectedColorHex = hex
        } label: {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(color: color.opacity(0.3), radius: 4, x: 0, y: 2)
                .scaleEffect(isActive ? 1.2 : 1.0)
                .overlay(
                    isActive ?
                        Circle()
                            .stroke(OnboardingDesign.textPrimary, lineWidth: 2)
                            .scaleEffect(1.35)
                        : nil
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reminder

    private var reminderSection: some View {
        glassPanel {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(vm.reminderEnabled ? OnboardingDesign.accentGreen.opacity(0.15) : Color.white.opacity(0.5))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "bell.fill")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(vm.reminderEnabled ? OnboardingDesign.accentGreen : OnboardingDesign.textSecondary)
                    )
                Text("Remind me 2 days before")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(OnboardingDesign.textPrimary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { vm.reminderEnabled },
                    set: { newValue in
                        vm.reminderEnabled = newValue
                        if newValue {
                            vm.scheduleReminder()
                        } else {
                            vm.cancelReminder()
                        }
                    }
                ))
                .labelsHidden()
                .tint(OnboardingDesign.accentGreen)
            }
            .padding(14)
        }
    }

    // MARK: - Subscription Details

    private var subscriptionDetailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Subscription Details")
            glassPanel {
                Button {
                    showEditDetails = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(CategoryStore.byId(subscription.categoryId ?? "")?.name ?? subscription.categoryId?.capitalized ?? "Uncategorized")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(OnboardingDesign.textPrimary)
                            Text("\(subscription.interval.capitalized) \u{00B7} \(vm.billDayString)")
                                .font(.system(size: 13))
                                .foregroundColor(OnboardingDesign.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(OnboardingDesign.textTertiary)
                    }
                    .padding(16)
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showEditDetails) {
            if let tx = vm.templateTransaction() {
                AddTransactionView(transaction: tx, onSuccess: {
                    onSave?()
                })
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
        }
    }

    // MARK: - Cancel

    private var cancelButton: some View {
        Button {
            showCancelConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                Text("Delete Subscription")
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
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(OnboardingDesign.textTertiary)
            .tracking(0.5)
            .padding(.leading, 4)
    }

    private func glassPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .overlay(OnboardingDesign.glassBg.opacity(0.5).allowsHitTesting(false))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
            )
            .shadow(color: OnboardingDesign.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
    }
}
