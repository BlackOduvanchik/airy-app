//
//  AiryAppDelegate.swift
//  Airy
//
//  UIApplicationDelegate that handles background URLSession events.
//  SwiftUI's App protocol doesn't expose handleEventsForBackgroundURLSession,
//  so we use UIApplicationDelegateAdaptor to receive it.
//

import UIKit

class AiryAppDelegate: NSObject, UIApplicationDelegate {

    /// Called by iOS when a background URLSession task finishes while the app was suspended.
    /// iOS wakes the app briefly to deliver the event; we must call the completion handler
    /// after updating UI / Live Activity so iOS knows we're done and can suspend again.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == GPTBackgroundSession.sessionIdentifier else {
            completionHandler()
            return
        }
        // Store the handler — GPTBackgroundSession calls it in urlSessionDidFinishEvents.
        GPTBackgroundSession.shared.backgroundCompletionHandler = completionHandler
    }
}
