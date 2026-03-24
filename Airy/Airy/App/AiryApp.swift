//
//  AiryApp.swift
//  Airy
//
//  AI-first personal finance tracker. Local-only: SwiftData + Sign in with Apple.
//

import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct AiryApp: App {
    @UIApplicationDelegateAdaptor(AiryAppDelegate.self) var appDelegate
    @State private var authStore = AuthStore()
    @State private var themeProvider = ThemeProvider()
    @State private var appLockManager = AppLockManager.shared
    private let modelContainer: ModelContainer = {
        let schema = Schema([LocalTransaction.self, LocalPendingTransaction.self])
        // Ensure Application Support exists before SwiftData creates the store (avoids CoreData 512 / "parent directory path reported as missing").
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeURL = appSupport.appendingPathComponent("default.store")
        let dirExistsBefore = FileManager.default.fileExists(atPath: appSupport.path)
        if !dirExistsBefore {
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        // SAFETY: Never remove or rename @Model stored properties without a SchemaMigrationPlan.
        // SwiftData defaults to shouldDeleteIfMigrationFails: true — schema mismatch silently
        // wipes the entire database. Adding new optional properties is safe (lightweight migration).
        let config = ModelConfiguration(url: storeURL)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return container
    }()

    init() {
        LocalDataStore.shared.configure(container: modelContainer)
        // One-time migration: normalize dates + fix nil isSubscription values.
        if !UserDefaults.standard.bool(forKey: "AiryDataMigrationV2Done") {
            LocalDataStore.shared.normalizeTransactionData()
            UserDefaults.standard.set(true, forKey: "AiryDataMigrationV2Done")
        }
        // One-time migration: replace hash-like merchant names with category display name.
        if !UserDefaults.standard.bool(forKey: "AiryDataMigrationV5HashAndUUIDCategories") {
            LocalDataStore.shared.migrateHashMerchants()
            UserDefaults.standard.set(true, forKey: "AiryDataMigrationV5HashAndUUIDCategories")
        }
        // Reconnect background URLSession — delivers any tasks that completed while app was suspended.
        GPTBackgroundSession.shared.reconnect()
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "ai.airy.imageProcessing",
            using: nil
        ) { task in
            if let processingTask = task as? BGProcessingTask {
                ImportViewModel.shared.handleBackgroundTask(processingTask)
            } else {
                task.setTaskCompleted(success: false)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authStore)
                .environment(themeProvider)
                .environment(appLockManager)
                .preferredColorScheme(themeProvider.preferredScheme)
                .tint(themeProvider.textPrimary)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    Task { @MainActor in
                        ImportViewModel.shared.resumeIfNeeded()
                        SubscriptionAnalysisService.shared.checkAndAnalyzeIfNeeded()
                        if appLockManager.isLocked {
                            appLockManager.authenticate()
                        }
                        // Theme is handled by ContentView's onChange(of: systemColorScheme).
                        // UIKit trait collections are polluted by .preferredColorScheme() so
                        // checkSystemAppearance() cannot reliably detect the real system theme.
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    appLockManager.lockIfNeeded()
                    ImportViewModel.shared.scheduleBackgroundProcessingIfNeeded()
                    try? LocalDataStore.shared.context?.save()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    try? LocalDataStore.shared.context?.save()
                }
        }
        .modelContainer(modelContainer)
    }
}
