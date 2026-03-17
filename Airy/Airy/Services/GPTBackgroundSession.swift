//
//  GPTBackgroundSession.swift
//  Airy
//
//  Background URLSession for OpenAI API calls.
//  Network requests continue even when the app is suspended — iOS handles
//  transport in its network layer and wakes the app when responses arrive.
//

import Foundation

/// Response returned by a background URLSession upload task.
struct BackgroundResponse {
    let data: Data
    let statusCode: Int
}

/// Manages a background URLSession for all OpenAI API calls.
/// Acts as a drop-in replacement for URLSession.data(for:) that survives app suspension.
final class GPTBackgroundSession: NSObject {

    static let shared = GPTBackgroundSession()
    static let sessionIdentifier = "ai.airy.gpt-background"

    // MARK: - Background URLSession

    /// Lazy so that `delegate: self` can be passed after super.init().
    private(set) lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        config.isDiscretionary = false          // start ASAP, not at iOS's convenience
        config.sessionSendsLaunchEvents = true  // wake app when a task finishes
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // MARK: - In-flight state (protected by NSLock)

    private let lock = NSLock()
    private var continuations: [Int: CheckedContinuation<BackgroundResponse, Error>] = [:]
    private var responseBuffers: [Int: Data] = [:]
    private var responseStatuses: [Int: Int] = [:]
    private var bodyURLs: [Int: URL] = [:]

    // MARK: - Background completion handler

    /// Set by AiryAppDelegate when iOS calls handleEventsForBackgroundURLSession.
    var backgroundCompletionHandler: (() -> Void)?

    // MARK: - Temp directory for request bodies

    private var bodyDir: URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AiryGPTBodies", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Init

    private override init() { super.init() }

    /// Call once at app launch to reconnect tasks that completed while the app was suspended.
    func reconnect() { _ = session }

    // MARK: - Submit

    /// Submit a POST request via the background URLSession.
    /// The body is written to a temp file (required by background sessions).
    /// Returns when the server responds — even if the app was suspended in between.
    func submitRequest(_ urlRequest: URLRequest, bodyData: Data) async throws -> BackgroundResponse {
        return try await withCheckedThrowingContinuation { continuation in
            let bodyURL = bodyDir.appendingPathComponent(UUID().uuidString + ".json")
            do {
                try bodyData.write(to: bodyURL, options: .atomic)
            } catch {
                continuation.resume(throwing: error)
                return
            }

            // uploadTask reads from file; httpBody must be nil
            var req = urlRequest
            req.httpBody = nil

            let task = session.uploadTask(with: req, fromFile: bodyURL)

            lock.lock()
            continuations[task.taskIdentifier] = continuation
            responseBuffers[task.taskIdentifier] = Data()
            responseStatuses[task.taskIdentifier] = 200
            bodyURLs[task.taskIdentifier] = bodyURL
            lock.unlock()

            task.resume()
        }
    }
}

// MARK: - URLSessionDataDelegate

extension GPTBackgroundSession: URLSessionDataDelegate {

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse {
            lock.lock()
            responseStatuses[dataTask.taskIdentifier] = http.statusCode
            lock.unlock()
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        responseBuffers[dataTask.taskIdentifier]?.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let id = task.taskIdentifier

        lock.lock()
        let data = responseBuffers.removeValue(forKey: id) ?? Data()
        let statusCode = responseStatuses.removeValue(forKey: id) ?? 0
        let continuation = continuations.removeValue(forKey: id)
        let bodyURL = bodyURLs.removeValue(forKey: id)
        lock.unlock()

        // Clean up the temp body file
        if let bodyURL {
            try? FileManager.default.removeItem(at: bodyURL)
        }

        guard let continuation else {
            // App was killed and re-launched by iOS to deliver background session events.
            // No live continuation — the queue item stays .processing and will be
            // reset to .pending by resumeIfNeeded() when the user next opens the app.
            return
        }

        if data.isEmpty {
            print("[GPTBgSession] ⚠️ Empty response data for task \(id), status \(statusCode)")
        }

        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: BackgroundResponse(data: data, statusCode: statusCode))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            self?.backgroundCompletionHandler?()
            self?.backgroundCompletionHandler = nil
        }
    }
}
