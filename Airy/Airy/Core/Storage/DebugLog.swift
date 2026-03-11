//
//  DebugLog.swift
//  Airy
//
//  Debug session instrumentation. Remove after verification.
//

import Foundation

func _dbg(_ loc: String, _ msg: String, _ data: [String: Any] = [:], hypothesisId: String = "") {
    let u = URL(fileURLWithPath: "/Users/oduvanchik/Desktop/Airy/.cursor/debug-41017e.log")
    let dataJson = (try? JSONSerialization.data(withJSONObject: data)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    let hyp = hypothesisId.isEmpty ? "" : ",\"hypothesisId\":\"\(hypothesisId)\""
    let line = "{\"sessionId\":\"41017e\",\"location\":\"\(loc)\",\"message\":\"\(msg)\",\"data\":\(dataJson),\"timestamp\":\(Int(Date().timeIntervalSince1970*1000))\(hyp)}\n"
    guard let d = line.data(using: .utf8) else { return }
    try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: u.path) { FileManager.default.createFile(atPath: u.path, contents: nil, attributes: nil) }
    if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(d); try? h.close() }
}
