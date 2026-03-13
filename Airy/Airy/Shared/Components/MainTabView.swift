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
    @State private var addSheetQuickPickOrder: [String] = []
    @State private var showGalleryPicker = false
    @State private var imagesToAnalyze: ImagesToAnalyze? = nil
    @State private var showPendingReview = false
    @State private var pasteNoImageAlert = false
    @State private var importViewModel = ImportViewModel()
    @State private var dashboardRefreshId = 0
    @State private var showAllTransactions = false
    @State private var showSubscriptions = false

    enum Tab: Int {
        case dashboard = 0
        case insights = 1
        case settings = 2
    }

    var body: some View {
        Group {
            switch selectedTab {
            case .dashboard:
                DashboardView(refreshId: dashboardRefreshId, showAllTransactions: $showAllTransactions, onOpenSubscriptions: { showSubscriptions = true })
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
                    // #region agent log
                    do {
                        let payload: [String: Any] = [
                            "sessionId": "ad783c",
                            "location": "MainTabView.fullScreenCover.onDismiss",
                            "message": "All transactions list dismissed",
                            "data": ["dashboardRefreshId": dashboardRefreshId],
                            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
                            "hypothesisId": "H2"
                        ]
                        if let json = try? JSONSerialization.data(withJSONObject: payload),
                           let line = String(data: json, encoding: .utf8) {
                            let path = "/Users/oduvanchik/Desktop/Airy/.cursor/debug-ad783c.log"
                            let lineData = (line + "\n").data(using: .utf8)!
                            if FileManager.default.fileExists(atPath: path) {
                                if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                                    defer { try? h.close() }
                                    h.seekToEndOfFile()
                                    h.write(lineData)
                                }
                            } else {
                                FileManager.default.createFile(atPath: path, contents: lineData, attributes: nil)
                            }
                        }
                    }
                    // #endregion
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
