//
//  AVStaticWindowController+MCPAppSwitcher.swift
//  AppView
//
//  MCP automation: toolbar app-switcher popover.
//

import AppKit
import AppViewShared
import RxSwift

extension AVStaticWindowController {
    /// `loadScreenshots`: the list came without screenshots; load them while the popover is open and fill the
    /// tiles in. Closing the popover or picking an app cancels the requests.
    func presentAppSwitcherPopover(
        apps: [AVInspectableApp],
        source: MenuPopoverAppsListControllerEventSource,
        loadScreenshots: Bool = false
    ) {
        guard let appItemView = toolbarItemsMap[NSToolbarItem.Identifier.AVToolBarIdentifier_App]?.view else { return }
        let sorted = AVAppsManager.sortedForDisplay(apps)
        let vc = AVMenuPopoverAppsListController(apps: sorted, source: source)
        let popover = NSPopover()
        let screenshotsLoad = SerialDisposable()
        vc.didSelectApp = { [weak popover] (app: AVInspectableApp?) in
            guard let app else { return }
            screenshotsLoad.dispose()
            popover?.close()
            if let error = app.serverVersionError as NSError? {
                AVHelper.presentError(error, window: self.window)
            } else {
                AVStaticAsyncUpdateManager.sharedInstance.endUpdating()
                self.viewController.progressView.animate(toProgress: InitialIndicatorProgressWhenFetchHierarchy)
                AVAppsManager.sharedInstance.switchToInspectableApp(app)
            }
        }
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = vc.bestSize()
        popover.contentViewController = vc
        popover.show(
            relativeTo: NSRect(x: 0, y: 0, width: appItemView.bounds.width, height: appItemView.bounds.height),
            of: appItemView,
            preferredEdge: .maxY
        )

        guard loadScreenshots, sorted.contains(where: { $0.appInfo != nil && $0.appInfo?.screenshot == nil }) else { return }
        screenshotsLoad.disposable = AppViewRACSignalRx.observeMainThread(
            AVAppsManager.sharedInstance.loadPopoverScreenshots(for: sorted)
        )
        .subscribe(onSuccess: { [weak vc] fresh in
            vc?.applyScreenshots(from: fresh)
        })
        var closeObserver: NSObjectProtocol?
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification,
            object: popover,
            queue: .main
        ) { _ in
            screenshotsLoad.dispose()
            if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        }
    }
}

enum AVMCPAppSwitcher {
    static func fetchAndOpen(timeout: TimeInterval) -> [String: Any] {
        AVMCPClientDiagnostics.shared.mcpOperationWillBegin()
        defer { AVMCPClientDiagnostics.shared.mcpOperationDidEnd() }

        if Thread.isMainThread {
            var result: [String: Any] = [:]
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                result = fetchAndOpen(timeout: timeout)
                group.leave()
            }
            _ = group.wait(timeout: .now() + timeout + AVMCPTiming.mainQueueHop + 10)
            return result
        }

        let fetchResult: Result<[AVInspectableApp], Error> = AVMCPBlockingWait.onMain(timeout: timeout) { done in
            _ = AppViewRACSignalRx.observeMainThread(
                AVAppsManager.sharedInstance.fetchAppsForPopover(withImage: true)
            )
            .subscribe(
                onSuccess: { apps in done(.success(apps)) },
                onFailure: { error in done(.failure(error)) }
            )
        }

        guard case .success(let apps) = fetchResult else {
            return response(for: [])
        }

        let showSem = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            AVNavigationManager.sharedInstance.staticWindowController?
                .presentAppSwitcherPopover(apps: apps, source: .appButton)
            showSem.signal()
        }
        _ = showSem.wait(timeout: .now() + AVMCPTiming.mainQueueHop)

        let expectedCount = apps.count
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let targets = AVMCPInspectTarget.launchTargets()
            if targets.count >= expectedCount {
                return response(for: targets)
            }
            if !targets.isEmpty, expectedCount <= 1 {
                return response(for: targets)
            }
            Thread.sleep(forTimeInterval: AVMCPTiming.appSwitcherTilePollInterval)
        }
        return response(for: AVMCPInspectTarget.launchTargets())
    }

    private static func response(for targets: [[String: Any]]) -> [String: Any] {
        [
            "ok": !targets.isEmpty,
            "count": targets.count,
            "targets": targets,
            "uiMode": AVNavigationManager.sharedInstance.mcpUIMode.rawValue,
            "lastDiscover": AVMCPClientDiagnostics.shared.lastDiscoverSummary,
        ]
    }
}
