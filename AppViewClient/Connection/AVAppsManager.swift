import Foundation
import AppViewShared
import RxRelay
import RxSwift

public final class AVAppsManager: NSObject {
    public static let sharedInstance = AVAppsManager()

    static func usableInspectableApps(from apps: [AVInspectableApp]) -> [AVInspectableApp] {
        apps.filter { $0.serverVersionError == nil && $0.appInfo != nil }
    }

    /// Same bundle on simulator and USB counts as different inspect targets.
    /// When both are simulator-only, Peertalk port distinguishes dual-sim sessions.
    static func isSameInspectableSession(_ a: AVInspectableApp?, _ b: AVInspectableApp?) -> Bool {
        guard let a, let b else { return false }
        guard a.appInfo?.isEqual(toAppInfo: b.appInfo) == true else { return false }
        let conn = AVConnectionManager.sharedInstance
        let aUSB = inspectSessionUsesUSB(a)
        let bUSB = inspectSessionUsesUSB(b)
        guard aUSB == bUSB else { return false }
        if aUSB { return true }
        let aPort = a.channel?.targetPort ?? 0
        let bPort = b.channel?.targetPort ?? 0
        if aPort > 0, bPort > 0 { return aPort == bPort }
        return true
    }

    static func usableSimulatorApps(from apps: [AVInspectableApp]) -> [AVInspectableApp] {
        usableInspectableApps(from: apps).filter { !inspectSessionUsesUSB($0) }
    }

    /// Popover / fresh discover when sim+USB or multiple booted simulators may yield more than one target.
    static func popoverNeedsFreshDiscover(from apps: [AVInspectableApp]) -> Bool {
        let conn = AVConnectionManager.sharedInstance
        let usable = usableInspectableApps(from: apps)
        if conn.hasAttachedUSBDevices {
            let hasUSB = usable.contains { conn.channelUsesUSB($0.channel) }
            let hasSim = usable.contains { !inspectSessionUsesUSB($0) }
            return !(hasUSB && hasSim)
        }
        let bootedSims = AVConnectionManager.mcpBootedIOSSimulatorCount()
        guard bootedSims >= 2 else { return false }
        return usableSimulatorApps(from: apps).count < min(bootedSims, 2)
    }

    static func matchesInspectTarget(
        _ candidate: AVInspectableApp,
        session: AVInspectableApp,
        wantsUSB: Bool
    ) -> Bool {
        guard candidate.serverVersionError == nil, candidate.appInfo != nil else { return false }
        let conn = AVConnectionManager.sharedInstance
        guard conn.channelUsesUSB(candidate.channel) == wantsUSB else { return false }
        if let targetInfo = session.appInfo {
            let bundle = targetInfo.appBundleIdentifier ?? ""
            if !bundle.isEmpty, !targetInfo.isEqual(toAppInfo: candidate.appInfo) {
                return false
            }
        }
        if wantsUSB { return true }
        if let sessionPort = session.channel?.targetPort, sessionPort > 0 {
            return candidate.channel?.targetPort == sessionPort
        }
        return isSameInspectableSession(session, candidate)
    }

    /// Peertalk transport for an inspect target — survives a dropped channel (reload / reconnect).
    static func inspectSessionUsesUSB(_ app: AVInspectableApp) -> Bool {
        if app.isLaunchUSBPendingPlaceholder {
            return true
        }
        let conn = AVConnectionManager.sharedInstance
        if let channel = app.channel {
            return conn.channelUsesUSB(channel)
        }
        if app.appInfo?.deviceType == .simulator {
            return false
        }
        return conn.hasAttachedUSBDevices
    }

    private enum AVInspectTransportFilter {
        case usb
        case simulator
    }

    public enum SwitchStatus {
        case idle
        /// App button tapped; waiting for the app list to arrive before showing the popover.
        case fetchingAppList
        case connecting(AVInspectableApp)

        /// True whenever the App button should be disabled.
        public var isBusy: Bool {
            switch self {
            case .idle: return false
            case .fetchingAppList, .connecting: return true
            }
        }

        public var isConnecting: Bool {
            if case .connecting = self { return true }
            return false
        }
    }

    public struct SwitchSuccess {
        public let previousApp: AVInspectableApp?
        public let freshApp: AVInspectableApp
        public let hierarchyInfo: AppViewHierarchyInfo
    }

    private static func transportFilter(forUSB wantsUSB: Bool) -> AVInspectTransportFilter {
        wantsUSB ? .usb : .simulator
    }

    private static func filterChannels(
        _ channels: [AVPeerChannel],
        transport: AVInspectTransportFilter
    ) -> [AVPeerChannel] {
        let conn = AVConnectionManager.sharedInstance
        switch transport {
        case .usb:
            return channels.filter { conn.channelUsesUSB($0) }
        case .simulator:
            return channels.filter { !conn.channelUsesUSB($0) }
        }
    }

    /// Simulator tiles first, then USB; stable order within each group.
    static func sortedForDisplay(_ apps: [AVInspectableApp]) -> [AVInspectableApp] {
        apps.sorted { lhs, rhs in
            let lhsSim = !inspectSessionUsesUSB(lhs)
            let rhsSim = !inspectSessionUsesUSB(rhs)
            if lhsSim != rhsSim { return lhsSim && !rhsSim }
            let lhsDevice = lhs.appInfo?.deviceDescription ?? ""
            let rhsDevice = rhs.appInfo?.deviceDescription ?? ""
            if lhsDevice != rhsDevice { return lhsDevice < rhsDevice }
            return (lhs.appInfo?.appName ?? "") < (rhs.appInfo?.appName ?? "")
        }
    }

    /// Adds USB placeholder tiles when a physical device is attached but its demo is not listening yet.
    static func appsForLaunchDisplay(discovered: [AVInspectableApp]) -> [AVInspectableApp] {
        let conn = AVConnectionManager.sharedInstance
        let hasConnectedUSBApp = discovered.contains {
            $0.serverVersionError == nil && $0.appInfo != nil && conn.channelUsesUSB($0.channel)
        }
        guard conn.hasAttachedUSBDevices, !hasConnectedUSBApp else {
            return sortedForDisplay(discovered)
        }

        var result = discovered
        for deviceID in conn.uniqueAttachedUSBDeviceIDs() {
            let placeholder = AVInspectableApp()
            placeholder.isLaunchUSBPendingPlaceholder = true
            placeholder.pendingUSBDeviceID = deviceID
            let info = AppViewAppInfo()
            info.deviceType = .others
            info.deviceDescription = conn.usbDeviceLabel(for: deviceID) ?? "iPhone"
            info.appName = NSLocalizedString("Waiting for inspectable app", comment: "")
            placeholder.appInfo = info
            result.append(placeholder)
        }
        return sortedForDisplay(result)
    }

    /// USB demo when a physical device is attached (CollLayout on iPhone, etc.).
    static func preferredUSBInspectableApp(from apps: [AVInspectableApp]) -> AVInspectableApp? {
        let usable = usableInspectableApps(from: apps)
        guard AVConnectionManager.sharedInstance.hasAttachedUSBDevices else { return nil }
        return usable.first { AVConnectionManager.sharedInstance.channelUsesUSB($0.channel) }
    }

    /// Launch auto-enter: only when a single target, or USB-only while iPhone is attached (never steal sim tile).
    static func preferredAppForLaunchAutoEnter(from apps: [AVInspectableApp]) -> AVInspectableApp? {
        let usable = usableInspectableApps(from: apps)
        guard !usable.isEmpty else { return nil }
        if usable.count == 1 { return usable[0] }
        let conn = AVConnectionManager.sharedInstance
        let simApps = usable.filter { !conn.channelUsesUSB($0.channel) }
        let usbApps = usable.filter { conn.channelUsesUSB($0.channel) }
        if !simApps.isEmpty, !usbApps.isEmpty {
            return nil
        }
        return preferredUSBInspectableApp(from: apps) ?? usable.first
    }

    /// Launch / MCP: prefer USB demo when iPhone is plugged in, else known demo bundle, else first usable.
    static func preferredInspectableApp(from apps: [AVInspectableApp]) -> AVInspectableApp? {
        let usable = usableInspectableApps(from: apps)
        guard !usable.isEmpty else { return nil }
        if let usb = preferredUSBInspectableApp(from: apps) {
            return usb
        }
        return AVDemoBundleID.firstMatch(in: usable) ?? usable.first
    }

    private let inspectingAppRelay = BehaviorRelay<AVInspectableApp?>(value: nil)
    var inspectingAppObservable: Observable<AVInspectableApp?> {
        inspectingAppRelay.asObservable()
    }

    public var inspectingApp: AVInspectableApp? {
        get { inspectingAppRelay.value }
        set {
            let oldValue = inspectingAppRelay.value
            guard oldValue !== newValue else { return }
            // Accept the new session before closing the old Peertalk channel. Otherwise
            // channelWillEnd on the previous channel fires while inspectingApp still points
            // at it and auto-reconnect steals the switch (sim ↔ USB).
            inspectingAppRelay.accept(newValue)
            if let newValue {
                willConnectToAppRelay.accept(newValue)
            }
            if let oldValue, let oldChannel = oldValue.channel, oldChannel !== newValue?.channel {
                AVConnectionManager.sharedInstance.releaseCachedChannel(oldChannel)
            }
            let shouldPostNotification = oldValue != nil && newValue == nil
            if shouldPostNotification {
                NotificationCenter.default.post(
                    name: NSNotification.Name("AVInspectingAppDidEndNotificationName"),
                    object: self
                )
            }
        }
    }

    /// Launch tile or toolbar popover: re-resolve Peertalk (sim vs USB), close other links, fetch hierarchy.
    public func connectInspectableApp(_ selected: AVInspectableApp) -> Single<(AVInspectableApp, AppViewHierarchyInfo)> {
        let conn = AVConnectionManager.sharedInstance
        let wantsUSB = Self.inspectSessionUsesUSB(selected)
        guard let targetInfo = selected.appInfo else {
            return .error(AVAppViewClientErrors.inner)
        }
        intentionalSessionChange = true

        // Fast path: tile/popover already holds a live Peertalk channel — avoid fetchAppInfos lock + port scan.
        if selected.serverVersionError == nil,
           let channel = selected.channel,
           channel.isConnected {
            conn.releaseDiscoveryChannels(except: channel)
            return selected.fetchHierarchyData(scanLayoutIssues: true)
                .map { (selected, $0) }
                .catch { [weak self] _ -> Single<(AVInspectableApp, AppViewHierarchyInfo)> in
                    guard let self else { return .error(AVAppViewClientErrors.noConnect) }
                    return self.connectInspectableAppViaRediscover(
                        selected: selected,
                        targetInfo: targetInfo,
                        wantsUSB: wantsUSB
                    )
                }
                .do(onDispose: { [weak self] in
                    self?.intentionalSessionChange = false
                })
        }

        return connectInspectableAppViaRediscover(
            selected: selected,
            targetInfo: targetInfo,
            wantsUSB: wantsUSB
        )
        .do(onDispose: { [weak self] in
            self?.intentionalSessionChange = false
        })
    }

    private func connectInspectableAppViaRediscover(
        selected: AVInspectableApp,
        targetInfo: AppViewAppInfo,
        wantsUSB: Bool
    ) -> Single<(AVInspectableApp, AppViewHierarchyInfo)> {
        fetchHierarchyAfterRediscover(matching: selected, targetInfo: targetInfo, wantsUSB: wantsUSB)
    }

    /// Re-resolve Peertalk for the same inspect target (sim vs USB), close other links, fetch hierarchy.
    private func fetchHierarchyAfterRediscover(
        matching session: AVInspectableApp,
        targetInfo: AppViewAppInfo,
        wantsUSB: Bool
    ) -> Single<(AVInspectableApp, AppViewHierarchyInfo)> {
        let conn = AVConnectionManager.sharedInstance
        return fetchAppInfos(
            withImage: false,
            localInfos: [targetInfo],
            forceFreshDiscovery: true,
            usbOnly: wantsUSB
        )
            .flatMap { [weak self] apps -> Single<(AVInspectableApp, AppViewHierarchyInfo)> in
                guard let self else { return .error(AVAppViewClientErrors.inner) }
                let fresh = apps.first(where: { candidate in
                    Self.matchesInspectTarget(candidate, session: session, wantsUSB: wantsUSB)
                }) ?? self.pickInspectableAppForReload(current: session, from: apps, wantsUSB: wantsUSB)
                guard let fresh else {
                    AppViewDiagLog.log(
                        "client reconnect: no Peertalk match usb=\(wantsUSB) usable=\(apps.count)"
                    )
                    return .error(AVAppViewClientErrors.noConnect)
                }
                if let icon = targetInfo.appIcon {
                    fresh.appInfo?.appIcon = icon
                }
                if let screenshot = targetInfo.screenshot {
                    fresh.appInfo?.screenshot = screenshot
                }
                conn.releaseDiscoveryChannels(except: fresh.channel)
                return fresh.fetchHierarchyData(scanLayoutIssues: true).map { (fresh, $0) }
            }
    }

    /// Toolbar App button: fetches the app list for the popover and blocks the button while loading.
    /// Only blocks when there are attached USB devices or a booted simulator (i.e. when the scan
    /// can take non-trivial time). Returns the same value as fetchAppInfos.
    public func fetchAppsForPopover(withImage needImages: Bool) -> Single<[AVInspectableApp]> {
        let conn = AVConnectionManager.sharedInstance
        let hasTargets = conn.hasAttachedUSBDevices || AVConnectionManager.mcpHasBootedIOSSimulator()
        if hasTargets {
            switchStatusRelay.accept(.fetchingAppList)
        }
        let needsDualTargets = inspectingApp != nil
            && (
                AVConnectionManager.sharedInstance.hasAttachedUSBDevices
                    || AVConnectionManager.mcpBootedIOSSimulatorCount() >= 2
            )
        return fetchAppInfosForPopoverUnlocked(withImage: needImages, needsDualTargets: needsDualTargets)
            .do(onDispose: { [weak self] in
                // Only reset if we're still in fetchingAppList; don't overwrite a connecting state
                // that started while this fetch was in flight (shouldn't happen, but be safe).
                guard let self, case .fetchingAppList = self.switchStatusRelay.value else { return }
                self.switchStatusRelay.accept(.idle)
            })
    }

    /// Popover list while inspecting: prefer a light fetch; full relisten when sim+USB or dual-sim list is incomplete.
    private func fetchAppInfosForPopoverUnlocked(
        withImage needImages: Bool,
        needsDualTargets: Bool
    ) -> Single<[AVInspectableApp]> {
        return fetchAppInfos(withImage: needImages, localInfos: nil, forceFreshDiscovery: false)
            .flatMap { [weak self] apps -> Single<[AVInspectableApp]> in
                guard let self, needsDualTargets, Self.popoverNeedsFreshDiscover(from: apps) else {
                    return .just(apps)
                }
                return self.fetchAppInfos(withImage: needImages, localInfos: nil, forceFreshDiscovery: true)
            }
    }

    /// Toolbar app popover: cancels any in-flight switch and starts a fresh one.
    /// Observe switchSuccessObservable / switchFailureObservable for results.
    public func switchToInspectableApp(_ selected: AVInspectableApp) {
        let previousApp = inspectingApp
        let previousPort = previousApp?.channel?.targetPort ?? 0
        let selectedPort = selected.channel?.targetPort ?? 0
        let isSimToSim = previousApp != nil
            && !Self.inspectSessionUsesUSB(previousApp!)
            && !Self.inspectSessionUsesUSB(selected)
        if isSimToSim {
            AVConnectionTiming.shared.begin(
                "switch.simToSim",
                attrs: [
                    "fromPort": previousPort,
                    "toPort": selectedPort,
                    "fromBundle": previousApp?.appInfo?.appBundleIdentifier ?? "",
                    "toBundle": selected.appInfo?.appBundleIdentifier ?? "",
                ]
            )
        }
        // Set flag before resetting the bag so the old subscription's onDispose (which clears the flag)
        // cannot leave a window where channelWillEnd triggers a spurious auto-reconnect.
        intentionalSessionChange = true
        autoReconnectDisposeBag = DisposeBag()
        currentSwitchDisposeBag = DisposeBag()
        switchStatusRelay.accept(.connecting(selected))
        connectInspectableApp(selected)
            .observe(on: MainScheduler.instance)
            .subscribe(
                onSuccess: { [weak self] pair in
                    guard let self else { return }
                    let (freshApp, info) = pair
                    self.inspectingApp = freshApp
                    self.switchStatusRelay.accept(.idle)
                    if isSimToSim {
                        AVConnectionTiming.shared.end("switch.simToSim", attrs: ["ok": true])
                    }
                    self.switchSuccessRelay.accept(SwitchSuccess(
                        previousApp: previousApp,
                        freshApp: freshApp,
                        hierarchyInfo: info
                    ))
                },
                onFailure: { [weak self] error in
                    if isSimToSim {
                        AVConnectionTiming.shared.end("switch.simToSim", attrs: ["ok": false])
                    }
                    self?.switchStatusRelay.accept(.idle)
                    self?.switchFailureRelay.accept(error)
                }
            )
            .disposed(by: currentSwitchDisposeBag)
    }

    private let didAutoReconnectSuccRelay = PublishRelay<Void>()

    public var didAutoReconnectSuccObservable: Observable<Void> {
        didAutoReconnectSuccRelay.asObservable()
    }

    private let willConnectToAppRelay = PublishRelay<AVInspectableApp>()
    /// Suppresses auto-reconnect while closing the previous Peertalk link during sim ↔ USB connect.
    private var intentionalSessionChange = false
    private let disposeBag = DisposeBag()
    private var autoReconnectDisposeBag = DisposeBag()
    private var autoReconnectMissCount = 0

    private static let autoReconnectMaxAttempts = 40
    private static let autoReconnectIntervalSec: RxTimeInterval = .seconds(3)
    /// Per-attempt timeout for fetchInspectableApp during auto-reconnect. Bounds the wait
    /// when purgeDisconnectedCachedChannels stalls on a dead TCP connection or when the
    /// App request is slow. Should be well below the default fetchAppInfos timeout (~25s).
    private static let autoReconnectFetchTimeoutSec: RxTimeInterval = .seconds(10)

    private let switchStatusRelay = BehaviorRelay<SwitchStatus>(value: .idle)
    public var switchStatusObservable: Observable<SwitchStatus> { switchStatusRelay.asObservable() }

    private let switchSuccessRelay = PublishRelay<SwitchSuccess>()
    public var switchSuccessObservable: Observable<SwitchSuccess> { switchSuccessRelay.asObservable() }

    private let switchFailureRelay = PublishRelay<Error>()
    public var switchFailureObservable: Observable<Error> { switchFailureRelay.asObservable() }

    private var currentSwitchDisposeBag = DisposeBag()

    private override init() {
        super.init()
        setupAutoReconnect()
    }

    /// Ends the current inspect session and closes Peertalk so the demo can accept a new client.
    public func endInspectingSession() {
        autoReconnectDisposeBag = DisposeBag()
        AVStaticAsyncUpdateManager.sharedInstance.endUpdating()
        inspectingApp?.cancelHierarchyDetailFetching()
        let channel = inspectingApp?.channel
        let hadActiveInspection = inspectingApp != nil
        inspectingApp = nil
        AVConnectionManager.sharedInstance.cancelAllActivePeerRequests()
        if let channel {
            AVConnectionManager.sharedInstance.releaseCachedChannel(channel)
        }
        if hadActiveInspection {
            AVConnectionManager.sharedInstance.releaseAllDiscoveryChannels()
        }
        AVConnectionManager.sharedInstance.clearMCPSessionSnapshots()
        AVStaticHierarchyDataSource.sharedInstance.clearSessionHierarchy()
    }

    /// Re-discovers simulator/USB apps with a fresh Peertalk scan (use on toolbar Reload after switching demo).
    public func fetchAppInfosForReload(localInfos: [AppViewAppInfo]? = nil) -> Single<[AVInspectableApp]> {
        if let channel = inspectingApp?.channel {
            AVConnectionManager.sharedInstance.releaseCachedChannel(channel)
        }
        return fetchAppInfos(withImage: false, localInfos: localInfos, forceFreshDiscovery: true)
    }

    /// Re-fetch hierarchy on the live channel, or reattach to the same app when Peertalk dropped (USB watchdog / Mac quit).
    public func fetchHierarchyDataForReload(from app: AVInspectableApp) -> Single<AppViewHierarchyInfo> {
        guard let targetInfo = app.appInfo else {
            return .error(AVAppViewClientErrors.inner)
        }
        let wantsUSB = Self.inspectSessionUsesUSB(app)
        intentionalSessionChange = true

        return prepareInspectableChannel(app.channel)
            .andThen(
                Single.deferred { [self] in
                    let conn = AVConnectionManager.sharedInstance
                    let reloadSingle: Single<(AVInspectableApp, AppViewHierarchyInfo)>
                    if let channel = app.channel, channel.isConnected {
                        conn.releaseDiscoveryChannels(except: channel)
                        reloadSingle = app.fetchHierarchyData(scanLayoutIssues: true)
                            .map { (app, $0) }
                            .catch { [weak self] _ -> Single<(AVInspectableApp, AppViewHierarchyInfo)> in
                                guard let self else { return .error(AVAppViewClientErrors.noConnect) }
                                AppViewDiagLog.log(
                                    "client reload: live hierarchy failed — reattach usb=\(wantsUSB)"
                                )
                                return self.fetchHierarchyAfterRediscover(
                                    matching: app,
                                    targetInfo: targetInfo,
                                    wantsUSB: wantsUSB
                                )
                            }
                    } else {
                        AppViewDiagLog.log("client reload: channel down — reattach usb=\(wantsUSB)")
                        reloadSingle = self.fetchHierarchyAfterRediscover(
                            matching: app,
                            targetInfo: targetInfo,
                            wantsUSB: wantsUSB
                        )
                    }
                    return reloadSingle
                }
            )
            .do(onSuccess: { [weak self] fresh, _ in
                self?.inspectingApp = fresh
            })
            .map { $0.1 }
            .do(onDispose: { [weak self] in
                self?.intentionalSessionChange = false
            })
    }

    /// Picks the app to inspect after reload. Returns nil when multiple apps are running and none matches the current session.
    public func pickInspectableAppForReload(
        current: AVInspectableApp?,
        from apps: [AVInspectableApp],
        wantsUSB: Bool? = nil
    ) -> AVInspectableApp? {
        let conn = AVConnectionManager.sharedInstance
        var usable = apps.filter { $0.serverVersionError == nil && $0.appInfo != nil }
        if let wantsUSB {
            usable = usable.filter { conn.channelUsesUSB($0.channel) == wantsUSB }
        }
        guard !usable.isEmpty else { return nil }
        if usable.count == 1 { return usable[0] }
        if let current,
           let match = usable.first(where: { Self.isSameInspectableSession(current, $0) }) {
            return match
        }
        if wantsUSB == false, let currentPort = current?.channel?.targetPort, currentPort > 0 {
            return usable.first { $0.channel?.targetPort == currentPort }
        }
        return nil
    }

    private static let fetchAppInfosLock = NSLock()
    private static let fetchAppInfosQueue = DispatchQueue(label: "appview.client.fetchAppInfos", qos: .userInitiated)
    private static var fetchLockAcquiredAt: TimeInterval?

    static func mcpFetchBlockedAgeSec() -> TimeInterval {
        guard let acquired = fetchLockAcquiredAt else { return 0 }
        return Date().timeIntervalSince1970 - acquired
    }

    public func fetchAppInfos(
        withImage needImages: Bool,
        localInfos: [AppViewAppInfo]?,
        forceFreshDiscovery: Bool = false,
        usbOnly: Bool? = nil
    ) -> Single<[AVInspectableApp]> {
        let transportFilter: AVInspectTransportFilter?
        switch usbOnly {
        case true?: transportFilter = .usb
        case false?: transportFilter = .simulator
        default: transportFilter = nil
        }
        return Single.deferred { [self] in
            Single.create { observer in
                var terminated = false
                let terminate: (Result<[AVInspectableApp], Error>) -> Void = { result in
                    guard !terminated else { return }
                    terminated = true
                    switch result {
                    case .success(let apps):
                        observer(.success(apps))
                    case .failure(let error):
                        observer(.failure(error))
                    }
                }
                var innerDisposable: Disposable?
                let work = DispatchWorkItem { [self] in
                    let lockWaitStart = CFAbsoluteTimeGetCurrent()
                    Self.fetchAppInfosLock.lock()
                    if AVConnectionTiming.isEnabled {
                        let waitMs = Int((CFAbsoluteTimeGetCurrent() - lockWaitStart) * 1000)
                        AVConnectionTiming.shared.recordInstant("fetchAppInfos.waitLock", durationMs: waitMs)
                    }
                    Self.fetchLockAcquiredAt = Date().timeIntervalSince1970
                    innerDisposable = self.fetchAppInfosUnlocked(
                        withImage: needImages,
                        localInfos: localInfos,
                        forceFreshDiscovery: forceFreshDiscovery,
                        transportFilter: transportFilter
                    )
                    .do(onDispose: {
                        Self.fetchAppInfosLock.unlock()
                        Self.fetchLockAcquiredAt = nil
                    })
                    .subscribe(
                        onSuccess: { terminate(.success($0)) },
                        onFailure: { terminate(.failure($0)) }
                    )
                }
                Self.fetchAppInfosQueue.async(execute: work)
                return Disposables.create {
                    work.cancel()
                    innerDisposable?.dispose()
                    terminate(.failure(AVAppViewClientErrors.discard()))
                }
            }
        }
    }

    /// Restart read loop on async Peertalk before toolbar reload / rediscover.
    private func prepareInspectableChannel(_ channel: AVPeerChannel?) -> Completable {
        Completable.create { done in
            guard let async = channel as? AVAsyncPeerChannel else {
                done(.completed)
                return Disposables.create()
            }
            Task {
                await async.reconcileTransportState()
                done(.completed)
            }
            return Disposables.create()
        }
    }

    private func fetchAppInfosUnlocked(
        withImage needImages: Bool,
        localInfos: [AppViewAppInfo]?,
        forceFreshDiscovery: Bool = false,
        transportFilter: AVInspectTransportFilter? = nil
    ) -> Single<[AVInspectableApp]> {
        let validAppInfos = (localInfos ?? []).filter { info in
            guard Date().timeIntervalSince1970 - info.cachedTimestamp <= 8 else { return false }
            // iOS returns shouldUseCache when localIdentifiers match — that stub has no screenshot.
            if needImages, info.screenshot == nil { return false }
            return true
        }
        let localInfoIdentifiers = validAppInfos.map { NSNumber(value: $0.appInfoIdentifier) }
        let appParams = WireAppRequestParams(
            needImages: needImages,
            localIdentifiers: localInfoIdentifiers.map(\.uintValue)
        )

        AVConnectionTiming.shared.begin("discover.fetchAppInfos", attrs: ["fresh": forceFreshDiscovery])
        return AVConnectionManager.sharedInstance.tryToConnectAllPorts(forceFreshDiscovery: forceFreshDiscovery)
            .flatMap { connectedChannels -> Single<[AVInspectableApp]> in
                let scopedChannels: [AVPeerChannel]
                if let transportFilter {
                    scopedChannels = Self.filterChannels(connectedChannels, transport: transportFilter)
                    if scopedChannels.isEmpty {
                        let tag = AVMCPChannelTag(usb: transportFilter == .usb).rawValue
                        AppViewDiagLog.log(
                            "client fetchAppInfos: 0 \(tag) channel(s) after transport filter (connected=\(connectedChannels.count))"
                        )
                    }
                } else {
                    scopedChannels = connectedChannels
                }
                guard !scopedChannels.isEmpty else {
                    AppViewDiagLog.log("client fetchAppInfos: no Peertalk channels (run the iOS app; the AppViewServer pod listens on launch)")
                    return .just([])
                }
                let liveChannels = scopedChannels.filter(\.isConnected)
                if liveChannels.isEmpty {
                    let ports = scopedChannels.map { String($0.targetPort) }.joined(separator: ",")
                    AppViewDiagLog.log(
                        "client fetchAppInfos: \(scopedChannels.count) channel(s) ports=[\(ports)] but none connected"
                    )
                    return .just([])
                }

                let discoverPerChannelTimeout = AVWireClientRequestTimeout.appInfo
                    + AVWireClientRequestTimeout.preflightPingBeforeApp
                    + 2
                let requestSingles: [Single<AVInspectableApp?>] = liveChannels.map { [weak self] channel in
                    // The active inspection channel is busy streaming hierarchy data (AppViewRequestTypeHierarchy)
                    // and won't respond to a new AppViewRequestTypeApp — request times out with code -405.
                    // Reuse the already-known app info instead of sending a fresh discovery request.
                    if let inspecting = self?.inspectingApp,
                       inspecting.channel === channel,
                       let cachedInfo = inspecting.appInfo,
                       !needImages || cachedInfo.screenshot != nil {
                        let reuse = AVInspectableApp()
                        reuse.appInfo = cachedInfo
                        reuse.channel = channel
                        AppViewDiagLog.log(
                            "client fetchAppInfos: reuse cached app info for active inspection channel port=\(channel.targetPort)"
                        )
                        return .just(reuse)
                    }
                    let portNum = channel.targetPort
                    if AVConnectionTiming.isEnabled {
                        AVConnectionTiming.shared.begin(
                            "discover.appRequest.port",
                            attrs: ["port": portNum]
                        )
                    }
                    return AVConnectionManager.sharedInstance.request(
                        withType: UInt32(AppViewRequestTypeApp),
                        data: nil,
                        channel: channel,
                        wirePayload: .app(appParams)
                    )
                    .take(1)
                    .timeout(.seconds(Int(discoverPerChannelTimeout)), scheduler: MainScheduler.instance)
                    .asSingle()
                    .map { pair -> AVInspectableApp? in
                        if AVConnectionTiming.isEnabled {
                            AVConnectionTiming.shared.end(
                                "discover.appRequest.port",
                                attrs: ["port": portNum, "ok": true]
                            )
                        }
                        return Self.inspectableApp(
                            from: pair,
                            validAppInfos: validAppInfos,
                            channel: channel,
                            needImages: needImages
                        )
                    }
                    .catch { error in
                        if AVConnectionTiming.isEnabled {
                            AVConnectionTiming.shared.end(
                                "discover.appRequest.port",
                                attrs: ["port": portNum, "ok": false]
                            )
                        }
                        let nsError = error as NSError
                        let port = channel.targetPort
                        if nsError.code == AppViewErrCode_ServerVersionTooHigh || nsError.code == AppViewErrCode_ServerVersionTooLow {
                            AppViewDiagLog.log(
                                "client App request version mismatch port=\(port) code=\(nsError.code)"
                            )
                            let app = AVInspectableApp()
                            app.serverVersionError = nsError
                            return .just(app)
                        }
                        AppViewDiagLog.log(
                            "client App request FAIL port=\(port) code=\(nsError.code) \(nsError.localizedDescription)"
                        )
                        return .just(nil)
                    }
                }

                return Single.zip(requestSingles)
                    .map { results in
                        // Deduplicate by appInfoIdentifier: multiple channels to the same iOS
                        // process (auto-reconnect channel + launch-screen scan, or concurrent
                        // Peertalk accepts during simulator swap) each return an identical App
                        // response, producing duplicate tiles.  Keep the first per identifier.
                        var seenIDs = Set<UInt>()
                        let unwrapped: [AVInspectableApp] = results.compactMap { $0 }
                        let apps = unwrapped.filter { app in
                            guard let info = app.appInfo else { return true }
                            return seenIDs.insert(info.appInfoIdentifier).inserted
                        }
                        let usable = apps.filter { $0.serverVersionError == nil && $0.appInfo != nil }
                        if usable.isEmpty, !liveChannels.isEmpty {
                            let ports = liveChannels.map { String($0.targetPort) }.joined(separator: ",")
                            AppViewDiagLog.log(
                                "client fetchAppInfos: 0 apps from \(liveChannels.count) channel(s) ports=[\(ports)] — run the iOS app with the AppViewServer pod (it listens on launch) and bring it to the foreground"
                            )
                        }
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
                        let summary: [String: Any] = [
                            "usableAppCount": usable.count,
                            "rawAppCount": apps.count,
                            "appNames": usable.compactMap { $0.appInfo?.appName },
                            "bundleIds": usable.compactMap { $0.appInfo?.appBundleIdentifier },
                            "channels": channels,
                            "channelCount": AVConnectionManager.sharedInstance.mcpLastConnectSnapshot?.channelCount ?? 0,
                            "timestamp": Date().timeIntervalSince1970,
                        ]
                        AVMCPClientDiagnostics.shared.recordDiscoverSummary(summary)
                        return apps
                    }
            }
            .do(
                onSuccess: { apps in
                    AVConnectionTiming.shared.end(
                        "discover.fetchAppInfos",
                        attrs: ["usable": Self.usableInspectableApps(from: apps).count]
                    )
                },
                onError: { _ in
                    AVConnectionTiming.shared.end("discover.fetchAppInfos", attrs: ["error": true])
                }
            )
    }

    /// Screenshots for app-switcher tiles shown without one. The inspected app reuses its key window screenshot
    /// from the loaded hierarchy: its channel is busy with hierarchy traffic and would not answer an App request.
    /// Other apps are asked on their own channel without `fetchAppInfosLock`, so Reload is never held up.
    public func loadPopoverScreenshots(for apps: [AVInspectableApp]) -> Single<[AVInspectableApp]> {
        var filled: [AVInspectableApp] = []
        var requests: [Single<AVInspectableApp?>] = []
        for app in apps {
            guard let info = app.appInfo, info.screenshot == nil, let channel = app.channel else { continue }
            if let inspecting = inspectingApp,
               channel === inspecting.channel || Self.isSameInspectableSession(inspecting, app) {
                guard let screenshot = Self.inspectedKeyWindowScreenshot(),
                      let copy = info.copy() as? AppViewAppInfo else { continue }
                copy.screenshot = screenshot
                let filledApp = AVInspectableApp()
                filledApp.appInfo = copy
                filledApp.channel = channel
                filled.append(filledApp)
                continue
            }
            guard channel.isConnected else { continue }
            requests.append(
                AVConnectionManager.sharedInstance.request(
                    withType: UInt32(AppViewRequestTypeApp),
                    data: nil,
                    channel: channel,
                    wirePayload: .app(WireAppRequestParams(needImages: true))
                )
                .take(1)
                .timeout(.seconds(Int(AVWireClientRequestTimeout.appInfo)), scheduler: MainScheduler.instance)
                .asSingle()
                .map { Self.inspectableApp(from: $0, validAppInfos: [], channel: channel, needImages: true) }
                .catch { _ in .just(nil) }
            )
        }
        guard !requests.isEmpty else { return .just(filled) }
        return Single.zip(requests).map { filled + $0.compactMap { $0 } }
    }

    private static func inspectedKeyWindowScreenshot() -> AppViewImage? {
        let roots = AVStaticHierarchyDataSource.sharedInstance.rawHierarchyInfo?.displayItems ?? []
        let window = roots.first(where: \.representedAsKeyWindow) ?? roots.first
        return window?.groupScreenshot ?? window?.soloScreenshot
    }

    private static func inspectableApp(
        from pair: AppViewPair,
        validAppInfos: [AppViewAppInfo],
        channel: AVPeerChannel,
        needImages: Bool = false
    ) -> AVInspectableApp? {
        guard let response = pair.first as? AppViewConnectionResponseAttachment,
              let relatedChannel = pair.second as? AVPeerChannel else {
            NSLog(
                "AppViewClient - App discovery unexpected zip item: %@",
                String(describing: type(of: pair.first as Any))
            )
            return nil
        }
        if let wireError = response.error {
            NSLog(
                "AppViewClient - App request wire error: %@",
                wireError.localizedDescription
            )
            return nil
        }
        guard let receivedInfo = response.data as? AppViewAppInfo else {
            NSLog(
                "AppViewClient - App request unexpected data type: %@",
                String(describing: type(of: response.data as Any))
            )
            return nil
        }
        var infoToUse = receivedInfo
        receivedInfo.cachedTimestamp = Date().timeIntervalSince1970
        if receivedInfo.shouldUseCache,
           let localInfo = validAppInfos.first(where: {
               $0.appInfoIdentifier == receivedInfo.appInfoIdentifier
           }),
           !needImages || localInfo.screenshot != nil {
            infoToUse = localInfo
        }

        let app = AVInspectableApp()
        app.appInfo = infoToUse
        app.channel = relatedChannel
        return app
    }

    private func tryToConnectAllPorts() -> Single<[AVPeerChannel]> {
        AVConnectionManager.sharedInstance.tryToConnectAllPorts()
    }

    private func setupAutoReconnect() {
        AVConnectionManager.sharedInstance.channelWillEnd
            .subscribe(with: self) { owner, channel in
                if owner.intentionalSessionChange { return }
                // Suppress during any busy state (.fetchingAppList or .connecting): those flows
                // release channels intentionally and will restore the session themselves.
                if owner.switchStatusRelay.value.isBusy { return }
                guard channel === owner.inspectingApp?.channel else { return }

                NSLog("AppViewClient - connection dropped, starting auto-reconnect")
                if AVConnectionManager.sharedInstance.isSimulatorPeertalkPort(channel.targetPort) {
                    AVConnectionManager.invalidateBootedSimulatorCache()
                }

                let targetSession = owner.inspectingApp
                owner.inspectingApp = nil
                owner.autoReconnectMissCount = 0
                owner.startAutoReconnectLoop(for: targetSession)
            }
            .disposed(by: disposeBag)
    }

    private func startAutoReconnectLoop(for session: AVInspectableApp?) {
        autoReconnectDisposeBag = DisposeBag()

        // Stop signal: fires when the user initiates a new manual connection.
        let stopSignal: Observable<Void> = willConnectToAppRelay.map { _ in () }

        // Merge polling ticks and serverReady pushes into one trigger stream.
        // A single flatMap(maxConcurrent: 1) ensures at most one fetchInspectableApp runs at
        // a time, preventing concurrent lock acquisitions in fetchAppInfos that could leave
        // the lock held when the losing subscription is disposed by stopSignal.
        let pollTrigger = Observable<Int>.interval(Self.autoReconnectIntervalSec, scheduler: MainScheduler.instance)
            .take(Self.autoReconnectMaxAttempts)
            .map { _ in () }

        let serverReadyTrigger = AVConnectionManager.sharedInstance.didReceivePush
            .filter { ($0.second as? NSNumber)?.uint32Value == AppViewWirePushTypes.serverReady }
            .map { _ in () }

        Observable.merge(pollTrigger, serverReadyTrigger)
            .take(until: stopSignal)
            .flatMapFirst { [weak self] _ -> Observable<AVInspectableApp> in
                guard let self else { return .empty() }
                self.autoReconnectMissCount += 1
                // Use fresh discover immediately: after a channel drop the old Peertalk
                // binding is gone, so a normal purge-and-reuse (attempt 1) would just
                // re-scan dead ports. Fresh discover closes stale channels and rescans right away.
                let useFresh = self.autoReconnectMissCount >= 1
                AVConnectionTiming.shared.begin(
                    "autoReconnect.attempt",
                    attrs: ["attempt": self.autoReconnectMissCount, "fresh": useFresh]
                )
                return self.fetchInspectableApp(matching: session, forceFreshDiscovery: useFresh)
                    .timeout(Self.autoReconnectFetchTimeoutSec, scheduler: MainScheduler.instance)
                    .asObservable()
                    .do(onNext: { [weak self] _ in
                        AVConnectionTiming.shared.end("autoReconnect.attempt", attrs: ["ok": true])
                        self?.autoReconnectMissCount = 0
                    }, onError: { [weak self] _ in
                        AVConnectionTiming.shared.end("autoReconnect.attempt", attrs: ["ok": false])
                        _ = self?.autoReconnectMissCount
                    })
                    .catch { _ in .empty() }
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] newApp in
                guard let self else { return }
                NSLog("AppViewClient - auto-reconnect succeeded")
                self.inspectingApp = newApp
                self.didAutoReconnectSuccRelay.accept(())
            })
            .disposed(by: autoReconnectDisposeBag)
    }

    private func fetchInspectableApp(
        matching session: AVInspectableApp?,
        forceFreshDiscovery: Bool = false
    ) -> Single<AVInspectableApp> {
        guard let session, let appInfo = session.appInfo else {
            return .error(AVAppViewClientErrors.inner)
        }
        let wasUSB = Self.inspectSessionUsesUSB(session)
        return fetchAppInfos(
            withImage: false,
            localInfos: [appInfo],
            forceFreshDiscovery: forceFreshDiscovery,
            usbOnly: wasUSB
        )
            .flatMap { allApps -> Single<AVInspectableApp> in
                let conn = AVConnectionManager.sharedInstance
                guard let targetApp = allApps.first(where: { candidate in
                    guard appInfo.isEqual(toAppInfo: candidate.appInfo) else { return false }
                    return conn.channelUsesUSB(candidate.channel) == wasUSB
                }) ?? self.pickInspectableAppForReload(current: session, from: allApps, wantsUSB: wasUSB) else {
                    return .error(AVAppViewClientErrors.inner)
                }
                targetApp.appInfo?.appIcon = appInfo.appIcon
                return .just(targetApp)
            }
    }
}
