import AppKit
import AppViewShared
import RxSwift

protocol AVDashboardCardViewDelegate: AnyObject {
    func dashboardCardViewNeedToggleCollapse(_ view: AVDashboardCardView)
}

final class AVDashboardViewController: AVBaseViewController {
    private var scrollView: NSScrollView!
    private var documentView: AVBaseView!
    private var cardContainerView: AVBaseView!
    private var groupList: [AppViewAttributesGroup] = []
    private var cardViews: [String: AVDashboardCardView] = [:]
    private var staticDataSource: AVStaticHierarchyDataSource?
    private var readDataSource: AVReadHierarchyDataSource?
    private let disposeBag = DisposeBag()

    private(set) var isStaticMode = false

    /// Layout Issues click state: the issue and the constraint rows painted for it.
    private(set) var layoutHighlight = AppViewLayoutIssueHighlight()
    var highlightedIssueKey: String? { layoutHighlight.issueKey }

    init(staticDataSource: AVStaticHierarchyDataSource) {
        self.staticDataSource = staticDataSource
        isStaticMode = true
        super.init(containerView: nil)
        didInitialized()
    }

    init(readDataSource: AVReadHierarchyDataSource) {
        self.readDataSource = readDataSource
        isStaticMode = false
        super.init(containerView: nil)
        didInitialized()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func makeContainerView() -> NSView {
        let containerView = AVBaseView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        documentView = AVBaseView()
        scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.contentView.documentView = documentView
        containerView.addSubview(scrollView)

        cardContainerView = AVBaseView()
        documentView.addSubview(cardContainerView)
        return containerView
    }

    private func didInitialized() {
        cardViews = [:]

        if let staticDataSource {
            staticDataSource.selectedItemObservable
                .observe(on: MainScheduler.instance)
                .subscribe(with: self) { owner, _ in
                    owner.clearConstraintHighlight()
                    let item = staticDataSource.selectedItem
                    let groups = item?.queryAllAttrGroupList() ?? []
                    owner.reload(withGroupList: groups)
                    if groups.isEmpty {
                        AVStaticAsyncUpdateManager.sharedInstance.scheduleSelectedItemAttributesFetch(item)
                    }
                }
                .disposed(by: disposeBag)

            staticDataSource.itemDidChangeAttrGroup
                .observe(on: MainScheduler.instance)
                .subscribe(with: self, onNext: { owner, item in
                    let selectedOid = staticDataSource.selectedItem?.layerObject?.oid
                    guard selectedOid != nil, selectedOid == item.layerObject?.oid else { return }
                    owner.clearConstraintHighlight()
                    owner.reload(withGroupList: item.queryAllAttrGroupList())
                })
                .disposed(by: disposeBag)

            staticDataSource.didReloadHierarchyInfo
                .observe(on: MainScheduler.instance)
                .subscribe(with: self, onNext: { owner, _ in
                    owner.clearConstraintHighlight()
                    owner.reload(withGroupList: staticDataSource.selectedItem?.queryAllAttrGroupList() ?? [])
                })
                .disposed(by: disposeBag)

            reload(withGroupList: staticDataSource.selectedItem?.queryAllAttrGroupList() ?? [])
        } else if let readDataSource {
            readDataSource.selectedItemObservable
                .observe(on: MainScheduler.instance)
                .subscribe(with: self) { owner, _ in
                    owner.clearConstraintHighlight()
                    owner.reload(withGroupList: readDataSource.selectedItem?.queryAllAttrGroupList() ?? [])
                }
                .disposed(by: disposeBag)
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name(NotificationName_DidChangeSectionShowing),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.reload(withGroupList: self.currentDataSource()?.selectedItem?.queryAllAttrGroupList() ?? [])
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        lk(scrollView).fullFrame()
        let verMargin: CGFloat = 10
        let contentWidth = DashboardViewWidth - DashboardHorInset * 2

        if !cardContainerView.isHidden {
            lk(cardContainerView).width(contentWidth).x(DashboardHorInset).y(verMargin)
            var y: CGFloat = 0
            for group in groupList {
                guard let cardView = cardViews[group.uniqueKey() ?? ""], !cardView.isHidden else { continue }
                lk(cardView).width(contentWidth).y(y).heightToFit()
                y = cardView.frame.maxY + verMargin
            }
            lk(cardContainerView).height(y)
        }

        var documentMaxY = verMargin
        if !cardContainerView.isHidden {
            documentMaxY = max(documentMaxY, cardContainerView.frame.maxY)
        }
        lk(documentView).fullWidth().y(0).toMaxY(documentMaxY)
    }

    func reload(withGroupList list: [AppViewAttributesGroup]) {
        layoutHighlight.setConflictIDs(AppViewLayoutIssueHighlight.conflictIDs(in: list))
        groupList = list
        guard !list.isEmpty else {
            scrollView.isHidden = false
            cardContainerView.isHidden = true
            view.needsLayout = true
            return
        }
        scrollView.isHidden = false
        cardContainerView.isHidden = false
        var needlessViews = Array(cardViews.values)
        for group in list {
            var cardView = cardViews[group.uniqueKey() ?? ""]
            if cardView == nil {
                cardView = AVDashboardCardView()
                cardView?.dashboardViewController = self
                cardView?.delegate = self
                cardViews[group.uniqueKey() ?? ""] = cardView
                cardContainerView.addSubview(cardView!)
            } else {
                needlessViews.removeAll { $0 === cardView }
            }
            cardView?.isHidden = false
            cardView?.attrGroup = group
            cardView?.isCollapsed = AVPreferenceMain().collapsedAttrGroups.contains(group.identifier ?? "")
            cardView?.render()
        }
        needlessViews.forEach { $0.isHidden = true }
        view.needsLayout = true
    }

    func modifyAttribute(_ attribute: AppViewAttribute, newValue: AttributeValue?) -> Single<Void> {
        if attribute.isUserCustom() {
            return modifyCustomAttribute(attribute, newValue: newValue)
        }
        return modifyInbuiltAttribute(attribute, newValue: newValue)
    }

    // MARK: - Layout issue highlight

    /// First click remembers the ids, shows Constraints if hidden and paints the rows once the card has been
    /// rebuilt. A second click on the same issue clears the highlight.
    func handleLayoutIssueClick(_ issue: AppViewLayoutIssue) {
        let key = AppViewLayoutIssueHighlight.key(for: issue)
        let revealConstraints = layoutHighlight.toggle(issue)
        if !revealConstraints {
            applyConstraintHighlight(scrollIfNeeded: false)
            refreshLayoutIssueActiveStates()
            return
        }
        let manager = AVPreferenceMain()
        refreshLayoutIssueActiveStates()
        // showSection asserts when the section is already visible; it rebuilds the card via the notification.
        if !manager.isSectionShowing(AppViewAttrSec_AutoLayout_Constraints) {
            manager.showSection(AppViewAttrSec_AutoLayout_Constraints)
            DispatchQueue.main.asyncAfter(deadline: .now() + AVUITiming.dashboardLayoutSettle) { [weak self] in
                guard let self, self.highlightedIssueKey == key else { return }
                self.applyConstraintHighlight(scrollIfNeeded: true)
            }
            return
        }
        applyConstraintHighlight(scrollIfNeeded: true)
    }

    func clearConstraintHighlight() {
        guard highlightedIssueKey != nil || !layoutHighlight.clickedIDs.isEmpty else { return }
        layoutHighlight.clearClick()
        applyConstraintHighlight(scrollIfNeeded: false)
        refreshLayoutIssueActiveStates()
    }

    private func refreshLayoutIssueActiveStates() {
        cardViews.values.forEach { $0.refreshLayoutIssueActiveStates() }
    }

    private func applyConstraintHighlight(scrollIfNeeded: Bool) {
        var target: AVDashboardAttributeConstraintsItemControl?
        for group in groupList {
            guard let cardView = cardViews[group.uniqueKey() ?? ""], !cardView.isHidden else { continue }
            cardView.applyConstraintHighlight(layoutHighlight)
            if target == nil { target = cardView.firstHighlightedConstraintControl() }
        }
        guard scrollIfNeeded, let target, let document = scrollView.documentView else { return }
        let rect = document.convert(target.bounds, from: target)
        let visible = scrollView.contentView.documentVisibleRect
        guard !visible.insetBy(dx: 0, dy: 8).contains(rect) else { return }
        let y = min(max(0, rect.minY - 12), max(0, document.bounds.height - visible.height))
        scrollView.contentView.scroll(to: NSPoint(x: visible.origin.x, y: y))
    }

    func currentDataSource() -> AVHierarchyDataSource? {
        staticDataSource ?? readDataSource
    }

    private func modifyCustomAttribute(_ attribute: AppViewAttribute, newValue: AttributeValue?) -> Single<Void> {
        AVReactiveBridge.singleSignal { sendSuccess, sendError in
            var modification = AppViewCustomAttrModification()
            modification.customSetterID = attribute.customSetterID
            modification.attrType = attribute.attrType
            modification.value = newValue
            guard let setterID = modification.customSetterID, !setterID.isEmpty else {
                assertionFailure()
                AlertError(AVAppViewClientErrors.inner, self.view.window)
                sendError(AVAppViewClientErrors.inner)
                return nil
            }
            guard let app = AVAppsManager.sharedInstance.inspectingApp else {
                AlertError(AVAppViewClientErrors.noConnect, self.view.window)
                sendError(AVAppViewClientErrors.noConnect)
                return nil
            }
            AppViewDiagLog.log(
                "client custom send setterID=\(setterID) attrType=\(attribute.attrType.rawValue) value=\(String(describing: newValue))"
            )
            let d = app.submitCustomModification(modification).subscribe(
                onCompleted: {
                    AppViewDiagLog.log("client custom OK setterID=\(setterID)")
                    attribute.value = newValue
                    sendSuccess(())
                },
                onError: { error in
                    let nsError = error as NSError? ?? AVAppViewClientErrors.inner
                    AppViewDiagLog.log("client custom FAIL code=\(nsError.code) \(nsError.localizedDescription)")
                    AlertError(nsError, self.view.window)
                    sendError(error)
                }
            )
            return { d.dispose() }
        }
    }

    /// Hidden/Opacity only update visibility — screenshot patch blocks main and times out on UIView.
    private static func shouldFetchScreenshotPatch(afterModifying attribute: AppViewAttribute) -> Bool {
        let id = attribute.identifier ?? ""
        if id == AppViewAttr_ViewLayer_Visibility_Hidden || id == AppViewAttr_ViewLayer_Visibility_Opacity {
            return false
        }
        return AppViewDashboardBlueprint.needPatchAfterModification(withAttrID: id)
    }

    private static func inbuiltModificationTargetOid(
        for attribute: AppViewAttribute,
        item: AppViewDisplayItem
    ) -> UInt {
        let attrID = attribute.identifier ?? ""
        if attrID == AppViewAttr_ViewLayer_Visibility_Hidden || attrID == AppViewAttr_ViewLayer_Visibility_Opacity {
            // CALayer-only items (e.g. DogLayer oid 17) have no viewObject — use layer oid.
            if item.viewObject == nil, let layerOid = item.layerObject?.oid, layerOid != 0 {
                return layerOid
            }
            if let viewOid = item.viewObject?.oid, viewOid != 0 {
                return viewOid
            }
            return item.layerObject?.oid ?? 0
        }
        if AppViewDashboardBlueprint.isUIViewProperty(withAttrID: attrID) {
            if let viewOid = item.viewObject?.oid, viewOid != 0 {
                return viewOid
            }
            return item.layerObject?.oid ?? 0
        }
        return item.layerObject?.oid ?? 0
    }

    private func modifyInbuiltAttribute(_ attribute: AppViewAttribute, newValue: AttributeValue?) -> Single<Void> {
        AVReactiveBridge.singleSignal { sendSuccess, sendError in
            guard let modifyingItem = attribute.targetDisplayItem ?? self.staticDataSource?.selectedItem else {
                sendError(AVAppViewClientErrors.inner)
                return nil
            }
            attribute.targetDisplayItem = modifyingItem
            var modification = AppViewAttributeModification()
            modification.clientReadableVersion = AVHelper.appviewReadableVersion()
            modification.targetOid = Self.inbuiltModificationTargetOid(for: attribute, item: modifyingItem)
            guard modification.targetOid != 0 else {
                sendError(AVAppViewClientErrors.inner)
                return nil
            }
            guard let setter = AppViewDashboardBlueprint.setter(withAttrID: attribute.identifier ?? "") else {
                assertionFailure()
                AlertError(AVAppViewClientErrors.inner, self.view.window)
                sendError(AVAppViewClientErrors.inner)
                return nil
            }
            modification.setterSelector = setter
            modification.attrIdentifier = attribute.identifier
            modification.attrType = attribute.attrType
            modification.value = newValue
            AppViewDiagLog.log(
                "client inbuilt send oid=\(modification.targetOid) attr=\(attribute.identifier ?? "?") item=\(modifyingItem.title() ?? "?") value=\(String(describing: newValue))"
            )
            guard let app = AVAppsManager.sharedInstance.inspectingApp else {
                AlertError(AVAppViewClientErrors.noConnect, self.view.window)
                sendError(AVAppViewClientErrors.noConnect)
                return nil
            }
            app.cancelInbuiltModification()
            let d = app.submitInbuiltModification(modification).subscribe(
                onSuccess: { detail in
                    AppViewDiagLog.log(
                        "client inbuilt OK detailOid=\(detail.displayItemOid) hidden=\(detail.hiddenValue?.boolValue ?? false)"
                    )
                    if let staticDataSource = self.staticDataSource {
                        AVDashboardTextControlEditingFlag.sharedInstance.shouldIgnoreTextEditingChangeEvent = true
                        staticDataSource.modify(with: detail)
                        AVDashboardTextControlEditingFlag.sharedInstance.shouldIgnoreTextEditingChangeEvent = false
                        if Self.shouldFetchScreenshotPatch(afterModifying: attribute) {
                            AVStaticAsyncUpdateManager.sharedInstance.updateAfterModifyingDisplayItem(modifyingItem)
                        }
                    } else {
                        assertionFailure()
                    }
                    sendSuccess(())
                },
                onFailure: { error in
                    let nsError = error as NSError? ?? AVAppViewClientErrors.inner
                    AppViewDiagLog.log(
                        "client inbuilt FAIL code=\(nsError.code) \(nsError.localizedDescription)"
                    )
                    if nsError.code != Int(AppViewErrCode_Discard) {
                        AlertError(nsError, self.view.window)
                    }
                    sendError(nsError)
                }
            )
            return { d.dispose() }
        }
    }
}

extension AVDashboardViewController: AVDashboardCardViewDelegate {
    func dashboardCardViewNeedToggleCollapse(_ view: AVDashboardCardView) {
        guard let dataSource = currentDataSource(),
              let identifier = view.attrGroup?.identifier else { return }
        let prefManager = dataSource.preferenceManager()
        if prefManager.collapsedAttrGroups.contains(identifier) {
            view.isCollapsed = false
            prefManager.collapsedAttrGroups = prefManager.collapsedAttrGroups.appview_arrayByRemovingObject(identifier)
        } else {
            view.isCollapsed = true
            prefManager.collapsedAttrGroups = prefManager.collapsedAttrGroups + [identifier]
        }
        self.view.needsLayout = true
    }
}
