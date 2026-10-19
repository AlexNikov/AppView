import AppKit
import AppViewShared

enum AVDashboardSectionManageState: Int {
    case none = 0
    case canAdd = 1
    case canRemove = 2
}

final class AVDashboardSectionView: AVBaseView {
    var attrSection: AppViewAttributesSection? {
        didSet { applyAttrSection() }
    }

    var showTopSeparator = false {
        didSet { topSepLayer.isHidden = !showTopSeparator }
    }

    weak var dashboardViewController: AVDashboardViewController?

    var manageState: AVDashboardSectionManageState = .none {
        didSet { applyManageState() }
    }

    private var attrViews: [AVDashboardAttributeView] = []
    private var titleLabel: AVLabel?
    private let topSepLayer = CALayer()
    private var manageButton: NSButton?
    private var jsonPopupButton: NSButton?
    private let titleMarginTop: CGFloat = 6

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        topSepLayer.appview_removeImplicitAnimations()
        layer?.addSublayer(topSepLayer)
        updateColors()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func manageButtonLayoutY() -> CGFloat {
        if topSepLayer.isHidden {
            return 0
        }
        if titleLabel?.isVisible == true {
            return 6
        }
        return 9
    }

    func constraintsView() -> AVDashboardAttributeConstraintsView? {
        attrViews.first { $0 is AVDashboardAttributeConstraintsView && !$0.isHidden } as? AVDashboardAttributeConstraintsView
    }

    func layoutIssuesView() -> AVDashboardAttributeLayoutIssuesView? {
        attrViews.first { $0 is AVDashboardAttributeLayoutIssuesView && !$0.isHidden } as? AVDashboardAttributeLayoutIssuesView
    }

    /// Room taken by header buttons on the right of the title.
    private func titleTrailingReserve() -> CGFloat {
        jsonPopupButton?.isVisible == true ? 20 : 0
    }

    private func hasDisplayableContent(forWidth width: CGFloat) -> Bool {
        if titleLabel?.isVisible == true, let titleLabel {
            let titleWidth = width - titleTrailingReserve()
            if titleLabel.sizeThatFits(NSSize(width: titleWidth, height: .greatestFiniteMagnitude)).height > 0 {
                return true
            }
        }
        let limitedSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        return attrViews.contains { view in
            view.lk_clientIsVisible && view.sizeThatFits(limitedSize).height > 0
        }
    }

    override func layout() {
        super.layout()
        var contentsX: CGFloat = 0
        let selfWidth = frame.width
        var contentsY: CGFloat = 0

        if manageButton?.isVisible == true, let manageButton {
            let y = manageButtonLayoutY()
            lk(manageButton).sizeToFit().x(0).y(y)
            contentsX = manageButton.frame.maxX + 6
        }

        if jsonPopupButton?.isVisible == true, let jsonPopupButton {
            lk(jsonPopupButton).width(30).height(28).right(-5).y(0)
        }

        if !topSepLayer.isHidden {
            lk(topSepLayer).x(contentsX).width(selfWidth).height(1).y(0)
            contentsY = DashboardAttrItemVerInterspace
        }

        if titleLabel?.isVisible == true, let titleLabel {
            let titleWidth = selfWidth - titleTrailingReserve()
            lk(titleLabel).x(contentsX).width(titleWidth).heightToFit().y(topSepLayer.isHidden ? 0 : titleMarginTop)
            contentsY = titleLabel.frame.maxY + DashboardAttrItemVerInterspace
        }

        let visibleAttrViews = attrViews.filter { $0.lk_clientIsVisible }
        for (idx, view) in visibleAttrViews.enumerated() {
            let prevView = idx > 0 ? visibleAttrViews[idx - 1] : nil
            let numberOfColumns = view.numberOfColumnsOccupied()
            let width: CGFloat
            if numberOfColumns == 0 {
                width = view.sizeThatFits(NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).width
            } else {
                width = floor((selfWidth + DashboardAttrItemHorInterspace) / CGFloat(numberOfColumns)) - DashboardAttrItemHorInterspace
            }
            let x: CGFloat
            let y: CGFloat
            if let prevView, prevView.frame.maxX + DashboardAttrItemHorInterspace + width <= selfWidth + contentsX {
                x = prevView.frame.maxX + DashboardAttrItemHorInterspace
                y = prevView.frame.origin.y
            } else {
                x = contentsX
                y = prevView.map { $0.frame.maxY + DashboardAttrItemVerInterspace } ?? contentsY
            }
            lk(view).width(width).heightToFit().x(x).y(y)
        }
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        var height: CGFloat = 0
        if !topSepLayer.isHidden {
            height += DashboardAttrItemVerInterspace
        }
        if titleLabel?.isVisible == true, let titleLabel {
            let titleWidth = limitedSize.width - titleTrailingReserve()
            height += titleLabel.sizeThatFits(NSSize(width: titleWidth, height: .greatestFiniteMagnitude)).height + titleMarginTop
        }
        let visibleAttrViews = attrViews.filter { $0.lk_clientIsVisible }
        var prevMaxX: CGFloat = 0
        for (idx, view) in visibleAttrViews.enumerated() {
            let numberOfColumns = view.numberOfColumnsOccupied()
            let width: CGFloat
            if numberOfColumns == 0 {
                width = view.sizeThatFits(limitedSize).width
            } else {
                width = floor((limitedSize.width + DashboardAttrItemHorInterspace) / CGFloat(numberOfColumns)) - DashboardAttrItemHorInterspace
            }
            if idx > 0, prevMaxX + DashboardAttrItemHorInterspace + width <= limitedSize.width {
                prevMaxX += DashboardAttrItemHorInterspace + width
            } else {
                height += view.sizeThatFits(limitedSize).height
                if idx > 0 { height += DashboardAttrItemVerInterspace }
                prevMaxX = width
            }
        }
        if manageButton?.isHidden == false, let manageButton {
            let buttonHeight = manageButton.sizeThatFits(limitedSize).height
            height = max(height, manageButtonLayoutY() + buttonHeight)
        }
        return NSSize(width: limitedSize.width, height: height)
    }

    override func updateColors() {
        super.updateColors()
        topSepLayer.backgroundColor = AppViewClientIsDarkMode() ? SeparatorDarkModeColor.cgColor : SeparatorLightModeColor.cgColor
    }

    private func applyAttrSection() {
        guard let attrSection else {
            assertionFailure()
            return
        }
        let title = resolveSectionTitle()
        if !title.isEmpty {
            if titleLabel == nil {
                let label = AVLabel()
                label.font = NSFont.boldSystemFont(ofSize: 12)
                addSubview(label)
                titleLabel = label
            }
            titleLabel?.isHidden = false
            titleLabel?.stringValue = title
        } else {
            titleLabel?.isHidden = true
        }

        var notUsedViews = attrViews
        for attr in attrSection.attributes ?? [] {
            guard let attrViewClass = targetAttrClass(for: attr.attrType, identifier: attr.identifier ?? "") else {
                assertionFailure()
                continue
            }
            var view = notUsedViews.first { type(of: $0) == attrViewClass }
            if let view {
                notUsedViews.removeAll { $0 === view }
                view.isHidden = false
            } else {
                view = attrViewClass.init()
                guard let view else { continue }
                view.dashboardViewController = dashboardViewController
                attrViews.append(view)
                addSubview(view)
            }
            if let selectedItem = dashboardViewController?.currentDataSource()?.selectedItem {
                attr.targetDisplayItem = selectedItem
            }
            view?.attribute = attr
        }
        notUsedViews.forEach { $0.isHidden = true }

        let hasJSON = (attrSection.attributes ?? []).contains { $0.attrType == .json }
        if hasJSON {
            showJSONPopupButton()
        } else {
            hideJSONPopupButton()
        }
        if manageState != .none {
            applyManageState()
        }
        needsLayout = true
    }

    private func targetAttrClass(for type: AppViewAttrType, identifier: AppViewAttrIdentifier) -> AVDashboardAttributeView.Type? {
        switch type {
        case .CGRect: return AVDashboardAttributeRectView.self
        case .UIEdgeInsets: return AVDashboardAttributeInsetsView.self
        case .BOOL: return AVDashboardAttributeSwitchView.self
        case .float, .double, .long: return AVDashboardAttributeNumberInputView.self
        case .UIColor: return AVDashboardAttributeColorView.self
        case .enumInt, .enumLong, .enumString: return AVDashboardAttributeEnumsView.self
        case .CGPoint: return AVDashboardAttributePointView.self
        case .CGSize: return AVDashboardAttributeSizeView.self
        case .NSString: return AVDashboardAttributeTextView.self
        case .shadow: return AVDashboardAttributeShadowView.self
        case .json: return AVDashboardAttributeJsonView.self
        case .customObj:
            switch identifier {
            case AppViewAttr_UITableView_RowsNumber_Number: return AVDashboardAttributeRowsCountView.self
            case AppViewAttr_Class_Class_Class: return AVDashboardAttributeClassView.self
            case AppViewAttr_Relation_Relation_Relation: return AVDashboardAttributeRelationView.self
            case AppViewAttr_AutoLayout_Constraints_Constraints,
                 AppViewAttr_AutoLayout_InstalledConstraints_Constraints:
                return AVDashboardAttributeConstraintsView.self
            case AppViewAttr_AutoLayout_Issues_Issues: return AVDashboardAttributeLayoutIssuesView.self
            case AppViewAttr_UIImageView_Open_Open: return AVDashboardAttributeOpenImageView.self
            case AppViewAttr_UIVisualEffectView_Style_Style: return AVDashboardAttributeEnumsView.self
            default:
                assertionFailure()
                return nil
            }
        default:
            assertionFailure()
            return nil
        }
    }

    private func showJSONPopupButton() {
        guard jsonPopupButton == nil else { return }
        let button = NSButton(image: .appviewNamed("open_newwindow"), target: self, action: #selector(handleJSONPopupButton))
        button.bezelStyle = .rounded
        button.isBordered = false
        addSubview(button)
        jsonPopupButton = button
    }

    private func hideJSONPopupButton() {
        jsonPopupButton?.removeFromSuperview()
        jsonPopupButton = nil
    }

    @objc private func handleJSONPopupButton() {
        guard let view = attrViews.first(where: { $0.attribute?.attrType == .json }) as? AVDashboardAttributeJsonView else {
            assertionFailure()
            return
        }
        view.showInNewWindow()
    }

    private func applyManageState() {
        switch manageState {
        case .none:
            manageButton?.isHidden = true
            needsLayout = true
        case .canAdd, .canRemove:
            let imageName = manageState == .canAdd ? "icon_manage_add" : "icon_manage_remove"
            let sectionWidth = bounds.width > 0 ? bounds.width : DashboardViewWidth - DashboardHorInset * 2
            let shouldShowManageButton = manageState == .canAdd || hasDisplayableContent(forWidth: sectionWidth)
            if let manageButton {
                manageButton.image = .appviewNamed(imageName)
                manageButton.isHidden = !shouldShowManageButton
            } else if shouldShowManageButton {
                let button = NSButton(image: .appviewNamed(imageName), target: self, action: #selector(handleManageButton))
                button.bezelStyle = .rounded
                button.isBordered = false
                addSubview(button)
                manageButton = button
            }
            needsLayout = true
        }
    }

    @objc private func handleManageButton() {
        guard let identifier = attrSection?.identifier else { return }
        let manager = AVPreferenceMain()
        switch manageState {
        case .canAdd:
            // showSection asserts when the section is already visible.
            if !manager.isSectionShowing(identifier) { manager.showSection(identifier) }
        case .canRemove:
            if manager.isSectionShowing(identifier) { manager.hideSection(identifier) }
        default: assertionFailure()
        }
    }

    private func resolveSectionTitle() -> String {
        guard let attrSection else { return "" }
        if !attrSection.isUserCustom() {
            return AppViewDashboardBlueprint.sectionTitle(withSectionID: attrSection.identifier ?? "") ?? ""
        }
        guard let attr = (attrSection.attributes ?? []).first else {
            assertionFailure()
            return ""
        }
        switch attr.attrType {
        case .BOOL: return ""
        default: return attr.displayTitle ?? ""
        }
    }
}
