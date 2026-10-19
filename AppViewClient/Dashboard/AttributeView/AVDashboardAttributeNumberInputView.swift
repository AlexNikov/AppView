import AppKit
import AppViewShared
import RxSwift

final class AVDashboardAttributeNumberInputView: AVDashboardAttributeView, NSTextFieldDelegate {
    private(set) var inputView: AVNumberInputView!
    private var modifyDisposable: Disposable?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        inputView = AVNumberInputView()
        inputView.textFieldView.textField.delegate = self
        addSubview(inputView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        lk(inputView).fullFrame()
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        var size = limitedSize
        switch inputView.viewStyle {
        case .horizontal: size.height = AVNumberInputHorizontalHeight
        case .vertical: size.height = AVNumberInputVerticalHeight
        @unknown default: assertionFailure()
        }
        return size
    }

    override func renderWithAttribute() {
        guard let attribute else { return }
        inputView.textFieldView.textField.isEditable = canEdit()
        if attribute.isUserCustom() {
            inputView.inputTitle = nil
        } else {
            inputView.inputTitle = AppViewDashboardBlueprint.briefTitle(withAttrID: attribute.identifier ?? "")
        }
        let doubleValue = attribute.value.dashboardDoubleValue
        if attribute.isUserCustom() {
            inputView.viewStyle = .horizontal
            inputView.textFieldView.textField.stringValue = NSString.appview_string(from: doubleValue, decimal: 6)
        } else {
            let horizontalAttrs: Set<AppViewAttrIdentifier> = [
                AppViewAttr_ViewLayer_Visibility_Opacity, AppViewAttr_ViewLayer_Corner_Radius, AppViewAttr_ViewLayer_Tag_Tag,
                AppViewAttr_UILabel_Font_Size, AppViewAttr_UILabel_NumberOfLines_NumberOfLines, AppViewAttr_UITextView_Font_Size,
                AppViewAttr_UITextField_Font_Size, AppViewAttr_UITextField_CanAdjustFont_MinSize, AppViewAttr_ViewLayer_Border_Width,
                AppViewAttr_UITableView_SectionsNumber_Number, AppViewAttr_AutoLayout_Resistance_Ver, AppViewAttr_AutoLayout_Resistance_Hor,
                AppViewAttr_AutoLayout_Hugging_Ver, AppViewAttr_AutoLayout_Hugging_Hor, AppViewAttr_UIStackView_Spacing_Spacing,
            ]
            if horizontalAttrs.contains(attribute.identifier ?? "") {
                inputView.viewStyle = .horizontal
                inputView.textFieldView.textField.stringValue = NSString.appview_string(from: doubleValue, decimal: 3)
            } else {
                inputView.viewStyle = .vertical
                inputView.textFieldView.textField.stringValue = NSString.appview_string(from: doubleValue, decimal: 2)
            }
        }
    }

    override func numberOfColumnsOccupied() -> UInt {
        guard let attribute, !attribute.isUserCustom() else { return 1 }
        let dict: [AppViewAttrIdentifier: UInt] = [
            AppViewAttr_ViewLayer_Visibility_Opacity: 1, AppViewAttr_ViewLayer_Corner_Radius: 1, AppViewAttr_ViewLayer_Tag_Tag: 1,
            AppViewAttr_UITextView_Font_Size: 1, AppViewAttr_UITextField_Font_Size: 1, AppViewAttr_UITextField_CanAdjustFont_MinSize: 1,
            AppViewAttr_ViewLayer_Border_Width: 1, AppViewAttr_UITableView_SectionsNumber_Number: 1, AppViewAttr_UILabel_NumberOfLines_NumberOfLines: 1,
            AppViewAttr_UILabel_Font_Size: 1, AppViewAttr_UIStackView_Spacing_Spacing: 1,
            AppViewAttr_AutoLayout_Resistance_Ver: 2, AppViewAttr_AutoLayout_Resistance_Hor: 2, AppViewAttr_AutoLayout_Hugging_Ver: 2, AppViewAttr_AutoLayout_Hugging_Hor: 2,
            AppViewAttr_UIScrollView_Zoom_Scale: 3, AppViewAttr_UIScrollView_Zoom_MinScale: 3, AppViewAttr_UIScrollView_Zoom_MaxScale: 3,
        ]
        return dict[attribute.identifier ?? ""] ?? 4
    }

    override var dashboardViewController: AVDashboardViewController? {
        didSet { inputView.textFieldView.backgroundColorName = "DashboardCardValueBGColor" }
    }

    func control(_ control: NSControl, textShouldBeginEditing fieldEditor: NSText) -> Bool { canEdit() }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let attribute else { return }
        if AVDashboardTextControlEditingFlag.sharedInstance.shouldIgnoreTextEditingChangeEvent { return }
        guard let parsed = AVNumberInputView.parsedValue(with: inputView.textFieldView.textField.stringValue, attrType: attribute.attrType) as? NSNumber else {
            renderWithAttribute()
            return
        }
        var doubleValue = parsed.doubleValue
        if attribute.identifier == AppViewAttr_ViewLayer_Visibility_Opacity || attribute.identifier == AppViewAttr_ViewLayer_Shadow_Opacity {
            doubleValue = max(min(doubleValue, 1), 0)
        }
        let expectedValue = AttributeValue.from(double: doubleValue, attrType: attribute.attrType)
        if expectedValue == attribute.value { renderWithAttribute(); return }
        modifyDisposable = subscribeAttributeModification(newValue: expectedValue, onSuccess: { [weak self] in self?.renderWithAttribute() })
    }
}
