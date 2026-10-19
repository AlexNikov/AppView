//
//  AVMCPLaunchHealth.swift
//  AppView
//
//  MCP: detect launch screen freeze / stall (discover stuck, enter hung, no progress).
//

import Foundation
import AppViewShared

enum AVMCPLaunchHealth {
    private static let enteringStuckThreshold: TimeInterval = 50
    private static let discoverStallThreshold: TimeInterval = 25
    private static let discoverNoProgressThreshold: TimeInterval = 30

    static func snapshot() -> [String: Any] {
        let nav = AVNavigationManager.sharedInstance
        let launchVisible = nav.launchWindowController?.window?.isVisible == true
        var result: [String: Any] = [
            "isLaunchVisible": launchVisible,
            "uiMode": AVNavigationManager.sharedInstance.mcpUIMode.rawValue,
        ]

        guard launchVisible, let launchVC = nav.launchWindowController?.launchViewController else {
            result["isFrozen"] = false
            result["freezeReasons"] = [String]()
            return result
        }

        let screen = launchVC.mcpLaunchScreenSnapshot()
        let discover = AVMCPClientDiagnostics.shared.lastDiscoverSummary
        let conn = AVConnectionManager.sharedInstance
        let reasons = freezeReasons(screen: screen, discover: discover, conn: conn)

        result.merge(screen) { _, new in new }
        result["lastDiscover"] = discover
        result["hasAttachedUSB"] = conn.hasAttachedUSBDevices
        result["freezeReasons"] = reasons
        result["isFrozen"] = !reasons.isEmpty
        if let primary = reasons.first {
            result["freezeReason"] = primary
        }
        return result
    }

    // MARK: - Private

    private static func freezeReasons(
        screen: [String: Any],
        discover: [String: Any],
        conn: AVConnectionManager
    ) -> [String] {
        var reasons: [String] = []

        let isEntering = screen["isEnteringApp"] as? Bool ?? false
        let enteringAge = screen["enteringAgeSec"] as? TimeInterval ?? 0
        if isEntering, enteringAge >= enteringStuckThreshold {
            reasons.append("entering_stuck")
        }

        let tileCount = screen["tileCount"] as? Int ?? 0
        let showsSearching = screen["showsSearchingUI"] as? Bool ?? false
        let isPolling = screen["isPolling"] as? Bool ?? false
        let usable = discover["usableAppCount"] as? Int ?? 0
        let discoverAge = secondsSinceDiscover(discover)

        let connectedPorts = (conn.mcpLastConnectSnapshot?.connectedPorts ?? []).count
        if tileCount == 0,
           showsSearching || isPolling,
           discoverAge >= discoverStallThreshold,
           connectedPorts > 0,
           usable == 0 {
            reasons.append("discover_stalled")
        }

        if tileCount == 0,
           !isPolling,
           !isEntering,
           !showsSearching,
           usable == 0 {
            reasons.append("polling_stopped_empty")
        }

        if discoverAge >= discoverNoProgressThreshold,
           !AVMCPClientDiagnostics.shared.discoverProgressedRecently(within: discoverNoProgressThreshold),
           tileCount < expectedTileCount(conn: conn),
           !isEntering {
            reasons.append("discover_no_progress")
        }

        let fetchBlockedAge = AVAppsManager.mcpFetchBlockedAgeSec()
        if fetchBlockedAge >= 30 {
            reasons.append("fetch_app_infos_blocked")
        }

        if AVMCPClientDiagnostics.shared.mcpOperationBlockedAgeSec() >= 60 {
            reasons.append("mcp_operation_blocked")
        }

        return reasons
    }

    private static func expectedTileCount(conn: AVConnectionManager) -> Int {
        var expected = 0
        if AVConnectionManager.mcpHasBootedIOSSimulator() {
            expected += 1
        }
        if conn.hasAttachedUSBDevices {
            expected += 1
        }
        return max(expected, 1)
    }

    private static func secondsSinceDiscover(_ discover: [String: Any]) -> TimeInterval {
        guard let ts = discover["timestamp"] as? TimeInterval, ts > 0 else {
            return .greatestFiniteMagnitude
        }
        return Date().timeIntervalSince1970 - ts
    }
}
