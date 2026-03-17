//
//  MainTabView.swift
//  Airy
//
//  Dashboard as default, bottom bar: Insights (left), FAB Add (center), Settings (right).
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Tab = .dashboard
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

    private var importViewModel: ImportViewModel { ImportViewModel.shared }

    enum Tab: Int {
        case dashboard = 0
        case insights = 1
        case settings = 2
    }

    var body: some View {
        Group {
            switch selectedTab {
            case .dashboard:
                DashboardView(
                    refreshId: dashboardRefreshId,
                    showAllTransactions: $showAllTransactions,
                    onOpenSubscriptions: { showSubscriptions = true },
                    onCloudTapped: handleCloudTap
                )
            case .insights:
                InsightsView()
            case .settings:
                NavigationStack {
                    SettingsView(importViewModel: importViewModel)
                        .navigationTitle("Settings")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            bottomNavBar
                .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showAddSheet) {
            AddActionSheetView(
                onExpense: {
                    showAddSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        addTransactionInitialType = nil
                        addSheetQuickPickOrder = LastUsedCategoriesStore.forQuickPick()
                        showAddTransaction = true
                    }
                },
                onIncome: {
                    showAddSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        addTransactionInitialType = "income"
                        addSheetQuickPickOrder = LastUsedCategoriesStore.forQuickPick()
                        showAddTransaction = true
                    }
                },
                onPasteFromClipboard: {
                    showAddSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let image = UIPasteboard.general.image {
                            ImportViewModel.shared.enqueue([image])
                            showLiveExtraction = true
                        } else {
                            pasteNoImageAlert = true
                        }
                    }
                },
                onOpenGallery: {
                    showAddSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showGalleryPicker = true
                    }
                },
                onCancel: {
                    showAddSheet = false
                }
            )
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showAddTransaction) {
            AddTransactionView(initialType: addTransactionInitialType, initialQuickPickOrder: addSheetQuickPickOrder, onSuccess: {
                showAddTransaction = false
                addTransactionInitialType = nil
                dashboardRefreshId += 1
            })
        }
        .fullScreenCover(isPresented: $showGalleryPicker) {
            GalleryPickerView(
                onImagesPicked: { images in
                    showGalleryPicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        ImportViewModel.shared.enqueue(images)
                        showLiveExtraction = true
                    }
                },
                onCancel: { showGalleryPicker = false }
            )
            .ignoresSafeArea()
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
        }
        .fullScreenCover(isPresented: $showPendingReview) {
            NavigationStack {
                PendingReviewView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showPendingReview = false }
                        }
                    }
            }
        }
        .onChange(of: showPendingReview) { _, showing in
            if !showing { dashboardRefreshId += 1 }
        }
        .alert("No image in clipboard", isPresented: $pasteNoImageAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Copy an image first, then try again.")
        }
        .fullScreenCover(isPresented: $showSubscriptions) {
            SubscriptionsView(onDismiss: { showSubscriptions = false })
        }
        .fullScreenCover(isPresented: $showAllTransactions) {
            TransactionListView(
                showBottomBar: true,
                onDismiss: {
                    showAllTransactions = false
                },
                onInsights: {
                    showAllTransactions = false
                    selectedTab = .insights
                },
                onSettings: {
                    showAllTransactions = false
                    selectedTab = .settings
                }
            )
        }
    }

    // MARK: - Cloud icon tap logic

    private func handleCloudTap() {
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
            onFab: { showAddSheet = true },
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
