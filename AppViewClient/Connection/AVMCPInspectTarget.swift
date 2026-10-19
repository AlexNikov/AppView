//
//  AVMCPInspectTarget.swift
//  AppView
//
//  MCP automation: launch-screen tiles and sim ↔ USB target selection.
//

import AppKit
import AppViewShared
import RxSwift

enum AVMCPInspectTarget {
    /// Triggers launch-screen reload and waits for tiles / discover (MCP automation).
    static func refreshLaunchTargets(timeout: TimeInterval = AVMCPTiming.defaultOperationTimeout) -> [String: Any] {
        AVMCPClientDiagnostics.shared.mcpOperationWillBegin()
        defer { AVMCPClientDiagnostics.shared.mcpOperationDidEnd() }
        if Thread.isMainThread {
            var result: [String: Any] = [:]
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                result = refreshLaunchTargets(timeout: timeout)
                group.leave()
            }
            _ = group.wait(timeout: .now() + timeout + AVMCPTiming.mainQueueHop)
            return result
        }

        let subscribeSem = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            let nav = AVNavigationManager.sharedInstance
            if nav.launchWindowController == nil {
                nav.showLaunch()
            }
            nav.launchWindowController?.launchViewController?.mcpReloadWithoutAutoEnter()
            subscribeSem.signal()
        }
        _ = subscribeSem.wait(timeout: .now() + AVMCPTiming.mainQueueHop)

        let deadline = Date().addingTimeInterval(timeout)
        var targets: [AVMCPLaunchTile] = []
        while Date() < deadline {
            targets = launchTilesOnMain()
            let usable = AVMCPClientDiagnostics.shared.lastDiscoverSummary["usableAppCount"] as? Int ?? 0
            if targets.count >= 2 || (targets.count >= 1 && usable >= 1) {
                break
            }
            Thread.sleep(forTimeInterval: AVMCPTiming.launchTilePollInterval)
        }

        DispatchQueue.main.async {
            AVNavigationManager.sharedInstance.launchWindowController?
                .launchViewController?
                .reloadLaunchTilePreviews()
        }

        return [
            "ok": !targets.isEmpty,
            "uiMode": AVNavigationManager.sharedInstance.mcpUIMode.rawValue,
            "count": targets.count,
            "targets": targets.map { $0.dictionaryRepresentation() },
            "lastDiscover": AVMCPClientDiagnostics.shared.lastDiscoverSummary,
        ]
    }

    /// Visible `AVLaunchAppView` tiles on the launch screen or app-switcher popover.
    static func launchTargets() -> [[String: Any]] {
        launchTiles().map { $0.dictionaryRepresentation() }
    }

    /// Enter inspector from launch or switch sim ↔ USB in inspector (blocks up to `timeout` s).
    static func selectInspectTarget(
        channel: String?,
        accessibilityIdentifier: String?,
        index: Int?,
        timeout: TimeInterval = AVMCPTiming.defaultOperationTimeout
    ) -> [String: Any] {
        selectInspectTargetStructured(
            channel: channel,
            accessibilityIdentifier: accessibilityIdentifier,
            index: index,
            timeout: timeout
        ).dictionaryRepresentation()
    }

    private static func selectInspectTargetStructured(
        channel: String?,
        accessibilityIdentifier: String?,
        index: Int?,
        timeout: TimeInterval
    ) -> AVMCPSelectInspectResult {
        AVMCPClientDiagnostics.shared.mcpOperationWillBegin()
        defer { AVMCPClientDiagnostics.shared.mcpOperationDidEnd() }
        if Thread.isMainThread {
            var result = AVMCPSelectInspectResult.timeout(channel: .unknown)
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                result = selectInspectTargetStructured(
                    channel: channel,
                    accessibilityIdentifier: accessibilityIdentifier,
                    index: index,
                    timeout: timeout
                )
                group.leave()
            }
            _ = group.wait(timeout: .now() + timeout + AVMCPTiming.mainQueueHop)
            return result
        }

        let normalizedChannel = channel?.lowercased()
        let channelTag = AVMCPChannelTag(rawChannel: normalizedChannel)
        let stub = resolveInspectableStubFromTiles(
            channel: normalizedChannel,
            accessibilityIdentifier: accessibilityIdentifier,
            index: index
        )
        let bundleFromA11y = Self.bundleIdFromLaunchAccessibilityIdentifier(accessibilityIdentifier)
        if stub == nil,
           bundleFromA11y == nil,
           normalizedChannel == nil,
           (accessibilityIdentifier ?? "").isEmpty,
           index == nil {
            return .noMatchingTarget(launchTargets: launchTiles())
        }

        let previousMode = AVNavigationManager.sharedInstance.mcpUIMode
        let previousApp = AVAppsManager.sharedInstance.inspectingApp
        let fallbackChannel: AVMCPChannelTag = {
            if channelTag != .unknown { return channelTag }
            return AVAppsManager.mcpChannelTag(for: stub)
        }()

        final class SubHold: @unchecked Sendable {
            var disposable: Disposable?
        }
        let subHold = SubHold()

        let waitResult: Result<AVMCPSelectInspectSuccess, Error> = AVMCPBlockingWait.onMain(
            timeout: timeout + AVMCPTiming.connectCompletionSlack
        ) { done in
            closeAppSwitcherPopoverIfVisible()
            AVStaticAsyncUpdateManager.sharedInstance.endUpdating()
            let conn = AVConnectionManager.sharedInstance
            let connectSingle: Single<(AVInspectableApp, AppViewHierarchyInfo)>
            if let stub, stub.serverVersionError == nil {
                connectSingle = AVAppsManager.sharedInstance.connectInspectableApp(stub)
            } else if let bundleFromA11y {
                connectSingle = AVAppsManager.sharedInstance.fetchAppInfos(withImage: false, localInfos: nil)
                    .flatMap { apps -> Single<(AVInspectableApp, AppViewHierarchyInfo)> in
                        let usable = apps.filter { $0.serverVersionError == nil && $0.appInfo != nil }
                        guard let match = usable.first(where: { $0.appInfo?.appBundleIdentifier == bundleFromA11y }) else {
                            return .error(AVAppViewClientErrors.noConnect)
                        }
                        return AVAppsManager.sharedInstance.connectInspectableApp(match)
                    }
            } else if let normalizedChannel {
                connectSingle = AVAppsManager.sharedInstance.fetchAppInfos(withImage: false, localInfos: nil)
                    .flatMap { apps -> Single<(AVInspectableApp, AppViewHierarchyInfo)> in
                        let usable = apps.filter { $0.serverVersionError == nil && $0.appInfo != nil }
                        let match: AVInspectableApp?
                        if let accessibilityIdentifier, !accessibilityIdentifier.isEmpty,
                           let stub {
                            match = usable.first { candidate in
                                AVAppsManager.isSameInspectableSession(stub, candidate)
                            }
                        } else if normalizedChannel == AVMCPChannelTag.sim.rawValue, usable.count > 1 {
                            let simApps = usable.filter {
                                !AVAppsManager.inspectSessionUsesUSB($0)
                            }
                            if let index, index >= 0, index < simApps.count {
                                match = simApps[index]
                            } else {
                                match = simApps.first
                            }
                        } else {
                            match = usable.first { candidate in
                                AVAppsManager.mcpChannelTag(for: candidate).rawValue == normalizedChannel
                            }
                        }
                        guard let match else {
                            return .error(AVAppViewClientErrors.noConnect)
                        }
                        conn.releaseDiscoveryChannels(except: match.channel)
                        return match.fetchHierarchyData().map { (match, $0) }
                    }
            } else if let stub {
                connectSingle = AVAppsManager.sharedInstance.connectInspectableApp(stub)
            } else {
                connectSingle = .error(AVAppViewClientErrors.noConnect)
            }
            subHold.disposable = AppViewRACSignalRx.observeMainThread(connectSingle)
                .subscribe(
                    onSuccess: { pair in
                        let (freshApp, info) = pair
                        let keepState = AVAppsManager.isSameInspectableSession(previousApp, freshApp)
                        AVAppsManager.sharedInstance.inspectingApp = freshApp
                        AVStaticHierarchyDataSource.sharedInstance.reload(with: info, keepState: keepState)
                        if previousMode == .launch {
                            AVNavigationManager.sharedInstance.showStaticWorkspace()
                            AVNavigationManager.sharedInstance.closeLaunch()
                        }
                        done(.success(AVMCPSelectInspectSuccess(
                            freshApp: freshApp,
                            previousMode: previousMode,
                            keepState: keepState
                        )))
                    },
                    onFailure: { error in
                        done(.failure(error))
                    }
                )
        }
        _ = subHold.disposable

        switch waitResult {
        case .success(let payload):
            return .success(payload)
        case .failure(let error):
            let nsError = error as NSError
            if nsError.isEqual(AVAppViewClientErrors.timeout())
                || nsError.isEqual(AVAppViewClientErrors.inner) {
                return .timeout(channel: fallbackChannel)
            }
            return .failure(
                message: nsError.localizedDescription,
                code: nsError.code,
                channel: fallbackChannel
            )
        }
    }

    // MARK: - Private

    private static func launchTilesOnMain() -> [AVMCPLaunchTile] {
        if Thread.isMainThread {
            return launchTiles()
        }
        var result: [AVMCPLaunchTile] = []
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            result = launchTiles()
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + AVMCPTiming.mainQueueHop)
        return result
    }

    private static func launchTiles() -> [AVMCPLaunchTile] {
        var entries: [(view: AVLaunchAppView, channel: AVMCPChannelTag)] = []
        for window in NSApp.windows where window.isVisible {
            collectLaunchAppViews(in: window.contentView, into: &entries)
        }
        let sorted = entries.sorted { lhs, rhs in
            let lhsSim = lhs.channel == .sim
            let rhsSim = rhs.channel == .sim
            if lhsSim != rhsSim { return lhsSim && !rhsSim }
            let lhsDevice = lhs.view.app?.appInfo?.deviceDescription ?? ""
            let rhsDevice = rhs.view.app?.appInfo?.deviceDescription ?? ""
            return lhsDevice < rhsDevice
        }
        return sorted.enumerated().map { index, entry in
            AVMCPLaunchTile.from(view: entry.view, index: index, channel: entry.channel)
        }
    }

    private static func resolveInspectableStubFromTiles(
        channel: String?,
        accessibilityIdentifier: String?,
        index: Int?
    ) -> AVInspectableApp? {
        var entries: [(view: AVLaunchAppView, channel: AVMCPChannelTag)] = []
        for window in NSApp.windows where window.isVisible {
            collectLaunchAppViews(in: window.contentView, into: &entries)
        }
        let sorted = entries.sorted { lhs, rhs in
            let lhsSim = lhs.channel == .sim
            let rhsSim = rhs.channel == .sim
            if lhsSim != rhsSim { return lhsSim && !rhsSim }
            return (lhs.view.app?.appInfo?.deviceDescription ?? "")
                < (rhs.view.app?.appInfo?.deviceDescription ?? "")
        }

        if let index, index >= 0 {
            let simOnly = sorted.filter { $0.channel == .sim }
            if channel?.lowercased() == AVMCPChannelTag.sim.rawValue, !simOnly.isEmpty {
                if index < simOnly.count, let app = simOnly[index].view.app {
                    return app
                }
            } else if index < sorted.count, let app = sorted[index].view.app {
                return app
            }
        }
        if let accessibilityIdentifier, !accessibilityIdentifier.isEmpty {
            if let match = sorted.first(where: { $0.view.accessibilityIdentifier() == accessibilityIdentifier })?.view.app {
                return match
            }
        }
        if let channel, !channel.isEmpty {
            let normalized = AVMCPChannelTag(rawChannel: channel)
            if let match = sorted.first(where: { $0.channel == normalized })?.view.app {
                return match
            }
        }
        return nil
    }

    /// Dismiss toolbar app-switcher so its in-flight `fetchAppInfos` does not block sim ↔ USB select.
    private static func closeAppSwitcherPopoverIfVisible() {
        for window in NSApp.windows where window.isVisible {
            if window.contentViewController is AVMenuPopoverAppsListController {
                window.close()
            }
        }
    }

    private static func collectLaunchAppViews(
        in view: NSView?,
        into entries: inout [(view: AVLaunchAppView, channel: AVMCPChannelTag)]
    ) {
        guard let view, !view.isHidden, view.alphaValue > 0.05 else { return }
        let frame = view.frame
        if frame.width < 4 || frame.height < 4 { return }

        if let launchView = view as? AVLaunchAppView, launchView.app != nil {
            entries.append((launchView, AVAppsManager.mcpChannelTag(for: launchView.app)))
        }
        for subview in view.subviews {
            collectLaunchAppViews(in: subview, into: &entries)
        }
    }

    /// `appview.launch.app.{bundleId}.sim` → bundle id
    private static func bundleIdFromLaunchAccessibilityIdentifier(_ identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty else { return nil }
        let prefix = "appview.launch.app."
        let suffix = ".sim"
        guard identifier.hasPrefix(prefix), identifier.hasSuffix(suffix) else { return nil }
        let start = identifier.index(identifier.startIndex, offsetBy: prefix.count)
        let end = identifier.index(identifier.endIndex, offsetBy: -suffix.count)
        let bundle = String(identifier[start ..< end])
        return bundle.isEmpty ? nil : bundle
    }
}
