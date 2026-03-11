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

    enum Tab: Int {
        case dashboard = 0
        case insights = 1
        case settings = 2
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .dashboard:
                    DashboardView()
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

            bottomNavBar
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
    }

    private var bottomNavBar: some View {
        HStack(spacing: 0) {
            navButton(tab: .insights, icon: "chart.xyaxis.line")
            Spacer()
            fabButton
            Spacer()
            navButton(tab: .settings, icon: "gearshape.fill")
        }
        .padding(.horizontal, 32)
        .frame(height: 72)
        .background(
            RoundedRectangle(cornerRadius: 36)
                .fill(.ultraThinMaterial)
                .overlay(
                RoundedRectangle(cornerRadius: 36)
                    .fill(Color.white.opacity(0.5))
                )
                .overlay(
                RoundedRectangle(cornerRadius: 36)
                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: Color(red: 0.118, green: 0.176, blue: 0.141).opacity(0.08), radius: 24, x: 0, y: 8)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }

    private func navButton(tab: Tab, icon: String) -> some View {
        Button {
            if selectedTab == tab {
                selectedTab = .dashboard
            } else {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(selectedTab == tab ? OnboardingDesign.textPrimary : OnboardingDesign.textTertiary)
            }
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var fabButton: some View {
        Button {
            showAddSheet = true
        } label: {
            ZStack {
                Color.clear
                    .frame(width: 88, height: 88)
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white, Color.white.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                        .shadow(color: OnboardingDesign.accentGreen.opacity(0.25), radius: 12, x: 0, y: 6)
                        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(OnboardingDesign.textPrimary)
                }
                .frame(width: 68, height: 68)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(y: -24)
    }
}

#Preview {
    MainTabView()
        .environment(AuthStore())
}
