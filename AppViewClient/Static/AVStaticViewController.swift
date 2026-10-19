//
//  AVStaticViewController.swift
//  AppView
//

import AppCenterAnalytics
import AppKit
import AppViewShared
import RxRelay
import RxSwift


final class AVStaticViewController: AVBaseViewController, NSSplitViewDelegate {
    private(set) var viewsPreviewController: AVPreviewController!
    var progressView: AVProgressIndicatorView!
    private let showConsoleRelay = BehaviorRelay<Bool>(value: false)
    var showConsoleObservable: Observable<Bool> {
        showConsoleRelay.asObservable()
    }

    var showConsole: Bool {
        get { showConsoleRelay.value }
        set {
            guard newValue != showConsoleRelay.value else { return }
            showConsoleRelay.accept(newValue)
            updateConsoleVisibility()
        }
    }

    private let showLogsRelay = BehaviorRelay<Bool>(value: false)
    var showLogsObservable: Observable<Bool> {
        showLogsRelay.asObservable()
    }

    var showLogs: Bool {
        get { showLogsRelay.value }
        set {
            guard newValue != showLogsRelay.value else { return }
            showLogsRelay.accept(newValue)
            updateLogsVisibility()
        }
    }

    var isShowingQuickSelectTutorialTips = false
    var isShowingMoveWithSpaceTutorialTips = false

    private var mainSplitView: AVSplitView!
    private var rightSplitView: AVSplitView!
    private var splitTopView: AVBaseView!

    private var imageSyncTipsView: AVTipsView!
    private var tooLargeToSyncScreenshotTipsView: AVRedTipsView!
    private var userConfigNoPreviewTipsView: AVTipsView!
    private var noPreviewTipView: AVTipsView!
    private var tutorialTipView: AVTipsView?
    private var customViewTipView: AVTipsView!
    private var focusTipView: AVYellowTipsView!
    private var fastModeTipView: AVTipsView!

    private var dashboardController: AVDashboardViewController!
    private(set) var hierarchyController: AVStaticHierarchyController!
    private var consoleController: AVConsoleViewController?
    private var logsController: AVLogsViewController?
    private var errorNotificationTipsView: AVRedTipsView?
    private var errorNotificationHideTimer: Timer?
    private var measureController: AVMeasureController!

    private let disposeBag = DisposeBag()

    override func makeContainerView() -> NSView {
        let split = AVSplitView()
        split.didFinishFirstLayout = { view in
            let x = min(max(350, view.bounds.width * 0.3), 700)
            view.setPosition(x, ofDividerAt: 0)
        }
        split.arrangesAllSubviews = false
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = self
        mainSplitView = split
        return split
    }

    override func appview_didSetView(_ view: NSView) {
        super.appview_didSetView(view)

        let preferenceManager = AVPreferenceMain()
        preferenceManager.measureStateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, state in
                owner.applyMeasureStateChange(state)
            }
            .disposed(by: disposeBag)

        let dataSource = AVStaticHierarchyDataSource.sharedInstance

        hierarchyController = AVStaticHierarchyController(dataSource: dataSource)
        addChild(hierarchyController)
        hierarchyController.view.setAccessibilityIdentifier("appview.panel.hierarchy")
        mainSplitView.addArrangedSubview(hierarchyController.view)

        rightSplitView = AVSplitView()
        rightSplitView.arrangesAllSubviews = true
        rightSplitView.isVertical = false
        rightSplitView.dividerStyle = .thin
        rightSplitView.delegate = self
        mainSplitView.addArrangedSubview(rightSplitView)

        splitTopView = AVBaseView()
        rightSplitView.addArrangedSubview(splitTopView)

        viewsPreviewController = AVPreviewController(dataSource: dataSource)
        viewsPreviewController.staticViewController = self
        viewsPreviewController.view.setAccessibilityIdentifier("appview.panel.preview")
        splitTopView.addSubview(viewsPreviewController.view)
        addChild(viewsPreviewController)

        dashboardController = AVDashboardViewController(staticDataSource: dataSource)
        dashboardController.view.setAccessibilityIdentifier("appview.panel.dashboard")
        splitTopView.addSubview(dashboardController.view)
        addChild(dashboardController)

        measureController = AVMeasureController(dataSource: dataSource)
        measureController.view.isHidden = true
        splitTopView.addSubview(measureController.view)
        addChild(measureController)

        imageSyncTipsView = AVTipsView()
        imageSyncTipsView.isHidden = true
        self.view.addSubview(imageSyncTipsView)

        tooLargeToSyncScreenshotTipsView = AVRedTipsView()
        tooLargeToSyncScreenshotTipsView.image = NSImageMake("icon_info")
        tooLargeToSyncScreenshotTipsView.title = NSLocalizedString("Image is too large to be displayed.", comment: "")
        tooLargeToSyncScreenshotTipsView.isHidden = true
        self.view.addSubview(tooLargeToSyncScreenshotTipsView)

        focusTipView = AVYellowTipsView()
        focusTipView.image = NSImageMake("icon_info")
        focusTipView.title = NSLocalizedString("Currently in focus mode", comment: "")
        focusTipView.isHidden = true
        focusTipView.buttonText = NSLocalizedString("Exit", comment: "")
        focusTipView.target = self
        focusTipView.clickAction = #selector(handleExitFocusTipView)
        self.view.addSubview(focusTipView)

        fastModeTipView = AVTipsView()
        fastModeTipView.image = NSImageMake("Icon_Inspiration_small")
        fastModeTipView.title = NSLocalizedString(
            "Fast refresh mode is enabled, which may result in layer consistency issues.",
            comment: ""
        )
        fastModeTipView.isHidden = true
        fastModeTipView.buttonText = NSLocalizedString("Details", comment: "")
        fastModeTipView.target = self
        fastModeTipView.clickAction = #selector(handleFastModeTipViewClick)
        self.view.addSubview(fastModeTipView)

        noPreviewTipView = AVTipsView()
        noPreviewTipView.image = NSImageMake("icon_hide")
        noPreviewTipView.title = NSLocalizedString("The screenshot of selected item is not displayed.", comment: "")
        noPreviewTipView.buttonText = NSLocalizedString("Display", comment: "")
        noPreviewTipView.target = self
        noPreviewTipView.clickAction = #selector(handleNoPreviewTipView)
        noPreviewTipView.isHidden = true
        self.view.addSubview(noPreviewTipView)

        customViewTipView = AVTipsView()
        customViewTipView.image = NSImageMake("Icon_Inspiration_small")
        customViewTipView.title = NSLocalizedString("This object may not be a UIView or CALayer.", comment: "")
        customViewTipView.buttonText = NSLocalizedString("Details", comment: "")
        customViewTipView.target = self
        customViewTipView.clickAction = #selector(handleCustomViewTipsView)
        customViewTipView.isHidden = true
        self.view.addSubview(customViewTipView)

        userConfigNoPreviewTipsView = AVTipsView()
        userConfigNoPreviewTipsView.image = NSImageMake("icon_hide")
        userConfigNoPreviewTipsView.title = NSLocalizedString(
            "The screenshot is not displayed due to the config in iOS App.",
            comment: ""
        )
        userConfigNoPreviewTipsView.buttonText = NSLocalizedString("Details", comment: "")
        userConfigNoPreviewTipsView.target = self
        userConfigNoPreviewTipsView.clickAction = #selector(handleUserConfigNoPreviewTipView)
        userConfigNoPreviewTipsView.isHidden = true
        self.view.addSubview(userConfigNoPreviewTipsView)

        progressView = AVProgressIndicatorView()
        self.view.addSubview(progressView)

        dataSource.selectedItemObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, _ in
                owner.handleSelectItemDidChange()
            }
            .disposed(by: disposeBag)

        let noPreviewMergeSignal = Observable.merge([
            dataSource.selectedItemObservable.map { _ in () },
            dataSource.itemDidChangeNoPreview,
        ]).skip(1)
        noPreviewMergeSignal
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, _ in
                let item = dataSource.selectedItem
                let shouldShow = item?.inNoPreviewHierarchy == true
                    && item?.doNotFetchScreenshotReason != .userConfig
                if shouldShow || !owner.noPreviewTipView.isHidden {
                    if let item {
                        owner.noPreviewTipView.title = String(
                            format: NSLocalizedString("The screenshot of selected %@ is not displayed.", comment: ""),
                            item.title() ?? ""
                        )
                        owner.noPreviewTipView.bindingObject = item
                    }
                    owner.noPreviewTipView.isHidden = !shouldShow
                    owner.view.needsLayout = true
                }
            }
            .disposed(by: disposeBag)

        dataSource.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, state in
                let isFocus = state == .focus
                owner.focusTipView.isHidden = !isFocus
                if isFocus {
                    owner.focusTipView.startAnimation()
                } else {
                    owner.focusTipView.endAnimation()
                }
                owner.view.needsLayout = true
            }
            .disposed(by: disposeBag)

        AVAppsManager.sharedInstance.inspectingAppObservable
            .compactMap { $0 }
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, app in
                owner.imageSyncTipsView.setImageByDeviceType(app.appInfo?.deviceType ?? .others)
            }
            .disposed(by: disposeBag)

        let updateMng = AVStaticAsyncUpdateManager.sharedInstance
        updateMng.modifyingUpdateProgress
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { owner, progressValue in
                let received = progressValue.received
                let total = max(1, progressValue.total)
                let progress = CGFloat(received) / CGFloat(total)
                if progress >= 1 {
                    owner.progressView.finish(completion: nil)
                    owner.imageSyncTipsView.isHidden = true
                } else {
                    owner.progressView.animate(toProgress: max(progress, 0.2), duration: 0.1)
                    owner.imageSyncTipsView.isHidden = false
                    owner.imageSyncTipsView.title = String(
                        format: NSLocalizedString("Updating screenshots… %@ / %@", comment: ""),
                        "\(received)",
                        "\(total)"
                    )
                    owner.view.needsLayout = true
                }
            })
            .disposed(by: disposeBag)

        updateMng.modifyingUpdateError
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { owner, error in
                owner.imageSyncTipsView.isHidden = true
                owner.progressView.resetToZero()
                AlertError(error, owner.view.window)
            })
            .disposed(by: disposeBag)

        preferenceManager.fastModeObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, _ in
                owner.updateFastModeTipVisibility()
            }
            .disposed(by: disposeBag)

        AVPreferenceMain().reportStatistics()

        hierarchyController.hierarchyView.printItemRelay
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, item in
                Analytics.trackEvent("PrintItem")
                let isFirstTime = owner.consoleController == nil
                owner.showConsole = true
                guard let viewObject = item.viewObject else { return }
                if isFirstTime {
                    DispatchQueue.main.asyncAfter(deadline: .now() + AVUITiming.staticConsoleReveal) { [weak owner] in
                        owner?.consoleController?.submit(withObj: viewObject, text: "self")
                    }
                } else {
                    owner.consoleController?.submit(withObj: viewObject, text: "self")
                }
            }
            .disposed(by: disposeBag)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleErrorNotification(_:)),
            name: .AVShowErrorNotification,
            object: nil
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if TutorialMng.hasAlreadyShowedTipsThisLaunch {
            return
        }
    }

    func currentHierarchyView() -> AVHierarchyView {
        hierarchyController.hierarchyView
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        lk(dashboardController.view).width(DashboardViewWidth).right(0).fullHeight()
        lk(measureController.view).width(MeasureViewWidth).right(DashboardHorInset).fullHeight()
        lk(viewsPreviewController.view).fullFrame()

        let windowTitleHeight = AVNavigationManager.sharedInstance.windowTitleBarHeight
        lk(progressView).fullWidth().height(3).y(windowTitleHeight)

        var tipsY = windowTitleHeight + 10
        var tipViews: [AVTipsView] = [
            imageSyncTipsView,
            tooLargeToSyncScreenshotTipsView,
            noPreviewTipView,
            userConfigNoPreviewTipsView,
            customViewTipView,
            fastModeTipView,
        ]
        if let errorView = errorNotificationTipsView, !errorView.isHidden {
            tipViews.insert(errorView, at: 0)
        }
        if let connectionTipsView {
            tipViews.insert(connectionTipsView, at: 0)
        }
        if let focusTipView {
            tipViews.append(focusTipView)
        }
        if let tutorialTipView {
            tipViews.append(tutorialTipView)
        }
        tipViews = tipViews.filter { !$0.isHidden }

        let midX = hierarchyController.view.frame.size.width
            + (viewsPreviewController.view.frame.size.width - DashboardViewWidth) / 2.0
        for tipsView in tipViews {
            lk(tipsView).sizeToFit().y(tipsY).midX(midX)
            tipsY = tipsView.frame.maxY + 5
        }
    }

    override func shouldShowConnectionTips() -> Bool { true }

    // MARK: - Tutorial

    func showQuickSelectionTutorialTips() {
        TutorialMng.quickSelection = true
        TutorialMng.hasAlreadyShowedTipsThisLaunch = true
        isShowingQuickSelectTutorialTips = true
        initTutorialTipsIfNeeded()
        tutorialTipView?.title = NSLocalizedString(
            "While holding \"Command\" key, you can directly select a screenshot without expanding its superview first",
            comment: ""
        )
        view.needsLayout = true
    }

    func showMoveWithSpaceTutorialTips() {
        TutorialMng.moveWithSpace = true
        TutorialMng.hasAlreadyShowedTipsThisLaunch = true
        isShowingMoveWithSpaceTutorialTips = true
        initTutorialTipsIfNeeded()
        tutorialTipView?.title = NSLocalizedString(
            "You can move screenshots by holding \"Space\" key and left mouse button",
            comment: ""
        )
        view.needsLayout = true
    }

    func showNoPreviewTutorialTips() {
        TutorialMng.hasAlreadyShowedTipsThisLaunch = true
        TutorialMng.togglePreview = true
        initTutorialTipsIfNeeded()
        tutorialTipView?.title = NSLocalizedString("You can hide a screenshot in its right-click menu", comment: "")
        view.needsLayout = true
    }

    func removeTutorialTips() {
        tutorialTipView?.removeFromSuperview()
        tutorialTipView = nil
        view.needsLayout = true
        isShowingQuickSelectTutorialTips = false
        isShowingMoveWithSpaceTutorialTips = false
    }

    @objc private func handleErrorNotification(_ notification: Notification) {
        let title = notification.userInfo?[AVShowErrorNotificationTitleKey] as? String ?? ""
        guard !title.isEmpty else { return }
        if errorNotificationTipsView == nil {
            let v = AVRedTipsView()
            v.isHidden = true
            view.addSubview(v)
            errorNotificationTipsView = v
        }
        errorNotificationTipsView?.title = title
        errorNotificationTipsView?.isHidden = false
        errorNotificationTipsView?.startAnimation()
        view.needsLayout = true
        errorNotificationHideTimer?.invalidate()
        errorNotificationHideTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.errorNotificationTipsView?.endAnimation()
            self?.errorNotificationTipsView?.isHidden = true
            self?.view.needsLayout = true
        }
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        if splitView === mainSplitView {
            return HierarchyMinWidth
        }
        return splitView.bounds.height * 0.3
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        if splitView === mainSplitView {
            return max(splitView.bounds.width - DashboardViewWidth - 100, HierarchyMinWidth)
        }
        return splitView.bounds.height - 50
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        if let splitView = notification.object as? NSSplitView, splitView === mainSplitView, splitView.subviews.count >= 2 {
            let maxDivider = max(splitView.bounds.width - DashboardViewWidth - 100, HierarchyMinWidth)
            let hierarchyWidth = splitView.subviews[0].frame.width
            if hierarchyWidth > maxDivider + 1 {
                splitView.setPosition(maxDivider, ofDividerAt: 0)
            }
        }
        view.needsLayout = true
    }

    // MARK: - Handlers

    @objc private func handleNoPreviewTipView() {
        if let view = hierarchyController.hierarchyView,
           let item = noPreviewTipView.bindingObject as? AppViewDisplayItem {
            hierarchyController.hierarchyView(view, needToShowPreviewOfItem: item)
        }
        if !TutorialMng.togglePreview,
           let selectedRowView = hierarchyController.currentSelectedRowView() {
            TutorialMng.showPopover(
                of: selectedRowView,
                text: "你可在右键菜单里再次隐藏它的图像",
                learned: {
                    TutorialMng.togglePreview = true
                    TutorialMng.hasAlreadyShowedTipsThisLaunch = true
                }
            )
        }
    }

    @objc private func handleCustomViewTipsView() {
        NSWorkspace.shared.open(URL(string: "https://bytedance.feishu.cn/docx/TRridRXeUoErMTxs94bcnGchnlb")!)
    }

    @objc private func handleExitFocusTipView() {
        hierarchyController.dataSource.endFocus()
    }

    @objc private func handleFastModeTipViewClick() {
        let menu = NSMenu()
        let docItem = NSMenuItem(
            title: NSLocalizedString("View feature description", comment: ""),
            action: #selector(handleFastModeDocumentation),
            keyEquivalent: ""
        )
        docItem.target = self
        menu.addItem(docItem)
        menu.addItem(.separator())
        let ignoreItem = NSMenuItem(
            title: NSLocalizedString("Don't remind me again", comment: ""),
            action: #selector(handleIgnoreFastModeTip),
            keyEquivalent: ""
        )
        ignoreItem.target = self
        menu.addItem(ignoreItem)
        NSMenu.popUpContextMenu(menu, with: NSApplication.shared.currentEvent!, for: fastModeTipView.button)
    }

    @objc private func handleFastModeDocumentation() {
        NSWorkspace.shared.open(URL(string: "https://qxh1ndiez2w.feishu.cn/wiki/BPihwfigUigWLQk1Epmc5SFenEe")!)
    }

    @objc private func handleIgnoreFastModeTip() {
        UserDefaults.standard.set(true, forKey: "IgnoreFastModeTips")
        fastModeTipView.isHidden = true
    }

    @objc private func handleUserConfigNoPreviewTipView() {
        AVHelper.openCustomConfigWebsite()
    }

    private func applyMeasureStateChange(_ state: AppViewMeasureState) {
        let isMeasure = state != .no
        dashboardController.view.isHidden = isMeasure
        measureController.view.isHidden = !isMeasure
    }

    private func updateFastModeTipVisibility() {
        if !AVPreferenceMain().fastMode {
            fastModeTipView.isHidden = true
            return
        }
        let shouldIgnore = UserDefaults.standard.bool(forKey: "IgnoreFastModeTips")
        fastModeTipView.isHidden = shouldIgnore
        view.needsLayout = true
    }

    private func handleSelectItemDidChange() {
        let item = hierarchyController.dataSource.selectedItem

        let showTooLarge = item != nil
            && item?.appropriateScreenshot() == nil
            && item?.doNotFetchScreenshotReason == .tooLarge
        let hideTooLarge = !showTooLarge
        if tooLargeToSyncScreenshotTipsView.isHidden != hideTooLarge {
            tooLargeToSyncScreenshotTipsView.isHidden = hideTooLarge
            if hideTooLarge {
                tooLargeToSyncScreenshotTipsView.endAnimation()
            } else {
                tooLargeToSyncScreenshotTipsView.startAnimation()
            }
            view.needsLayout = true
        }

        let showCustom = item?.isUserCustom() == true
        if customViewTipView.isHidden == showCustom {
            customViewTipView.isHidden = !showCustom
            view.needsLayout = true
        }
    }

    private func initTutorialTipsIfNeeded() {
        guard tutorialTipView == nil else {
            tutorialTipView?.isHidden = false
            return
        }
        let tips = AVTipsView()
        tips.image = NSImageMake("Icon_Inspiration_small")
        tips.buttonText = NSLocalizedString("Do not show again", comment: "")
        tips.didClick = { [weak self] tipsView in
            tipsView.removeFromSuperview()
            self?.view.needsLayout = true
        }
        self.view.addSubview(tips)
        tutorialTipView = tips
        tutorialTipView?.isHidden = false
    }

    private func updateConsoleVisibility() {
        if showConsole {
            Analytics.trackEvent("Launch Console")
            if consoleController == nil {
                consoleController = AVConsoleViewController(
                    hierarchyDataSource: AVStaticHierarchyDataSource.sharedInstance
                )
                addChild(consoleController!)
            }
            rightSplitView.addArrangedSubview(consoleController!.view)
            if consoleController!.view.bounds.size.height < 20 {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let h = self.rightSplitView.bounds.height - 150
                    self.rightSplitView.setPosition(h, ofDividerAt: 0)
                }
            }
        } else if let consoleController {
            if consoleController.view.superview != nil {
                rightSplitView.removeArrangedSubview(consoleController.view)
            } else {
                assertionFailure()
            }
        }
        consoleController?.isControllerShowing = showConsole
    }

    private func updateLogsVisibility() {
        if showLogs {
            AVLogsManager.shared.markAllRead()
            if logsController == nil {
                logsController = AVLogsViewController()
                addChild(logsController!)
            }
            rightSplitView.addArrangedSubview(logsController!.view)
            if logsController!.view.bounds.height < 20 {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let dividerIdx = self.rightSplitView.subviews.count - 2
                    let h = self.rightSplitView.bounds.height - 150
                    self.rightSplitView.setPosition(h, ofDividerAt: dividerIdx)
                }
            }
        } else if let logsController, logsController.view.superview != nil {
            rightSplitView.removeArrangedSubview(logsController.view)
        }
    }

    func mcpInspectorParitySnapshot(uiMode: String) -> [String: Any] {
        let dataSource = AVStaticHierarchyDataSource.sharedInstance
        return AVMCPInspectorParity.buildSnapshot(
            dataSource: dataSource,
            hierarchyView: hierarchyController.hierarchyView,
            previewView: AVPreviewView.sharedForMCP,
            uiMode: uiMode
        )
    }
}
