//
//  AVReadViewController.swift
//  AppView
//

import AppKit
import AppViewShared
import RxSwift

class AVReadViewController: AVBaseViewController, NSSplitViewDelegate {
    private(set) var hierarchyDataSource: AVReadHierarchyDataSource!

    private var splitView: AVSplitView!
    private var splitLeftView: NSView!
    private var splitRightView: NSView!

    private var dashboardController: AVDashboardViewController!
    private var hierarchyController: AVReadHierarchyController!
    private var previewController: AVPreviewController!
    private var measureController: AVMeasureController!
    private var focusTipView: AVYellowTipsView!

    private let disposeBag = DisposeBag()

    init(file: AppViewHierarchyFile, preferenceManager: AVPreferenceManager) {
        super.init(containerView: nil)

        hierarchyDataSource = AVReadHierarchyDataSource(file: file, preferenceManager: preferenceManager)

        hierarchyController = AVReadHierarchyController(dataSource: hierarchyDataSource)
        addChild(hierarchyController)
        splitLeftView = hierarchyController.view
        splitView.addArrangedSubview(splitLeftView)

        splitRightView = AVBaseView()
        splitView.addArrangedSubview(splitRightView)

        previewController = AVPreviewController(dataSource: hierarchyDataSource)
        splitRightView.addSubview(previewController.view)
        addChild(previewController)

        dashboardController = AVDashboardViewController(readDataSource: hierarchyDataSource)
        splitRightView.addSubview(dashboardController.view)
        addChild(dashboardController)

        measureController = AVMeasureController(dataSource: hierarchyDataSource)
        measureController.view.isHidden = true
        splitRightView.addSubview(measureController.view)
        addChild(measureController)

        focusTipView = AVYellowTipsView()
        focusTipView.image = NSImageMake("icon_info")
        focusTipView.title = NSLocalizedString("Currently in focus mode", comment: "")
        focusTipView.isHidden = true
        focusTipView.buttonText = NSLocalizedString("Exit", comment: "")
        focusTipView.target = self
        focusTipView.clickAction = #selector(handleExitFocusTipView)
        view.addSubview(focusTipView)

        preferenceManager.measureStateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, state in
                owner.applyMeasureStateChange(state)
            }
            .disposed(by: disposeBag)

        hierarchyDataSource.stateObservable
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
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func makeContainerView() -> NSView {
        splitView = AVSplitView()
        splitView.didFinishFirstLayout = { view in
            view.setPosition(350, ofDividerAt: 0)
        }
        splitView.arrangesAllSubviews = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        return splitView
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        lk(previewController.view).fullFrame()
        lk(dashboardController.view).width(DashboardViewWidth).right(0).fullHeight()
        lk(measureController.view).width(MeasureViewWidth).right(DashboardHorInset).fullHeight()

        let windowTitleHeight = AVNavigationManager.sharedInstance.windowTitleBarHeight
        var tipsY = windowTitleHeight + 10
        if !focusTipView.isHidden {
            let midX = hierarchyController.view.frame.size.width + (previewController.view.frame.size.width - DashboardViewWidth) / 2.0
            lk(focusTipView).sizeToFit().y(tipsY).midX(midX)
            tipsY = focusTipView.frame.maxY + 5
        }
    }

    func currentHierarchyView() -> AVHierarchyView {
        hierarchyController.hierarchyView
    }

    private func applyMeasureStateChange(_ state: AppViewMeasureState) {
        let isMeasure = state != .no
        dashboardController.view.isHidden = isMeasure
        measureController.view.isHidden = !isMeasure
    }

    @objc
    private func handleExitFocusTipView() {
        hierarchyDataSource.endFocus()
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        false
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        200
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        700
    }
}
