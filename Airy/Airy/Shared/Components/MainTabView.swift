//
//  MainTabView.swift
//  Airy
//
//  Dashboard as default, bottom bar: Insights (left), FAB Add (center), Settings (right).
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .dashboard
    @State private var showAddSheet = false
    @State private var showAddTransaction = false
    @State private var addTransactionInitialType: String? = nil
    @State private var addSheetQuickPickOrder: [String] = []
    @State private var showGalleryPicker = false
    @State private var showLiveExtraction = false
    @State private var showPendingReview = false
    @State private var pasteNoImageAlert = false
    @State private var dashboardRefreshId = 0
    @State private var showAllTransactions = false
    @State private var showSubscriptions = false
    @State private var subscriptionsRequested = false
    @State private var cloudTapRequested = false
    @State private var navType: NavigationType = AppearanceStore.navigationType

    @Environment(ThemeProvider.self) private var theme

    private var importViewModel: ImportViewModel { ImportViewModel.shared }

    enum AppTab: Int {
        case dashboard = 0
        case insights = 1
        case settings = 2
        case bills = 3
        case add = 4
    }

    var body: some View {
        Group {
            if navType == .standardTab {
                standardTabBarLayout
            } else {
                customAiryBarLayout
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddActionSheetView(
                onExpense: {
                    print("[Tap] AddSheet → Expense")
                    showAddSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        addTransactionInitialType = nil
                        addSheetQuickPickOrder = LastUsedCategoriesStore.forQuickPick()
                        showAddTransaction = true
                    }
                },
                onIncome: {
                    print("[Tap] AddSheet → Income")
                    showAddSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        addTransactionInitialType = "income"
                        addSheetQuickPickOrder = LastUsedCategoriesStore.forQuickPick()
                        showAddTransaction = true
                    }
                },
                onPasteFromClipboard: {
                    print("[Tap] AddSheet → Paste from Clipboard")
                    showAddSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        if let image = UIPasteboard.general.image {
                            ImportViewModel.shared.enqueue([image])
                            showLiveExtraction = true
                        } else {
                            pasteNoImageAlert = true
                        }
                    }
                },
                onOpenGallery: {
                    print("[Tap] AddSheet → Open Gallery")
                    showAddSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        showGalleryPicker = true
                    }
                },
                onCancel: {
                    showAddSheet = false
                }
            )
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.hidden)
            .themed(theme)
        }
        .sheet(isPresented: $showAddTransaction) {
            AddTransactionView(initialType: addTransactionInitialType, initialQuickPickOrder: addSheetQuickPickOrder, onSuccess: {
                showAddTransaction = false
                addTransactionInitialType = nil
                dashboardRefreshId += 1
            })
            .themed(theme)
        }
        .fullScreenCover(isPresented: $showGalleryPicker) {
            GalleryPickerView(
                onImagesPicked: { images in
                    ImportViewModel.shared.enqueue(images)
                    showLiveExtraction = true
                },
                onCancel: { showGalleryPicker = false },
                onPickConfirmed: { showGalleryPicker = false }
            )
            .ignoresSafeArea()
            .themed(theme)
        }
        .fullScreenCover(isPresented: $showLiveExtraction) {
            AnalyzingTransactionsView(
                importViewModel: importViewModel,
                onConfirm: {
                    showLiveExtraction = false
                    if importViewModel.pendingCount > 0 {
                        showPendingReview = true
                    }
                },
                onCancel: {
                    showLiveExtraction = false
                }
            )
            .themed(theme)
        }
        .fullScreenCover(isPresented: $showPendingReview) {
            NavigationStack {
                PendingReviewView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L("common_done")) { showPendingReview = false }
                        }
                    }
            }
            .themed(theme)
        }
        .onChange(of: showPendingReview) { _, showing in
            if !showing { dashboardRefreshId += 1 }
        }
        .onChange(of: showGalleryPicker) { _, showing in
            if !showing { dashboardRefreshId += 1 }
        }
        .onChange(of: showLiveExtraction) { _, showing in
            if !showing { dashboardRefreshId += 1 }
        }
        .alert(L("add_no_image_title"), isPresented: $pasteNoImageAlert) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(L("add_no_image_message"))
        }
        .fullScreenCover(isPresented: $showSubscriptions) {
            SubscriptionsView(onDismiss: { showSubscriptions = false })
                .themed(theme)
        }
        .onChange(of: showSubscriptions) { _, showing in
            if !showing { dashboardRefreshId += 1 }
        }
        .onChange(of: subscriptionsRequested) { _, val in
            if val {
                subscriptionsRequested = false
                if navType == .standardTab {
                    selectedTab = .bills
                } else {
                    showSubscriptions = true
                }
            }
        }
        .onChange(of: cloudTapRequested) { _, val in
            if val {
                cloudTapRequested = false
                handleCloudTap()
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            print("[Nav] Tab → \(newValue)")
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigationTypeChanged)) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                navType = AppearanceStore.navigationType
            }
        }
    }

    // MARK: - Standard Tab Bar Layout

    private var standardTabBarLayout: some View {
        TabView(selection: $selectedTab) {
            Tab(L("tab_settings"), systemImage: "gearshape.fill", value: AppTab.settings) {
                NavigationStack {
                    SettingsView()
                }
            }

            Tab(L("tab_insights"), systemImage: "chart.xyaxis.line", value: AppTab.insights) {
                InsightsView()
            }

            Tab(L("tab_bills"), systemImage: "doc.text.fill", value: AppTab.bills) {
                SubscriptionsView(onDismiss: nil)
            }

            Tab(L("tab_dashboard"), systemImage: "house.fill", value: AppTab.dashboard) {
                DashboardView(
                    refreshId: dashboardRefreshId,
                    showAllTransactions: $showAllTransactions,
                    subscriptionsRequested: $subscriptionsRequested,
                    cloudTapRequested: $cloudTapRequested
                )
            }

            Tab(L("tab_add"), systemImage: "plus", value: AppTab.add, role: .search) {
                Color.clear
            }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == .add {
                selectedTab = oldValue
                showAddSheet = true
            }
        }
    }

    // MARK: - Custom Airy Bar Layout

    private var customAiryBarLayout: some View {
        Group {
            switch selectedTab {
            case .dashboard:
                DashboardView(
                    refreshId: dashboardRefreshId,
                    showAllTransactions: $showAllTransactions,
                    subscriptionsRequested: $subscriptionsRequested,
                    cloudTapRequested: $cloudTapRequested
                )
            case .insights:
                InsightsView()
            case .settings:
                NavigationStack {
                    SettingsView()
                }
            case .bills, .add:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            bottomNavBar
                .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Cloud icon tap logic

    private func handleCloudTap() {
        print("[Tap] Dashboard → Cloud icon")
        if importViewModel.isAnalyzing {
            showLiveExtraction = true
        } else if importViewModel.hasUnreviewedResults {
            importViewModel.addProcessedToPending()
            dashboardRefreshId += 1
            showPendingReview = true
        } else {
            let hasPending = !LocalDataStore.shared.fetchPendingTransactions().isEmpty
            if hasPending {
                showPendingReview = true
            } else {
                showAllTransactions = true
            }
        }
    }

    private var bottomNavBar: some View {
        BottomNavBarView(
            onInsights: {
                if selectedTab == .insights {
                    selectedTab = .dashboard
                } else {
                    selectedTab = .insights
                }
            },
            onFab: {
                print("[Tap] NavBar → FAB (Add)")
                showAddSheet = true
            },
            onSettings: {
                if selectedTab == .settings {
                    selectedTab = .dashboard
                } else {
                    selectedTab = .settings
                }
            },
            useDashboardButton: selectedTab != .dashboard,
            onDashboard: { selectedTab = .dashboard },
            insightsActive: selectedTab == .insights,
            settingsActive: selectedTab == .settings
        )
    }
}

#Preview {
    MainTabView()
        .environment(AuthStore())
}
