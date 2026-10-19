//
//  AVMCPClientDiagnostics.swift
//  AppView
//
//  Connection / discover diagnostics used by launch flow and internal tooling.
//

import Darwin
import Foundation
import AppViewShared
import RxRelay
import RxSwift

/// Immutable connect diagnostics — avoids races when concurrent discover replaces the snapshot
/// while MCP `/status` reads arrays (class + mutable `[Int]` caused SIGSEGV / malloc corruption).
public struct AVMCPConnectSnapshot: Sendable {
    public let channelCount: Int
    public let connectedPorts: [Int]
    public let portErrors: [String]
    public let cachedSimulatorPorts: [Int]
    public let timestamp: TimeInterval

    public init(
        channelCount: Int = 0,
        connectedPorts: [Int] = [],
        portErrors: [String] = [],
        cachedSimulatorPorts: [Int] = [],
        timestamp: TimeInterval = 0
    ) {
        self.channelCount = channelCount
        self.connectedPorts = connectedPorts
        self.portErrors = portErrors
        self.cachedSimulatorPorts = cachedSimulatorPorts
        self.timestamp = timestamp
    }

    public func dictionaryRepresentation() -> [String: Any] {
        [
            "channelCount": channelCount,
            "connectedPorts": connectedPorts.map { NSNumber(value: $0) },
            "portErrors": portErrors,
            "cachedSimulatorPorts": cachedSimulatorPorts.map { NSNumber(value: $0) },
            "timestamp": timestamp,
        ]
    }
}

public final class AVMCPClientDiagnostics {
    public static let shared = AVMCPClientDiagnostics()

    public private(set) var lastConnectSnapshot: AVMCPConnectSnapshot?
    public private(set) var lastDiscoverSummary: [String: Any] = [:]
    private var lastDiscoverProgressAt: TimeInterval = 0
    private var lastDiscoverSignature: String = ""
    private var mcpOperationStartedAt: TimeInterval?
    private let discoverDidUpdateRelay = PublishRelay<[String: Any]>()
    private static let discoverLock = NSLock()
    private let snapshotLock = NSLock()

    private init() {}

    var discoverDidUpdate: Observable<[String: Any]> {
        discoverDidUpdateRelay.asObservable()
    }

    public func recordConnectSnapshot(_ snapshot: AVMCPConnectSnapshot) {
        snapshotLock.lock()
        lastConnectSnapshot = snapshot
        snapshotLock.unlock()
    }

    public func recordDiscoverSummary(_ summary: [String: Any]) {
        let signature = Self.discoverSignature(summary)
        if signature != lastDiscoverSignature {
            lastDiscoverSignature = signature
            lastDiscoverProgressAt = Date().timeIntervalSince1970
        }
        lastDiscoverSummary = summary
        discoverDidUpdateRelay.accept(summary)
    }

    public func discoverProgressedRecently(within interval: TimeInterval) -> Bool {
        guard lastDiscoverProgressAt > 0 else { return false }
        return Date().timeIntervalSince1970 - lastDiscoverProgressAt <= interval
    }

    public var isMcpOperationInProgress: Bool {
        mcpOperationStartedAt != nil
    }

    public func mcpOperationWillBegin() {
        mcpOperationStartedAt = Date().timeIntervalSince1970
        let pauseLaunchDiscovery = {
            AVNavigationManager.sharedInstance.launchWindowController?
                .launchViewController?
                .mcpPauseDiscoveryPolling()
        }
        if Thread.isMainThread {
            pauseLaunchDiscovery()
        } else {
            DispatchQueue.main.sync(execute: pauseLaunchDiscovery)
        }
    }

    public func mcpOperationDidEnd() {
        mcpOperationStartedAt = nil
    }

    public func mcpOperationBlockedAgeSec() -> TimeInterval {
        guard let started = mcpOperationStartedAt else { return 0 }
        return Date().timeIntervalSince1970 - started
    }

    private static func discoverSignature(_ summary: [String: Any]) -> String {
        let usable = summary["usableAppCount"] as? Int ?? -1
        let bundles = (summary["bundleIds"] as? [String]) ?? []
        let channels = (summary["channels"] as? [[String: Any]]) ?? []
        let ports = channels.compactMap { $0["port"] as? Int }.sorted()
        return "\(usable)|\(bundles.joined(separator: ","))|\(ports)"
    }

    public func connectionStateDictionary() -> [String: Any] {
        let apps = AVAppsManager.sharedInstance
        let conn = AVConnectionManager.sharedInstance
        let nav = AVNavigationManager.sharedInstance
        let inspecting = apps.inspectingApp

        let cachedPorts = conn.mcpCachedSimulatorPortNumbers().map { Int($0) }

        var state: [String: Any] = [
            "uiMode": nav.mcpUIMode.rawValue,
            "hasInspectingApp": inspecting != nil,
            "inspectingBundleId": inspecting?.appInfo?.appBundleIdentifier ?? "",
            "inspectingAppName": inspecting?.appInfo?.appName ?? "",
            "channelIsConnected": inspecting?.channel?.isConnected ?? false,
            "channelTargetPort": inspecting?.channel?.targetPort ?? 0,
            "hasHierarchy": AVStaticHierarchyDataSource.sharedInstance.rawHierarchyInfo != nil,
            "cachedSimulatorPorts": cachedPorts,
            "diagLineCount": AppViewDiagLog.lineCount,
        ]

        snapshotLock.lock()
        let diagSnap = lastConnectSnapshot
        snapshotLock.unlock()
        if let snap = conn.mcpLastConnectSnapshot ?? diagSnap {
            state["lastConnect"] = snap.dictionaryRepresentation()
        }
        if !lastDiscoverSummary.isEmpty {
            state["lastDiscover"] = lastDiscoverSummary
        }
        if AVConnectionTiming.isEnabled {
            state["lastTiming"] = AVConnectionTiming.shared.summary
        }
        if nav.mcpUIMode == .launch, Thread.isMainThread {
            state["launchHealth"] = AVMCPLaunchHealth.snapshot()
        }

        return state
    }

    public func diagLogLines(limit: Int) -> [String] {
        AppViewDiagLog.recentLines(limit: limit)
    }

    public func clearDiagLog() {
        AppViewDiagLog.clear()
    }

    /// TCP probe from Mac host to 127.0.0.1 (simulator port forwarding).
    public func simulatorPeertalkPortProbe() -> [String: Any] {
        var ports: [String: Any] = [:]
        let start = Int32(AppViewSimulatorIPv4PortNumberStart)
        let end = Int32(AppViewSimulatorIPv4PortNumberEnd)
        for port in start ... end {
            ports[String(port)] = Self.probeTCPPort(UInt16(port))
        }
        return [
            "ports": ports,
            "portRange": "\(start)-\(end)",
            "hint": "open = demo likely listening; refused = no listener (run AppViewCustomInfoDemoSwift)",
        ]
    }

    public func discoverAppsSync(timeout: TimeInterval) -> [String: Any] {
        mcpOperationWillBegin()
        defer { mcpOperationDidEnd() }
        Self.discoverLock.lock()
        defer { Self.discoverLock.unlock() }

        let effectiveTimeout = max(
            timeout,
            AVMCPTiming.minimumDiscoverTimeout,
            AVWireClientRequestTimeout.appInfo
                + AVWireClientRequestTimeout.preflightPingBeforeApp
                + 8
        )

        // Must not spin the main run loop here — MCP handler already uses the main queue.
        if Thread.isMainThread {
            var result: [String: Any] = [:]
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                result = self.discoverAppsSync(timeout: effectiveTimeout)
                group.leave()
            }
            _ = group.wait(timeout: .now() + effectiveTimeout + AVMCPTiming.mainQueueHop)
            return result
        }

        struct DiscoverPayload {
            var apps: [AVInspectableApp] = []
            var fetchError: NSError?
            var finished = false
        }

        let forceFreshDiscovery = AVConnectionManager.sharedInstance.consumeMCPForceFreshDiscover()
        let waitResult: Result<DiscoverPayload, Error> = AVMCPBlockingWait.onMain(
            timeout: effectiveTimeout
        ) { done in
            _ = AppViewRACSignalRx.observeMainThread(
                AVAppsManager.sharedInstance.fetchAppInfos(
                    withImage: false,
                    localInfos: nil,
                    forceFreshDiscovery: forceFreshDiscovery
                )
            )
            .subscribe(
                onSuccess: { apps in
                    done(.success(DiscoverPayload(apps: apps, finished: true)))
                },
                onFailure: { error in
                    var payload = DiscoverPayload(finished: true)
                    payload.fetchError = (error as NSError?) ?? AVAppViewClientErrors.inner
                    done(.success(payload))
                }
            )
        }

        let apps: [AVInspectableApp]
        let fetchError: NSError?
        let finished: Bool
        switch waitResult {
        case .success(let payload):
            apps = payload.apps
            fetchError = payload.fetchError
            finished = payload.finished
        case .failure:
            apps = []
            fetchError = nil
            finished = false
        }

        let usable = apps.filter { $0.serverVersionError == nil && $0.appInfo != nil }
        let names = usable.compactMap { $0.appInfo?.appName }
        let bundles = usable.compactMap { $0.appInfo?.appBundleIdentifier }
        let channels = usable.map { app -> [String: Any] in
            let tag = AVMCPChannelTag(
                usb: AVConnectionManager.sharedInstance.channelUsesUSB(app.channel)
            ).rawValue
            return [
                "channel": tag,
                "port": app.channel?.targetPort ?? 0,
                "bundleId": app.appInfo?.appBundleIdentifier ?? "",
                "appName": app.appInfo?.appName ?? "",
            ]
        }
        let connectSnap = AVConnectionManager.sharedInstance.mcpLastConnectSnapshot

        var summary: [String: Any] = [
            "timedOut": !finished,
            "usableAppCount": usable.count,
            "rawAppCount": apps.count,
            "appNames": names,
            "bundleIds": bundles,
            "channels": channels,
            "channelCount": connectSnap?.channelCount ?? 0,
            "timestamp": Date().timeIntervalSince1970,
        ]
        if let fetchError {
            summary["error"] = [
                "code": fetchError.code,
                "domain": fetchError.domain,
                "message": fetchError.localizedDescription,
            ]
        }
        if let connectSnap {
            summary["connect"] = connectSnap.dictionaryRepresentation()
        }

        recordDiscoverSummary(summary)
        AppViewDiagLog.log("client MCP discover usable=\(usable.count) [\(names.joined(separator: ", "))]")
        return summary
    }

    public func wireV2PingSync(timeout: TimeInterval) -> [String: Any] {
        guard let channel = AVAppsManager.sharedInstance.inspectingApp?.channel else {
            return [
                "ok": false,
                "message": "No inspectingApp.channel — connect and enter inspector first",
            ]
        }
        guard channel.isConnected else {
            return ["ok": false, "message": "Channel not connected"]
        }

        var pingResult: Any?
        var pingError: NSError?
        var done = false

        let disposable = AppViewRACSignalRx.observeMainThread(
            AVConnectionManager.sharedInstance.request(
                withType: UInt32(AppViewRequestTypePing),
                data: nil,
                channel: channel
            )
            .take(1)
            .asSingle()
        )
        .subscribe(
            onSuccess: { pair in
                pingResult = pair
                done = true
            },
            onFailure: { error in
                pingError = (error as NSError?) ?? AVAppViewClientErrors.inner
                done = true
            }
        )

        let deadline = Date().addingTimeInterval(timeout)
        while !done, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        _ = disposable

        if let pingError {
            return [
                "ok": false,
                "error": [
                    "code": pingError.code,
                    "message": pingError.localizedDescription,
                ],
            ]
        }

        guard let pair = pingResult as? AppViewPair,
              let attachment = pair.first as? AppViewConnectionResponseAttachment else {
            return ["ok": false, "message": "Unexpected ping response type"]
        }

        return [
            "ok": attachment.error == nil,
            "appviewServerVersion": attachment.appviewServerVersion,
            "wireError": attachment.error?.localizedDescription ?? "",
        ]
    }

    /// Non-intrusive listen check — a TCP `connect` would accept on the demo and tear down Peertalk listen.
    static func simulatorPortIsListening(_ port: Int) -> Bool {
        probeTCPPort(UInt16(port)) == "listen"
    }

    private static func probeTCPPort(_ port: UInt16) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return "lsof_fail"
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.contains("127.0.0.1:\(port)") || text.contains("*:\(port)") {
            return "listen"
        }
        if proc.terminationStatus == 1 {
            return "closed"
        }
        return proc.terminationStatus == 0 ? "closed" : "lsof_err_\(proc.terminationStatus)"
    }
}
