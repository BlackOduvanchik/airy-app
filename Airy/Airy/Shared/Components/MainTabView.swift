//
//  MainTabView.swift
//  Airy
//
//  Dashboard as default, bottom bar: Insights (left), FAB Add (center), Settings (right).
//

import SwiftUI

private struct ImagesToAnalyze: Identifiable {
    let id = UUID()
    let images: [UIImage]
}

struct MainTabView: View {
    @State private var selectedTab: Tab = .dashboard
    @State private var showAddSheet = false
    @State private var showAddTransaction = false
    @State private var addTransactionInitialType: String? = nil
    @State private var showGalleryPicker = false
    @State private var imagesToAnalyze: ImagesToAnalyze? = nil
    @State private var showPendingReview = false
    @State private var pasteNoImageAlert = false
    @State private var importViewModel = ImportViewModel()
    @State private var dashboardRefreshId = 0
    @State private var showAllTransactions = false

    enum Tab: Int {
        case dashboard = 0
        case insights = 1
        case settings = 2
    }

    var body: some View {
        Group {
            switch selectedTab {
            case .dashboard:
                DashboardView(refreshId: dashboardRefreshId, showAllTransactions: $showAllTransactions)
            case .insights:
                InsightsView()
            case .settings:
                NavigationStack {
                    SettingsView()
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
                        showAddTransaction = true
                    }
                },
                onIncome: {
                    showAddSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        addTransactionInitialType = "income"
                        showAddTransaction = true
                    }
                },
                onPasteFromClipboard: {
                    showAddSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let image = UIPasteboard.general.image {
                            imagesToAnalyze = ImagesToAnalyze(images: [image])
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
            AddTransactionView(initialType: addTransactionInitialType, onSuccess: {
                showAddTransaction = false
                addTransactionInitialType = nil
                dashboardRefreshId += 1
            })
        }
        .fullScreenCover(isPresented: $showGalleryPicker) {
            GalleryPickerView(
                onImagesPicked: { images in
                    showGalleryPicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        imagesToAnalyze = ImagesToAnalyze(images: images)
                    }
                },
                onCancel: { showGalleryPicker = false }
            )
        }
        .fullScreenCover(item: $imagesToAnalyze) { wrapper in
            AnalyzingTransactionsView(
                images: wrapper.images,
                importViewModel: importViewModel,
                onConfirm: {
                    imagesToAnalyze = nil
                    if importViewModel.pendingCount > 0 {
                        showPendingReview = true
                    }
                },
                onCancel: {
                    imagesToAnalyze = nil
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
        .alert("No image in clipboard", isPresented: $pasteNoImageAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Copy an image first, then try again.")
        }
        .fullScreenCover(isPresented: $showAllTransactions) {
            TransactionListView(
                showBottomBar: true,
                onInsights: {
                    showAllTransactions = false
                    selectedTab = .insights
                },
                onSettings: {
                    showAllTransactions = false
                    selectedTab = .settings
                }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showAllTransactions = false }
                }
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
            insightsActive: selectedTab == .insights,
            settingsActive: selectedTab == .settings
        )
    }
}

#Preview {
    MainTabView()
        .environment(AuthStore())
}
