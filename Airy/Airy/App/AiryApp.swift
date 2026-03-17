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
    private let modelContainer: ModelContainer = {
        let schema = Schema([LocalTransaction.self, LocalPendingTransaction.self])
        // Ensure Application Support exists before SwiftData creates the store (avoids CoreData 512 / "parent directory path reported as missing").
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeURL = appSupport.appendingPathComponent("default.store")
        let dirExistsBefore = FileManager.default.fileExists(atPath: appSupport.path)
        if !dirExistsBefore {
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        let config = ModelConfiguration(url: storeURL)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return container
    }()

    init() {
        LocalDataStore.shared.configure(container: modelContainer)
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
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    Task { @MainActor in ImportViewModel.shared.resumeIfNeeded() }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    ImportViewModel.shared.scheduleBackgroundProcessingIfNeeded()
                }
        }
        .modelContainer(modelContainer)
    }
}
