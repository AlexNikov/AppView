import AppKit
import AppViewShared

final class AVDashboardCardView: AVBaseView {
    weak var dashboardViewController: AVDashboardViewController?
    weak var delegate: AVDashboardCardViewDelegate?
    var attrGroup: AppViewAttributesGroup?
    var isCollapsed = false {
        didSet {
            titleControl.disclosureImageView.image = NSImageMake(isCollapsed ? "icon_arrow_right" : "icon_arrow_down")
        }
    }

    private var backgroundEffectView: AVVisualEffectView!
    private var titleControl: AVDashboardCardTitleControl!
    private var detailButton: NSButton!
    private let sectionViewPool = AVDashboardSectionViewPool()
    private var sectionViews: [AVDashboardSectionView] = []
    private var accessoryWC: AVDashboardAccessoryWindowController?

    private let titleHeight: CGFloat = 30
    private var contentsY: CGFloat = 35
    private let insetBottom: CGFloat = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = DashboardCardCornerRadius
        backgroundEffectView = AVVisualEffectView()
        backgroundEffectView.blendingMode = .withinWindow
        backgroundEffectView.state = .active
        addSubview(backgroundEffectView)
        titleControl = AVDashboardCardTitleControl()
        titleControl.addTarget(self, clickAction: #selector(handleClickTitle))
        addSubview(titleControl)
        detailButton = NSButton(image: .appviewNamed("icon_more"), target: self, action: #selector(handleClickDetailButton))
        detailButton.bezelStyle = .rounded
        detailButton.isBordered = false
        addSubview(detailButton)
        updateColors()
        AVUserActionManager.sharedInstance.addDelegate(self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        lk(backgroundEffectView).fullFrame()
        lk(titleControl).fullWidth().height(titleHeight).y(0)
        if detailButton.isVisible { lk(detailButton).width(50).height(28).right(-3).y(0) }
        guard attrGroup != nil, !sectionViews.isEmpty else { return }
        var y = contentsY
        for view in sectionViews {
            lk(view).x(DashboardHorInset).toRight(DashboardHorInset).heightToFit().y(y)
            y = view.frame.maxY + DashboardSectionMarginTop
        }
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        var size = limitedSize
        if isCollapsed {
            size.height = titleHeight
            return size
        }
        size.width -= DashboardHorInset * 2
        var height = contentsY
        for obj in sectionViews {
            height += obj.sizeThatFits(size).height + DashboardSectionMarginTop
        }
        height -= DashboardSectionMarginTop
        height += insetBottom
        size.height = height
        return size
    }

    func render() {
        guard let attrGroup else { assertionFailure(); return }
        switch attrGroup.identifier {
        case AppViewAttrGroup_Class: contentsY = 28
        case AppViewAttrGroup_Relation: contentsY = 30
        default: contentsY = 35
        }
        titleControl.label.stringValue = attrGroup.queryDisplayTitle()
        titleControl.iconImageView.image = Self.image(with: attrGroup)
        titleControl.needsLayout = true
        detailButton.isHidden = !shouldShowDetailButton(groupID: attrGroup.identifier ?? "")
        sectionViews.forEach { $0.removeFromSuperview() }
        sectionViews.removeAll()
        sectionViewPool.recycleAll()
        var visibleSectionIndex = 0
        for sec in attrGroup.attrSections ?? [] {
            if !sec.isUserCustom(), !AVPreferenceMain().isSectionShowing(sec.identifier ?? "") { continue }
            let secView = sectionViewPool.dequeView(for: sec)
            sectionViews.append(secView)
            addSubview(secView)
            secView.dashboardViewController = dashboardViewController
            secView.attrSection = sec
            secView.showTopSeparator = visibleSectionIndex > 0
            secView.manageState = accessoryWC == nil ? .none : .canRemove
            visibleSectionIndex += 1
        }
        if accessoryWC != nil { renderAccessoryWindowController() }
        needsLayout = true
    }

    func applyConstraintHighlight(_ highlight: AppViewLayoutIssueHighlight) {
        sectionViews.forEach { $0.constraintsView()?.applyWarningHighlight(highlight) }
    }

    func refreshLayoutIssueActiveStates() {
        sectionViews.forEach { $0.layoutIssuesView()?.refreshActiveState() }
    }

    func firstHighlightedConstraintControl() -> AVDashboardAttributeConstraintsItemControl? {
        for secView in sectionViews {
            if let control = secView.constraintsView()?.firstHighlightedControl() { return control }
        }
        return nil
    }

    @objc private func handleClickTitle() {
        delegate?.dashboardCardViewNeedToggleCollapse(self)
    }

    private static func image(with group: AppViewAttributesGroup) -> NSImage {
        let dict: [AppViewAttrGroupIdentifier: String] = [
            AppViewAttrGroup_Class: "dashboard_class",
            AppViewAttrGroup_Accessibility: "dashboard_label",
            AppViewAttrGroup_Relation: "dashboard_relation",
            AppViewAttrGroup_Layout: "dashboard_layout",
            AppViewAttrGroup_AutoLayout: "dashboard_autolayout",
            AppViewAttrGroup_ViewLayer: "dashboard_layer",
            AppViewAttrGroup_UIImageView: "dashboard_imageview",
            AppViewAttrGroup_UILabel: "dashboard_label",
            AppViewAttrGroup_UIButton: "dashboard_button",
            AppViewAttrGroup_UIControl: "dashboard_control",
            AppViewAttrGroup_UIScrollView: "dashboard_scrollview",
            AppViewAttrGroup_UITableView: "dashboard_tableview",
            AppViewAttrGroup_UITextView: "dashboard_textview",
            AppViewAttrGroup_UITextField: "dashboard_textfield",
            AppViewAttrGroup_UIVisualEffectView: "dashboard_effectview",
            AppViewAttrGroup_UIStackView: "dashboard_stackview",
            AppViewAttrGroup_UserCustom: "dashboard_custom",
        ]
        guard let name = dict[group.identifier ?? ""], let image = NSImageMake(name) else { assertionFailure(); return NSImage() }
        return image
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        AVUserActionManager.sharedInstance.send(.dashboardClick)
    }

    @objc private func handleClickDetailButton() {
        if let accessoryWC {
            accessoryWC.close()
            return
        }
        AVUserActionManager.sharedInstance.send(.dashboardClick)
        if isCollapsed { delegate?.dashboardCardViewNeedToggleCollapse(self) }
        guard let dashboardViewController, let identifier = attrGroup?.identifier else { return }
        let wc = AVDashboardAccessoryWindowController(dashboardController: dashboardViewController, attrGroupID: identifier)
        wc.delegate = self
        accessoryWC = wc
        renderAccessoryWindowController()
        if let window, let childWindow = wc.window {
            window.addChildWindow(childWindow, ordered: .above)
        }
    }

    private func renderAccessoryWindowController() {
        guard let accessoryWC, let attrGroup else { assertionFailure(); return }
        sectionViews.forEach { $0.manageState = .canRemove }
        let allSecIDs = AppViewDashboardBlueprint.sectionIDs(forGroupID: attrGroup.identifier ?? "")
        let hiddenSecIDs = allSecIDs.filter { !AVPreferenceMain().isSectionShowing($0) }
        if hiddenSecIDs.isEmpty {
            accessoryWC.window?.contentView?.isHidden = true
            return
        }
        accessoryWC.window?.contentView?.isHidden = false
        let sections = hiddenSecIDs.compactMap { secID in
            (attrGroup.attrSections ?? []).first { $0.identifier == secID }
        }
        let contentSize = accessoryWC.render(withAttrSections: sections)
        guard let window, let superview else { return }
        let selfFrameInWindow = window.contentView!.convert(frame, from: superview)
        let selfWindowFrame = window.frame
        let panelY = max(selfWindowFrame.origin.y + (selfWindowFrame.height - selfFrameInWindow.origin.y) - contentSize.height, 0)
        var panelX = selfWindowFrame.maxX + 5
        if panelX + contentSize.width > (window.screen?.frame.width ?? panelX + contentSize.width) {
            panelX = selfWindowFrame.origin.x + selfFrameInWindow.minX - contentSize.width - 5
        }
        accessoryWC.window?.setFrame(NSRect(x: panelX, y: panelY, width: contentSize.width, height: contentSize.height), display: true)
    }

    private func shouldShowDetailButton(groupID: AppViewAttrGroupIdentifier) -> Bool {
        if groupID == AppViewAttrGroup_UserCustom { return false }
        return AppViewDashboardBlueprint.sectionIDs(forGroupID: groupID).count > 1
    }

}

extension AVDashboardCardView: AVUserActionManagerDelegate {
    func lkUserActionManager(_ manager: AVUserActionManager, didAct type: AVUserActionType) {
        guard accessoryWC != nil else { return }
        let valid: [AVUserActionType] = [.previewOperation, .dashboardClick, .selectedItemChange]
        if valid.contains(type) { accessoryWC?.close() }
    }
}

extension AVDashboardCardView: AVDashboardAccessoryWindowControllerDelegate {
    func dashboardAccessoryWindowControllerWillClose(_ controller: AVDashboardAccessoryWindowController) {
        sectionViews.forEach { $0.manageState = .none }
        accessoryWC = nil
    }
}
