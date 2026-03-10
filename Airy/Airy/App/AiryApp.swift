//
//  AiryApp.swift
//  Airy
//
//  AI-first personal finance tracker.
//

import SwiftUI

@main
struct AiryApp: App {
    @State private var authStore = AuthStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authStore)
        }
    }
}
