//
//  PaywallView.swift
//  Airy
//

import SwiftUI
import Combine

@available(iOS 15.0, *)
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = PaywallViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Airy Pro")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Unlimited AI analysis, Money Mirror insights, subscriptions dashboard, yearly review, and more.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                if !viewModel.products.isEmpty {
                    ForEach(viewModel.products) { p in
                        Text("\(p.displayName) — \(p.displayPrice)")
                            .font(.subheadline)
                    }
                }
                Button("Subscribe") {
                    Task { await viewModel.purchase() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isPurchasing)
                Button("Restore purchases") {
                    Task { await viewModel.restore() }
                }
                .disabled(viewModel.isRestoring)
                if let err = viewModel.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await viewModel.loadProducts() }
            .onChange(of: viewModel.didSucceed) { _, ok in
                if ok { dismiss() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .airyEntitlementsDidChange)) { _ in
                viewModel.didSucceed = true
            }
        }
    }
}

#Preview {
    PaywallView()
}
