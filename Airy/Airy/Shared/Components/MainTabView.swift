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
    @State private var showImportView = false

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
                onScreenshot: {
                    showAddSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showImportView = true
                    }
                },
                onCancel: {
                    showAddSheet = false
                }
            )
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showAddTransaction) {
            AddTransactionView(initialType: addTransactionInitialType, onSuccess: {
                showAddTransaction = false
                addTransactionInitialType = nil
            })
        }
        .sheet(isPresented: $showImportView) {
            ImportView()
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
        .padding(.vertical, 12)
        .padding(.bottom, 30)
        .background(
            RoundedRectangle(cornerRadius: 36)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 36)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: OnboardingDesign.textPrimary.opacity(0.1), radius: 20, x: 0, y: 10)
        )
        .padding(.horizontal, 20)
    }

    private func navButton(tab: Tab, icon: String) -> some View {
        Button {
            if selectedTab == tab {
                selectedTab = .dashboard
            } else {
                selectedTab = tab
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(selectedTab == tab ? OnboardingDesign.textPrimary : OnboardingDesign.textTertiary)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var fabButton: some View {
        Button {
            showAddSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(OnboardingDesign.textPrimary)
                .frame(width: 68, height: 68)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white, Color.white.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                        .shadow(color: OnboardingDesign.accentGreen.opacity(0.2), radius: 16, x: 0, y: 8)
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                )
        }
        .buttonStyle(.plain)
        .offset(y: -24)
    }
}

#Preview {
    MainTabView()
        .environment(AuthStore())
}
