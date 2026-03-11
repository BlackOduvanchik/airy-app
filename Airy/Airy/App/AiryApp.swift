//
//  AiryApp.swift
//  Airy
//
//  AI-first personal finance tracker. Local-only: SwiftData + Sign in with Apple.
//

import SwiftUI
import SwiftData

@main
struct AiryApp: App {
    @State private var authStore = AuthStore()
    private let modelContainer: ModelContainer = {
        let schema = Schema([LocalTransaction.self, LocalPendingTransaction.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    init() {
        LocalDataStore.shared.configure(container: modelContainer)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authStore)
        }
        .modelContainer(modelContainer)
    }
}
