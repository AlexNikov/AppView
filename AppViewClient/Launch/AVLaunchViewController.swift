//
//  AVLaunchViewController.swift
//  AppView
//

import AppKit
import AppViewShared
import RxSwift

class AVLaunchViewController: AVBaseViewController {
    private weak var hostWindow: NSWindow?
    private var appViews: [AVLaunchAppView] = []
    private var bottomIndicatorView: AVProgressIndicatorView!
    private var reloadingIndicator: NSProgressIndicator?
    private var noAppsTitleLabel: AVLabel?
    private var isEnteringApp = false
    private var enteringStartedAt: Date?
    private var lastFetchCompletedAt: Date?
    private var appInfos: [AppViewAppInfo] = []
    private var appDiscoveryTimer: DispatchSourceTimer?
    private var appDiscoveryPollCount = 0
    private var appDiscoveryFetchDisposable: Disposable?
    private static let appDiscoveryMaxPolls = 45

    private let appViewInterSpace: CGFloat = 10
    private let contentHorInset: CGFloat = 30
    private let contentHeight: CGFloat = 400

    private let disposeBag = DisposeBag()

    init(window: NSWindow) {
        hostWindow = window
        super.init(containerView: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func makeContainerView() -> NSView {
        let containerView = AVVisualEffectView()
        containerView.blendingMode = .behindWindow
        containerView.state = .active

        appViews = []

        bottomIndicatorView = AVProgressIndicatorView()
        containerView.addSubview(bottomIndicatorView)

        bottomIndicatorView.animate(toProgress: 0.7, duration: 0.5)

        DispatchQueue.main.asyncAfter(deadline: .now() + AVUITiming.brief) { [weak self] in
            self?.reloadWithAutoEntering(true)
        }

        return containerView
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        if let reloadingIndicator, let noAppsTitleLabel {
            reloadingIndicator.sizeToFit()
            noAppsTitleLabel.sizeToFit()

            let midY = view.bounds.height * 0.35
            let groupWidth = reloadingIndicator.frame.width + 5 + noAppsTitleLabel.frame.width
            var x = (view.bounds.width - groupWidth) / 2
            reloadingIndicator.frame.origin = NSPoint(x: x, y: midY - reloadingIndicator.frame.height / 2)
            x = reloadingIndicator.frame.maxX + 5
            noAppsTitleLabel.frame.origin = NSPoint(
                x: x,
                y: midY - noAppsTitleLabel.frame.height / 2
            )
        }

        var posX = contentHorInset
        for appView in appViews {
            appView.sizeToFit()
            appView.frame.origin = NSPoint(x: posX, y: 30)
            posX = appView.frame.maxX + appViewInterSpace
        }

        bottomIndicatorView.frame = NSRect(
            x: 0,
            y: 0,
            width: view.bounds.width,
            height: 3
        )
    }

    /// MCP: refresh launch tiles without auto-entering inspector.
    /// Bypasses the `isMcpOperationInProgress` guard — the caller (refreshLaunchTargets) holds
    /// that flag itself, so the normal guard would make this a permanent no-op.
    func mcpReloadWithoutAutoEnter() {
        stopAppDiscoveryPolling()
        reloadWithAutoEntering(false, bypassMCPInProgressCheck: true)
    }

    /// MCP select/refresh: pause background discover polling to avoid fetchAppInfos lock contention.
    func mcpPauseDiscoveryPolling() {
        stopAppDiscoveryPolling()
        cancelInFlightAppDiscoveryFetch()
    }

    private func cancelInFlightAppDiscoveryFetch() {
        appDiscoveryFetchDisposable?.dispose()
        appDiscoveryFetchDisposable = nil
    }

    /// MCP launch-health snapshot (freeze detection inputs).
    func mcpLaunchScreenSnapshot() -> [String: Any] {
        let visibleTiles = appViews.filter { !$0.isHidden && $0.app != nil }
        let now = Date()
        var snapshot: [String: Any] = [
            "isEnteringApp": isEnteringApp,
            "isPolling": appDiscoveryTimer != nil,
            "pollCount": appDiscoveryPollCount,
            "tileCount": visibleTiles.count,
            "showsSearchingUI": noAppsTitleLabel != nil,
            "progress": bottomIndicatorView?.progress ?? 0,
        ]
        if let enteringStartedAt {
            snapshot["enteringAgeSec"] = now.timeIntervalSince(enteringStartedAt)
        } else {
            snapshot["enteringAgeSec"] = 0
        }
        if let lastFetchCompletedAt {
            snapshot["secondsSinceLastFetch"] = now.timeIntervalSince(lastFetchCompletedAt)
        } else {
            snapshot["secondsSinceLastFetch"] = -1
        }
        return snapshot
    }

    /// Automation: open inspector by activating the demo app tile (or the only visible tile).
    func appview_mcpTryEnterInspector() {
        if isEnteringApp { return }
        guard bottomIndicatorView != nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + AVUITiming.launchAppsReveal) { [weak self] in
                self?.appview_mcpTryEnterInspector()
            }
            return
        }

        cancelInFlightAppDiscoveryFetch()
        appDiscoveryFetchDisposable = AppViewRACSignalRx.observeMainThread(
            AVAppsManager.sharedInstance.fetchAppInfos(withImage: true, localInfos: appInfos)
        )
        .subscribe(with: self, onSuccess: { owner, apps in
            guard let app = AVAppsManager.preferredInspectableApp(from: apps) else { return }
            if owner.appViews.isEmpty {
                owner.renderWithApps(apps)
            }
            owner.enterApp(app)
        })
    }

    private func reloadWithAutoEntering(
        _ autoEnter: Bool,
        bypassMCPInProgressCheck: Bool = false,
        forceFreshDiscovery: Bool = false
    ) {
        if isEnteringApp { return }
        if !bypassMCPInProgressCheck && AVMCPClientDiagnostics.shared.isMcpOperationInProgress { return }

        cancelInFlightAppDiscoveryFetch()
        // While searching (no tiles yet) always skip images regardless of forceFreshDiscovery:
        // a cold App response with screenshots blocks fetchAppInfosLock for 10-15 s, which
        // stalls auto-enter significantly after a simulator swap or "Select App" from inspector.
        // Once an app is found and tiles are displayed the next poll re-fetches with images from
        // the server cache (cache is warm by then, response is fast).
        let needImages = !appViews.isEmpty && !forceFreshDiscovery
        AVConnectionTiming.shared.begin(
            "launch.discover",
            attrs: ["fresh": forceFreshDiscovery, "autoEnter": autoEnter, "img": needImages]
        )
        appDiscoveryFetchDisposable = AppViewRACSignalRx.observeMainThread(
            AVAppsManager.sharedInstance.fetchAppInfos(
                withImage: needImages,
                localInfos: appInfos,
                forceFreshDiscovery: forceFreshDiscovery
            )
        )
        .subscribe(with: self, onSuccess: { owner, apps in
            AVConnectionTiming.shared.end("launch.discover", attrs: ["count": apps.count])
            owner.handleFetchedApps(apps, autoEnter: autoEnter)
        }, onFailure: { owner, _ in
            AVConnectionTiming.shared.end("launch.discover", attrs: ["error": true])
            owner.handleFetchedApps([], autoEnter: autoEnter)
        })
    }

    private func handleFetchedApps(_ apps: [AVInspectableApp], autoEnter: Bool) {
        if isEnteringApp { return }
        lastFetchCompletedAt = Date()
        appInfos = apps.compactMap { $0.appInfo }
        let usableApps = apps.filter { $0.serverVersionError == nil && $0.appInfo != nil }
        let names = usableApps.compactMap { $0.appInfo?.appName }.joined(separator: ", ")
        let deferUSB = AVConnectionManager.sharedInstance.shouldDeferLaunchAutoEnterForPendingUSB(
            usableApps: usableApps
        )
        AppViewDiagLog.log(
            "client launch found apps=\(usableApps.count) [\(names)] autoEnter=\(autoEnter) deferUSB=\(deferUSB)"
        )
        if AVConnectionTiming.isEnabled, !usableApps.isEmpty {
            let withScreenshot = usableApps.filter { $0.appInfo?.screenshot != nil }.count
            AVConnectionTiming.shared.recordInstant(
                "preview.launchTile",
                durationMs: 0,
                attrs: ["usable": usableApps.count, "withScreenshot": withScreenshot]
            )
        }

        let displayApps = AVAppsManager.appsForLaunchDisplay(discovered: apps)

        if autoEnter, !deferUSB {
            let appToEnter = AVAppsManager.preferredAppForLaunchAutoEnter(from: apps)
            if let appToEnter {
                stopAppDiscoveryPolling()
                renderWithApps(displayApps)
                enterApp(appToEnter)
                return
            }
        }

        if bottomIndicatorView.progress > 0, !deferUSB {
            bottomIndicatorView.finish(completion: nil)
        }
        renderWithApps(displayApps)

        let missingScreenshots = Self.usableAppsMissingScreenshots(usableApps)
        if (usableApps.isEmpty || deferUSB || missingScreenshots), !isEnteringApp {
            if missingScreenshots, !usableApps.isEmpty, !deferUSB {
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isEnteringApp else { return }
                    self.reloadWithAutoEntering(false)
                }
            }
            scheduleAppDiscoveryPolling()
        } else {
            stopAppDiscoveryPolling()
        }
    }

    /// MCP / automation: tiles are visible but first discover skipped images — fetch previews now.
    func reloadLaunchTilePreviews() {
        guard !appViews.isEmpty, !isEnteringApp else { return }
        reloadWithAutoEntering(false, bypassMCPInProgressCheck: true)
    }

    private static func usableAppsMissingScreenshots(_ apps: [AVInspectableApp]) -> Bool {
        apps.contains { app in
            guard app.serverVersionError == nil, app.appInfo != nil else { return false }
            if app.isLaunchUSBPendingPlaceholder { return false }
            return app.appInfo?.screenshot == nil
        }
    }

    /// Keep scanning simulator/USB ports while the launch screen shows “Searching…” (demo may start after AppView).
    private func scheduleAppDiscoveryPolling() {
        guard appDiscoveryTimer == nil else { return }
        appDiscoveryPollCount = 0
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + AVUITiming.launchPollInterval, repeating: AVUITiming.launchPollInterval)
        timer.setEventHandler { [weak self] in
            guard let self, !self.isEnteringApp else {
                self?.stopAppDiscoveryPolling()
                return
            }
            if AVMCPClientDiagnostics.shared.isMcpOperationInProgress {
                return
            }
            self.appDiscoveryPollCount += 1
            let waitingForUSB = AVConnectionManager.sharedInstance.hasAttachedUSBDevices
            if self.appDiscoveryPollCount > Self.appDiscoveryMaxPolls, !waitingForUSB {
                self.stopAppDiscoveryPolling()
                return
            }
            // Auto-enter only before any tile is shown; deferUSB in handleFetchedApps waits for USB demo.
            // The iOS pod listens on Peertalk by itself. A full relisten every few polls drops that socket.
            self.reloadWithAutoEntering(self.appViews.isEmpty, forceFreshDiscovery: false)
        }
        timer.resume()
        appDiscoveryTimer = timer
    }

    private func stopAppDiscoveryPolling() {
        appDiscoveryTimer?.cancel()
        appDiscoveryTimer = nil
        appDiscoveryPollCount = 0
    }

    @objc
    private func handleClickAppView(_ view: AVLaunchAppView) {
        if isEnteringApp { return }

        guard let app = view.app else { return }

        if app.isLaunchUSBPendingPlaceholder || app.channel == nil {
            guard let window = resolvedWindow else { return }
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("No inspectable app on this iPhone yet", comment: "")
            alert.informativeText = NSLocalizedString(
                "Launch your iOS app with AppViewServer on the device (Xcode Run), then return here.",
                comment: ""
            )
            alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
            alert.beginSheetModal(for: window)
            reloadWithAutoEntering(false)
            return
        }

        if let error = app.serverVersionError as NSError? {
            AVHelper.presentError(error, window: resolvedWindow)
            return
        }

        bottomIndicatorView.animate(toProgress: 0.8, duration: 1)
        enterApp(app)
    }

    private func renderWithApps(_ apps: [AVInspectableApp]?) {
        let apps = apps.map { AVAppsManager.sortedForDisplay($0) }
        guard let apps, !apps.isEmpty else {
            resolvedWindow?.setContentSize(NSSize(width: 256, height: contentHeight))
            showNoAppsView()
            appViews.forEach { $0.isHidden = true }
            return
        }

        var windowWidth = contentHorInset * 2 + CGFloat(apps.count - 1) * appViewInterSpace
        appViews = resizeAppViews(count: apps.count, apps: apps, windowWidth: &windowWidth)
        appViews.forEach { $0.isHidden = false }

        resolvedWindow?.setContentSize(NSSize(width: windowWidth, height: contentHeight))
        hideNoAppsViews()
        view.needsLayout = true
    }

    private func resizeAppViews(
        count: Int,
        apps: [AVInspectableApp],
        windowWidth: inout CGFloat
    ) -> [AVLaunchAppView] {
        var views = appViews

        while views.count < count {
            let view = AVLaunchAppView()
            self.view.addSubview(view)
            views.append(view)
        }
        while views.count > count {
            views.removeLast().removeFromSuperview()
        }

        for (idx, view) in views.enumerated() {
            view.app = apps[idx]
            view.addTarget(self, clickAction: #selector(handleClickAppView(_:)))
            windowWidth += view.sizeThatFits(
                NSSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                )
            ).width
        }

        return views
    }

    private func enterApp(_ app: AVInspectableApp) {
        if isEnteringApp { return }
        stopAppDiscoveryPolling()
        isEnteringApp = true
        enteringStartedAt = Date()

        AVPerformanceReporter.sharedInstance.willStartReload()

        AppViewRACSignalRx.observeMainThread(
            AVAppsManager.sharedInstance.connectInspectableApp(app)
        )
            .subscribe(with: self, onSuccess: { owner, pair in
                let (freshApp, info) = pair
                owner.handleEnterAppSuccess(app: freshApp, info: info)
                AVPerformanceReporter.sharedInstance.didFetchHierarchy()
            }, onFailure: { owner, error in
                owner.handleEnterAppFail(with: (error as NSError?) ?? AVAppViewClientErrors.inner)
            })
            .disposed(by: disposeBag)
    }

    private func handleEnterAppSuccess(app: AVInspectableApp, info: AppViewHierarchyInfo) {
        isEnteringApp = false
        enteringStartedAt = nil
        AVAppsManager.sharedInstance.inspectingApp = app
        AVStaticHierarchyDataSource.sharedInstance.reload(with: info, keepState: false)

        let openInspector = { [weak self] in
            AVNavigationManager.sharedInstance.showStaticWorkspace()
            AVNavigationManager.sharedInstance.closeLaunch()
            _ = self
        }
        // Do not block inspector on progress-bar animation (MCP verify / headless runs).
        openInspector()
        bottomIndicatorView.finish(completion: nil)
    }

    private func handleEnterAppFail(with error: NSError) {
        isEnteringApp = false
        enteringStartedAt = nil
        bottomIndicatorView.resetToZero()
        guard let window = resolvedWindow else { return }
        NSAlert(error: error).beginSheetModal(for: window) { [weak self] _ in
            self?.reloadWithAutoEntering(false)
        }
    }

    private func showNoAppsView() {
        if noAppsTitleLabel == nil {
            let label = AVLabel()
            label.textColor = .labelColor
            label.font = NSFont.systemFont(ofSize: 14)
            label.stringValue = NSLocalizedString("Searching for inspectable apps", comment: ""
            )
            view.addSubview(label)
            noAppsTitleLabel = label
        }
        if reloadingIndicator == nil {
            let indicator = NSProgressIndicator()
            indicator.isIndeterminate = true
            indicator.style = .spinning
            indicator.controlSize = .small
            view.addSubview(indicator)
            indicator.startAnimation(self)
            reloadingIndicator = indicator
        }
        view.needsLayout = true
    }

    private func hideNoAppsViews() {
        noAppsTitleLabel?.removeFromSuperview()
        noAppsTitleLabel = nil

        reloadingIndicator?.removeFromSuperview()
        reloadingIndicator = nil
    }

    private var resolvedWindow: NSWindow? {
        hostWindow ?? view.window
    }

    deinit {
        stopAppDiscoveryPolling()
    }
}
