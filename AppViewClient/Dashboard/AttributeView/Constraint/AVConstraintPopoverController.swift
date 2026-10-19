import AppKit
import AppViewShared

final class AVConstraintPopoverController: AVBaseViewController {
    var requestJumpingToObject: ((AppViewObject) -> Void)?

    private var titleView: AVTextFieldView?
    private var textsView: AVTextsMenuView!
    private let horInset: CGFloat = 5
    private let insetBottom: CGFloat = 10
    private let titleHeight: CGFloat = 26
    private let textsViewMarginTop: CGFloat = 10

    init(constraint: AppViewAutoLayoutConstraint) {
        super.init(containerView: nil)
        if !constraint.effective {
            let labelView = AVTextFieldView.label()
            labelView.textField.font = NSFontMake(IsEnglish ? 12 : 13)
            labelView.textColors = AVColorsCombine(NSColorGray1, NSColorGray9)
            labelView.textField.alignment = .center
            labelView.textField.stringValue = NSLocalizedString("The layout of selected view is not affected by this constraint.", comment: "")
            labelView.backgroundColors = AVColorsCombine(AppViewColorRGBAMake(0, 0, 0, 0.1), AppViewColorRGBAMake(0, 0, 0, 0.2))
            labelView.image = NSImageMake("Constraint_Popover_Info")
            labelView.insets = NSEdgeInsets(top: 0, left: horInset, bottom: 0, right: horInset)
            view.addSubview(labelView)
            titleView = labelView
        }
        textsView = AVTextsMenuView()
        textsView.verSpace = 8
        textsView.horSpace = 4
        textsView.font = NSFontMake(13)
        textsView.type = .center
        view.addSubview(textsView)
        let texts: [AppViewStringTwoTuple] = [
            AppViewStringTwoTuple.tuple(withFirst: "FirstItem", second: AppViewAutoLayoutConstraint.descriptionWithItemObject(constraint.firstItem, type: constraint.firstItemType, detailed: true)),
            AppViewStringTwoTuple.tuple(withFirst: "FirstAttribute", second: AppViewAutoLayoutConstraint.description(withAttributeInt: constraint.firstAttribute).lk_capitalizedString()),
            AppViewStringTwoTuple.tuple(withFirst: "Relation", second: AppViewAutoLayoutConstraint.description(with: constraint.relation)),
            AppViewStringTwoTuple.tuple(withFirst: "SecondItem", second: AppViewAutoLayoutConstraint.descriptionWithItemObject(constraint.secondItem, type: constraint.secondItemType, detailed: true)),
            AppViewStringTwoTuple.tuple(withFirst: "SecondAttribute", second: AppViewAutoLayoutConstraint.description(withAttributeInt: constraint.secondAttribute).lk_capitalizedString()),
            AppViewStringTwoTuple.tuple(withFirst: "Multiplier", second: "\(constraint.multiplier)"),
            AppViewStringTwoTuple.tuple(withFirst: "Constant", second: "\(constraint.constant)"),
            AppViewStringTwoTuple.tuple(withFirst: "Priority", second: "\(constraint.priority)"),
            AppViewStringTwoTuple.tuple(withFirst: "Active", second: constraint.active ? "YES" : "NO"),
            AppViewStringTwoTuple.tuple(withFirst: "ShouldBeArchived", second: constraint.shouldBeArchived ? "YES" : "NO"),
            AppViewStringTwoTuple.tuple(withFirst: "Identifier", second: constraint.identifier ?? ""),
        ]
        if constraint.firstItemType == .view, let image = NSImageMake("Icon_JumpDisclosure") {
            let button = NSButton.lk_button(with: image, target: self, action: #selector(handleJumpButton(_:)))
            button.appview_bindObject(constraint.firstItem, forKey: "jumpObject")
            textsView.add(button, atIndex: 0)
        }
        if constraint.secondItemType == .view, let image = NSImageMake("Icon_JumpDisclosure") {
            let button = NSButton.lk_button(with: image, target: self, action: #selector(handleJumpButton(_:)))
            button.appview_bindObject(constraint.secondItem, forKey: "jumpObject")
            textsView.add(button, atIndex: 3)
        }
        textsView.texts = texts
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func viewDidLayout() {
        super.viewDidLayout()
        if let titleView {
            lk(titleView).fullWidth().height(titleHeight).y(0)
        }
        let y = titleView != nil ? titleHeight : 0
        lk(textsView).sizeToFit().horAlign().y(y + textsViewMarginTop)
    }

    func contentSize() -> NSSize {
        var result = textsView.sizeThatFits(NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        if let titleView {
            result.width = max(result.width, titleView.sizeThatFits(NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).width)
            result.height += titleHeight
        }
        result.width += horInset * 2
        result.height += insetBottom + textsViewMarginTop
        return result
    }

    @objc private func handleJumpButton(_ button: NSButton) {
        guard let object = button.appview_getBindObject(forKey: "jumpObject") as? AppViewObject else {
            assertionFailure(); return
        }
        requestJumpingToObject?(object)
    }
}
