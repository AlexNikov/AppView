//
//  AVConnectionTiming.swift
//  AppView
//
//  Temporary connection/discovery phase timings (APPVIEW_VERIFY=1 or APPVIEW_CONN_TIMING=1).
//

import Foundation
import AppViewShared

final class AVConnectionTiming {
    static let shared = AVConnectionTiming()

    static var isEnabled: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["APPVIEW_CONN_TIMING"] == "1" || env["APPVIEW_VERIFY"] == "1"
    }

    private let lock = NSLock()
    private var openPhases: [String: (start: CFAbsoluteTime, attrs: [String: Any])] = [:]
    private var completed: [[String: Any]] = []
    private let capacity = 250

    private init() {}

    func begin(_ phase: String, attrs: [String: Any] = [:]) {
        guard Self.isEnabled else { return }
        lock.lock()
        openPhases[phase] = (CFAbsoluteTimeGetCurrent(), attrs)
        lock.unlock()
    }

    func end(_ phase: String, attrs: [String: Any] = [:]) {
        guard Self.isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let open = openPhases.removeValue(forKey: phase) else { return }
        let durationMs = Int((CFAbsoluteTimeGetCurrent() - open.start) * 1000)
        recordLocked(phase: phase, durationMs: durationMs, attrs: open.attrs.merging(attrs) { _, new in new })
    }

    func recordInstant(_ phase: String, durationMs: Int, attrs: [String: Any] = [:]) {
        guard Self.isEnabled else { return }
        lock.lock()
        recordLocked(phase: phase, durationMs: durationMs, attrs: attrs)
        lock.unlock()
    }

    private func recordLocked(phase: String, durationMs: Int, attrs: [String: Any]) {
        var entry: [String: Any] = [
            "phase": phase,
            "durationMs": durationMs,
            "ms": Int(Date().timeIntervalSince1970 * 1000),
        ]
        for (key, value) in attrs {
            entry[key] = value
        }
        if completed.count >= capacity {
            completed.removeFirst(completed.count - capacity + 1)
        }
        completed.append(entry)
        AVDebugEventLog.shared.record("timing", entry)
        let attrSummary = attrs.isEmpty
            ? ""
            : " " + attrs.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        AppViewDiagLog.log("timing phase=\(phase) ms=\(durationMs)\(attrSummary)")
    }

    var recentPhases: [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    var summary: [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        var totals: [String: Int] = [:]
        var counts: [String: Int] = [:]
        var maxMs: [String: Int] = [:]
        for entry in completed {
            guard let phase = entry["phase"] as? String,
                  let ms = entry["durationMs"] as? Int else { continue }
            totals[phase, default: 0] += ms
            counts[phase, default: 0] += 1
            maxMs[phase] = max(maxMs[phase] ?? 0, ms)
        }
        let recent = completed.suffix(24).map { $0 }
        return [
            "enabled": true,
            "phaseCount": completed.count,
            "totalsMs": totals,
            "counts": counts,
            "maxMs": maxMs,
            "recent": recent,
        ]
    }

    func clear() {
        lock.lock()
        openPhases.removeAll()
        completed.removeAll()
        lock.unlock()
    }
}
