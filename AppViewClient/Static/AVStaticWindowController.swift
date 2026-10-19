//
//  AVStaticWindowController.swift
//  AppView
//

import AppCenterAnalytics
import AppKit
import AppViewShared
import RxRelay
import RxSwift

final class AVStaticWindowController: AVWindowController, NSToolbarDelegate {
    private(set) var viewController: AVStaticViewController!

    var toolbarItemsMap: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    private let isFetchingHierarchyRelay = BehaviorRelay<Bool>(value: false)
    private let isFetchingDetailsRelay = BehaviorRelay<Bool>(value: false)
    private var inspectingAppEndToken: NSObjectProtocol?

    var isFetchingHierarchy: Bool {
        get { isFetchingHierarchyRelay.value }
        set { isFetchingHierarchyRelay.accept(newValue) }
    }

    var isFetchingDetails: Bool {
        get { isFetchingDetailsRelay.value }
        set { isFetchingDetailsRelay.accept(newValue) }
    }

    var mcpFetchingDetails: Bool { isFetchingDetails }
    var mcpFetchingHierarchy: Bool { isFetchingHierarchy }

    let disposeBag = DisposeBag()
    private var reloadHierarchyDisposable: Disposable?

    deinit {
        if let token = inspectingAppEndToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    override init(window: NSWindow?) {
        let contentSize: NSSize
        if AppViewUITestSupport.isEnabled {
            contentSize = AppViewUITestSupport.inspectorContentSize()
        } else {
            let screenSize = NSScreen.main?.frame.size ?? NSSize(width: 1440, height: 900)
            contentSize = NSSize(width: screenSize.width * 0.7, height: screenSize.height * 0.7)
        }
        let lkWindow = AVWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        lkWindow.tabbingMode = .disallowed
        lkWindow.titleVisibility = .hidden
        lkWindow.setAccessibilityIdentifier("appview.inspector.window")
        lkWindow.setAccessibilityValue("loading")
        if #available(macOS 11.0, *) {
            lkWindow.toolbarStyle = .unified
        }
        lkWindow.minSize = NSSize(width: HierarchyMinWidth + DashboardViewWidth + 200, height: 500)
        if AppViewUITestSupport.isEnabled {
            lkWindow.center()
        } else {
            lkWindow.center()
            lkWindow.setFrameUsingName(AVWindowSizeName_Static)
        }

        super.init(window: lkWindow)

        inspectingAppEndToken = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AVInspectingAppDidEndNotificationName"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isFetchingHierarchy = false
            self?.isFetchingDetails = false
        }

        viewController = AVStaticViewController()
        lkWindow.contentView = viewController.view
        contentViewController = viewController

        let toolbar = NSToolbar()
        toolbar.displayMode = .iconAndLabel
        toolbar.sizeMode = .regular
        toolbar.delegate = self
        lkWindow.toolbar = toolbar

        AVStaticAsyncUpdateManager.sharedInstance.delegate = self

        bindToolbarItemStates()
        bindFastModeSideEffects()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    convenience init() {
        self.init(window: nil)
    }

    func popupAllInspectableApps(
        with source: MenuPopoverAppsListControllerEventSource,
        needImages: Bool = true
    ) {
        guard let appItemView = toolbarItemsMap[NSToolbarItem.Identifier.AVToolBarIdentifier_App]?.view else { return }

        // App button tap: skip screenshots on first fetch to avoid blocking fetchAppInfosLock
        // for 10-15 s (cold App response with screenshots). The popover shows device icons and
        // app names immediately, then loads screenshots into the open tiles.
        // This mirrors the same optimization in AVLaunchViewController.reloadWithAutoEntering.
        let effectiveNeedImages: Bool
        switch source {
        case .appButton:
            effectiveNeedImages = false
        case .reloadButton, .noConnectionTips:
            effectiveNeedImages = needImages
        }

        AppViewRACSignalRx.observeMainThread(
            AVAppsManager.sharedInstance.fetchAppsForPopover(withImage: effectiveNeedImages)
        )
        .subscribe(with: self, onSuccess: { owner, apps in
            owner.presentAppSwitcherPopover(apps: apps, source: source, loadScreenshots: !effectiveNeedImages)
        })
        .disposed(by: disposeBag)
    }

    // MARK: - NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        var ret: [NSToolbarItem.Identifier] = [
            NSToolbarItem.Identifier.AVToolBarIdentifier_Reload,
            NSToolbarItem.Identifier.AVToolBarIdentifier_FastMode,
            NSToolbarItem.Identifier.AVToolBarIdentifier_App,
            .flexibleSpace,
            NSToolbarItem.Identifier.AVToolBarIdentifier_Dimension,
            NSToolbarItem.Identifier.AVToolBarIdentifier_Rotation,
            NSToolbarItem.Identifier.AVToolBarIdentifier_Setting,
            .flexibleSpace,
            NSToolbarItem.Identifier.AVToolBarIdentifier_Scale,
            .flexibleSpace,
            NSToolbarItem.Identifier.AVToolBarIdentifier_Measure,
            NSToolbarItem.Identifier.AVToolBarIdentifier_Console,
            NSToolbarItem.Identifier.AVToolBarIdentifier_Logs,
        ]
        if !AVMessageManager.sharedInstance.queryMessages().isEmpty {
            ret.append(NSToolbarItem.Identifier.AVToolBarIdentifier_Message)
            Analytics.trackEvent("Show Notification")
        }
        return ret
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if let existing = toolbarItemsMap[itemIdentifier] {
            return existing
        }
        guard let item = AVWindowToolbarHelper.sharedInstance().makeToolBarItem(
            withIdentifier: itemIdentifier,
            preferenceManager: AVPreferenceMain()
        ) else { return nil }
        toolbarItemsMap[itemIdentifier] = item

        switch itemIdentifier {
        case NSToolbarItem.Identifier.AVToolBarIdentifier_Reload:
            // Custom `item.view` — only wire the button; item.action would double-fire with button.action.
            if let button = item.view as? NSButton {
                button.target = self
                button.action = #selector(handleReload)
            }
        case NSToolbarItem.Identifier.AVToolBarIdentifier_App:
            if let button = item.view as? NSButton {
                button.target = self
                button.action = #selector(handleApp)
            }
        case NSToolbarItem.Identifier.AVToolBarIdentifier_Rotation:
            item.target = self
            item.action = #selector(handleFreeRotation)
        case NSToolbarItem.Identifier.AVToolBarIdentifier_Setting:
            item.label = NSLocalizedString("View", comment: "")
            item.target = self
            item.action = #selector(handleSetting(_:))
        case NSToolbarItem.Identifier.AVToolBarIdentifier_Console:
            item.target = self
            item.action = #selector(handleConsole)
            viewController.showConsoleObservable
                .skip(1)
                .distinctUntilChanged()
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { isShowing in
                    if let button = item.view as? NSButton {
                        button.state = isShowing ? .on : .off
                    }
                })
                .disposed(by: disposeBag)
        case NSToolbarItem.Identifier.AVToolBarIdentifier_Logs:
            item.target = self
            item.action = #selector(handleLogs)
            viewController.showLogsObservable
                .skip(1)
                .distinctUntilChanged()
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { isShowing in
                    if let button = item.view as? NSButton {
                        button.state = isShowing ? .on : .off
                    }
                })
                .disposed(by: disposeBag)
            AVLogsManager.shared.hasUnreadErrorsObservable
                .distinctUntilChanged()
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { hasUnread in
                    if let button = item.view as? NSButton {
                        AVStaticWindowController.updateLogsBadge(on: button, visible: hasUnread)
                    }
                })
                .disposed(by: disposeBag)
        case NSToolbarItem.Identifier.AVToolBarIdentifier_Message:
            item.label = NSLocalizedString("Notifications", comment: "")
            item.target = self
            item.action = #selector(handleMessage(_:))
        case NSToolbarItem.Identifier.AVToolBarIdentifier_FastMode:
            if let button = item.view as? NSButton {
                button.target = self
                button.action = #selector(handleFastMode)
            }
        default:
            break
        }
        return item
    }

    // MARK: - Event handlers

    @objc func handleReload() {
        if isFetchingDetails {
            AVStaticAsyncUpdateManager.sharedInstance.endUpdating()
            resetDetailFetchingToolbarState()
        }

        guard let app = AVAppsManager.sharedInstance.inspectingApp else {
            popupAllInspectableApps(with: .reloadButton)
            return
        }

        cancelInFlightHierarchyReload(on: app.channel)

        AVStaticAsyncUpdateManager.sharedInstance.endUpdating()
        isFetchingHierarchy = true
        viewController.progressView.animate(toProgress: InitialIndicatorProgressWhenFetchHierarchy)
        AVPerformanceReporter.sharedInstance.willStartReload()
        AVConnectionTiming.shared.begin("reload.hierarchy")

        reloadHierarchyDisposable?.dispose()
        reloadHierarchyDisposable = AppViewRACSignalRx.observeMainThread(
            AVAppsManager.sharedInstance.fetchHierarchyDataForReload(from: app)
        )
        .do(onDispose: { [weak self] in
            self?.isFetchingHierarchy = false
        })
        .subscribe(with: self, onSuccess: { owner, info in
            owner.viewController.progressView.finish(completion: nil)
            AVStaticHierarchyDataSource.sharedInstance.reload(with: info, keepState: true)
            owner.isFetchingHierarchy = false
            AVPerformanceReporter.sharedInstance.didFetchHierarchy()
            AVConnectionTiming.shared.end("reload.hierarchy", attrs: ["flat": info.displayItems?.count ?? 0])
        }, onFailure: { owner, error in
            AVConnectionTiming.shared.end("reload.hierarchy", attrs: ["error": true])
            let nsError = error as NSError
            if nsError.code != AVAppViewClientErrors.discard().code {
                owner.viewController.progressView.resetToZero()
                AlertError(nsError, owner.window)
            } else {
                owner.viewController.progressView.resetToZero()
            }
            owner.isFetchingHierarchy = false
        })
    }

    private func cancelInFlightHierarchyReload(on channel: AVPeerChannel?) {
        guard let channel else { return }
        let conn = AVConnectionManager.sharedInstance
        conn.cancelRequest(withType: UInt32(AppViewRequestTypeHierarchyDetails), channel: channel)
        conn.cancelRequest(withType: UInt32(AppViewRequestTypeHierarchy), channel: channel, notifyDiscard: true)
        conn.cancelRequest(withType: UInt32(AppViewRequestTypePing), channel: channel, notifyDiscard: true)
    }

    @objc private func handleApp() {
        popupAllInspectableApps(with: .appButton)
    }

    @objc private func handleSetting(_ button: NSButton) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: AVHelper.isEnglish() ? 270 : 350, height: 200)
        popover.contentViewController = AVMenuPopoverSettingController(preferenceManager: AVPreferenceMain())
        popover.show(
            relativeTo: NSRect(x: 0, y: 0, width: button.bounds.width, height: button.bounds.height),
            of: button,
            preferredEdge: .maxY
        )
    }

    @objc private func handleConsole() {
        viewController.showConsole = !viewController.showConsole
    }

    @objc private func handleLogs() {
        viewController.showLogs = !viewController.showLogs
    }

    @objc private func handleFastMode() {
        AVConnectionTiming.shared.begin("fastMode.toggle")
        let manager = AVPreferenceMain()
        manager.fastMode = !manager.fastMode
        AVConnectionTiming.shared.end("fastMode.toggle", attrs: ["enabled": manager.fastMode])
    }

    @objc private func handleMessage(_ button: NSButton) {
        let menu = NSMenu()
        let msgs = AVMessageManager.sharedInstance.queryMessages()

        for msg in msgs {
            if msg == AVMessage_NewServerVersion {
                let item = NSMenuItem()
                item.image = NSImageMake("Icon_Inspiration_small")
                let userVersion = AVAppsManager.sharedInstance.inspectingApp?.appInfo?.serverReadableVersion
                let newestVersion = AVServerVersionRequestor.shared.query()
                if let userVersion, !userVersion.isEmpty {
                    let format = NSLocalizedString(
                        "Your iOS project uses version %@ of the AppViewServer SDK, while the latest version online is %@, it is recommended to upgrade.",
                        comment: ""
                    )
                    item.title = String(format: format, userVersion, newestVersion ?? "")
                } else {
                    let format = NSLocalizedString(
                        "Your iOS project uses an outdated version of the AppViewServer SDK. It is recommended to upgrade to the latest version %@",
                        comment: ""
                    )
                    item.title = String(format: format, newestVersion ?? "")
                }
                menu.addItem(item)
                let historyItem = NSMenuItem()
                historyItem.image = NSImage(size: NSSize(width: 18, height: 1))
                historyItem.title = NSLocalizedString("Check out version updates on GitHub…", comment: "")
                historyItem.target = self
                historyItem.action = #selector(handleVersionsHistory)
                menu.addItem(historyItem)
                menu.addItem(.separator())
                continue
            }
            if msg == AVMessage_SwiftSubspec {
                let item = NSMenuItem()
                item.image = NSImageMake("Icon_Inspiration_small")
                item.title = NSLocalizedString(
                    "Your iOS project seems to use Swift, but you haven't turn on Swift optimization for AppView",
                    comment: ""
                )
                menu.addItem(item)
                menu.addItem(.separator())
            }
        }

        if menu.items.isEmpty {
            let item = NSMenuItem()
            item.title = NSLocalizedString("No message", comment: "")
            menu.addItem(item)
        }

        NSMenu.popUpContextMenu(menu, with: NSApplication.shared.currentEvent!, for: button)
        Analytics.trackEvent("Open Notification", withProperties: [
            "SwiftSubspec": "\(msgs.contains(AVMessage_SwiftSubspec))",
            "LowServer": "\(msgs.contains(AVMessage_NewServerVersion))",
        ])
    }

    @objc private func handleFreeRotation() {
        let manager = AVPreferenceMain()
        manager.freeRotation = !manager.freeRotation
    }

    @objc private func handleVersionsHistory() {
        NSWorkspace.shared.open(URL(string: "https://github.com/AlexNikov/AppViewServer/releases")!)
    }

    // MARK: - Private

    private func bindFastModeSideEffects() {
        AVPreferenceMain().fastModeObservable
            .distinctUntilChanged()
            .skip(1)
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, enabled in
                if enabled {
                    AVStaticAsyncUpdateManager.sharedInstance.updateForDisplayingItems()
                } else {
                    AVStaticAsyncUpdateManager.sharedInstance.endUpdating()
                    owner.resetDetailFetchingToolbarState()
                    AVStaticAsyncUpdateManager.sharedInstance.updateAll()
                }
            }
            .disposed(by: disposeBag)
    }

    private func bindToolbarItemStates() {
        Observable.combineLatest(
            isFetchingHierarchyRelay.asObservable(),
            isFetchingDetailsRelay.asObservable(),
            AVAppsManager.sharedInstance.switchStatusObservable.map { $0.isBusy }
        )
        .distinctUntilChanged { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 }
        .observe(on: MainScheduler.instance)
        .subscribe(with: self) { owner, flags in
            let disabled = flags.0 || flags.1 || flags.2
            for id in [
                NSToolbarItem.Identifier.AVToolBarIdentifier_App,
                NSToolbarItem.Identifier.AVToolBarIdentifier_Console,
            ] {
                owner.toolbarItemsMap[id]?.isEnabled = !disabled
            }
            owner.toolbarItemsMap[NSToolbarItem.Identifier.AVToolBarIdentifier_FastMode]?.isEnabled = true
        }
        .disposed(by: disposeBag)

        AVAppsManager.sharedInstance.switchSuccessObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, success in
                owner.viewController.progressView.finish(completion: nil)
                let isSameApp = AVAppsManager.isSameInspectableSession(success.previousApp, success.freshApp)
                AVStaticHierarchyDataSource.sharedInstance.reload(with: success.hierarchyInfo, keepState: isSameApp)
            }
            .disposed(by: disposeBag)

        AVAppsManager.sharedInstance.switchFailureObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, error in
                owner.viewController.progressView.resetToZero()
                AlertError(error as NSError, owner.window)
            }
            .disposed(by: disposeBag)

        isFetchingHierarchyRelay.asObservable()
            .distinctUntilChanged()
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, isFetching in
                owner.toolbarItemsMap[NSToolbarItem.Identifier.AVToolBarIdentifier_Reload]?.isEnabled = !isFetching
            }
            .disposed(by: disposeBag)

        AVStaticHierarchyDataSource.sharedInstance.selectedItemObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, item in
                guard let measureButton = owner.toolbarItemsMap[NSToolbarItem.Identifier.AVToolBarIdentifier_Measure]?.view as? NSButton else {
                    return
                }
                measureButton.isEnabled = item != nil
            }
            .disposed(by: disposeBag)
    }

    private static let logsBadgeLayerKey = "logsBadgeLayer"

    static func updateLogsBadge(on button: NSButton, visible: Bool) {
        button.wantsLayer = true
        if visible {
            if button.layer?.sublayers?.contains(where: { $0.name == logsBadgeLayerKey }) == true {
                return
            }
            let dotSize: CGFloat = 8
            let dot = CALayer()
            dot.name = logsBadgeLayerKey
            dot.cornerRadius = dotSize / 2
            dot.backgroundColor = NSColor.systemRed.cgColor
            dot.appview_removeImplicitAnimations()
            // Anchor to top-right; layerMinXMargin + layerMinYMargin keeps it there
            // as the button resizes (non-flipped coords: y=0 is bottom)
            let w = max(button.bounds.width, 48)
            let h = max(button.bounds.height, 34)
            dot.frame = CGRect(x: w - dotSize - 2, y: h - dotSize - 2, width: dotSize, height: dotSize)
            dot.autoresizingMask = [.layerMinXMargin, .layerMinYMargin]
            button.layer?.addSublayer(dot)
        } else {
            button.layer?.sublayers?.filter { $0.name == logsBadgeLayerKey }.forEach { $0.removeFromSuperlayer() }
        }
    }

    // MARK: - AVAppMenuManagerDelegate
    // Must stay in the class body (not an extension) for Swift vtable override.

    override func appMenuManagerDidSelectReload() {
        if isFetchingDetails {
            let error = AppViewErrorMake(
                NSLocalizedString("Cannot reload at this time", comment: ""),
                NSLocalizedString(
                    "Please wait until current sync is completed. You can get sync progress in the upper-left corner of this window.",
                    comment: ""
                )
            )
            if let window {
                NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
            }
            return
        }
        handleReload()
    }

    func mcpForceReload() {
        AVStaticAsyncUpdateManager.sharedInstance.endUpdating()
        isFetchingDetails = false
        isFetchingHierarchy = false
        handleReload()
    }

    override func appMenuManagerDidSelectDimension() {
        let manager = AVPreferenceMain()
        if manager.previewDimension == Int(AppViewPreviewDimension.dimension2D.rawValue) {
            manager.previewDimension = Int(AppViewPreviewDimension.dimension3D.rawValue)
        } else {
            manager.previewDimension = Int(AppViewPreviewDimension.dimension2D.rawValue)
        }
    }

    override func appMenuManagerDidSelectZoomIn() {
        let manager = AVPreferenceMain()
        let target = min(max(manager.previewScale + 0.1, AppViewPreviewMinScale), AppViewPreviewMaxScale)
        manager.previewScale = target
    }

    override func appMenuManagerDidSelectZoomOut() {
        let manager = AVPreferenceMain()
        let target = min(max(manager.previewScale - 0.1, AppViewPreviewMinScale), AppViewPreviewMaxScale)
        manager.previewScale = target
    }

    override func appMenuManagerDidSelectDecreaseInterspace() {
        let manager = AVPreferenceMain()
        var newValue = manager.zInterspace - 0.1
        newValue = min(max(newValue, AppViewPreviewMinZInterspace), AppViewPreviewMaxZInterspace)
        manager.zInterspace = newValue
    }

    override func appMenuManagerDidSelectIncreaseInterspace() {
        let manager = AVPreferenceMain()
        var newValue = manager.zInterspace + 0.1
        newValue = min(max(newValue, AppViewPreviewMinZInterspace), AppViewPreviewMaxZInterspace)
        manager.zInterspace = newValue
    }

    override func appMenuManagerDidSelectExpansionIndex(_ index: UInt) {
        AVStaticHierarchyDataSource.sharedInstance.adjustExpansionByIndex(
            Int(index),
            referenceDict: nil,
            selectedItem: nil
        )
        if !TutorialMng.hasAlreadyShowedTipsThisLaunch, !TutorialMng.quickSelection, index <= 1 {
            viewController.showQuickSelectionTutorialTips()
        }
    }

    override func appMenuManagerDidSelectExport() {
        let exportManager = AVExportManager.sharedInstance
        guard let hierarchyInfo = AVStaticHierarchyDataSource.sharedInstance.rawHierarchyInfo else { return }

        let accessoryView = AVExportAccessoryView()
        accessoryView.sizeToFit()

        // Build synchronously first — `observe(on: MainScheduler)` would leave `exported` nil
        // until the next runloop turn, so Save could run with no data.
        var exported = exportManager.exportDocument(
            from: hierarchyInfo,
            imageCompression: AVPreferenceMain().preferredExportCompression
        )
        accessoryView.dataSize = UInt(exported?.data.count ?? 0)

        let compressionUpdates = SerialDisposable()
        compressionUpdates.disposable = AVPreferenceMain().preferredExportCompressionObservable
            .skip(1)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { compression in
                exported = exportManager.exportDocument(
                    from: hierarchyInfo,
                    imageCompression: compression
                )
                accessoryView.dataSize = UInt(exported?.data.count ?? 0)
            })

        let panel = NSSavePanel()
        panel.accessoryView = accessoryView
        panel.nameFieldStringValue = exported?.fileName
            ?? AVExportManager.suggestedFileName(for: hierarchyInfo.appInfo)
        panel.allowsOtherFileTypes = false
        panel.allowedFileTypes = ["appview"]
        panel.isExtensionHidden = true
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window!) { result in
            compressionUpdates.dispose()
            if result == .OK, let path = panel.url?.path {
                guard let exported else {
                    assertionFailure("AppViewClient - write fail, no data")
                    AlertError(AVAppViewClientErrors.inner, self.window)
                    return
                }
                do {
                    try exported.data.write(to: URL(fileURLWithPath: path))
                } catch {
                    NSLog("AppViewClient - write fail:%@", error.localizedDescription)
                    AlertError(error as NSError, self.window)
                }
            }
        }
        Analytics.trackEvent("Export Document")
    }

    override func appMenuManagerDidSelectOpenInNewWindow() {
        guard let hierarchyInfo = AVStaticHierarchyDataSource.sharedInstance.rawHierarchyInfo else { return }
        // Lookin parity: copy hierarchy with screenshots still attached to display items.
        let file = AVExportManager.sharedInstance.hierarchyFileForReader(from: hierarchyInfo)
        guard file.hierarchyInfo != nil else {
            assertionFailure("Open in new window: hierarchy copy failed")
            return
        }
        AVNavigationManager.sharedInstance.showReader(withHierarchyFile: file, title: nil)
        Analytics.trackEvent("Open New Window")
    }

    override func appMenuManagerDidSelectFilter() {
        viewController.currentHierarchyView().activateSearchBar()
    }
}
