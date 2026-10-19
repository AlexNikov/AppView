//
//  AVDebugEventLog.swift
//  AppView
//

import Foundation

/// Main-thread ring buffer of debug events. Accessible via MCP GET /ui/event-log.
final class AVDebugEventLog: NSObject {
    static let shared = AVDebugEventLog()

    private var events: [[String: Any]] = []
    private let capacity = 300

    func record(_ event: String, _ info: [String: Any] = [:]) {
        var e = info
        e["event"] = event
        e["ms"] = Int(Date().timeIntervalSince1970 * 1000)
        if events.count >= capacity { events.removeFirst() }
        events.append(e)
    }

    var allEvents: [[String: Any]] { events }

    func clear() { events.removeAll() }
}
