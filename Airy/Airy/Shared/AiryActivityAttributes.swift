//
//  AiryActivityAttributes.swift
//  Airy
//
//  Live Activity attributes shared between the main app and AiryWidgets extension.
//  ⚠️  This file must be added to BOTH targets: Airy and AiryWidgets.
//

import ActivityKit

/// Attributes and live state for the import Live Activity (Dynamic Island + Lock Screen).
struct AiryImportAttributes: ActivityAttributes {
    /// A single completed transaction shown in the Lock Screen Live Activity.
    struct LiveActivityItem: Codable, Hashable {
        var merchant: String
        var amount: String  // pre-formatted, e.g. "-$54.21"
    }

    public struct ContentState: Codable, Hashable {
        /// Number of screenshots fully processed (success or failed).
        var processed: Int
        /// Total screenshots in the import queue.
        var total: Int
        /// Last successfully completed transaction, shown in the Lock Screen UI.
        var lastCompletedItem: LiveActivityItem?
    }
}
