//
//  MainTabView.swift
//  Airy
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.pie") }
                .tag(0)
            TransactionListView()
                .tabItem { Label("Transactions", systemImage: "list.bullet") }
                .tag(1)
            ImportView()
                .tabItem { Label("Import", systemImage: "camera") }
                .tag(2)
            InsightsView()
                .tabItem { Label("Insights", systemImage: "lightbulb") }
                .tag(3)
            MoreTabView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(4)
        }
    }
}

/// More tab: Settings and Subscriptions
struct MoreTabView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Settings", destination: SettingsView())
                NavigationLink("Subscriptions", destination: SubscriptionsView())
            }
            .navigationTitle("More")
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthStore())
}
