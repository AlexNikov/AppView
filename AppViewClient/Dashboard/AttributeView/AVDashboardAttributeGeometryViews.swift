import AppKit
import AppViewShared
import RxSwift

private enum DashboardGeometryInputHelper {
    static func layoutTwoColumn(_ views: [AVNumberInputView], in parent: NSView) {
        let itemWidth = (parent.frame.size.width - DashboardAttrItemHorInterspace) / 2
        for (idx, view) in views.enumerated() {
            let x = idx == 0 ? 0 : itemWidth + DashboardAttrItemHorInterspace
            lk(view).width(itemWidth).height(AVNumberInputHorizontalHeight).x(x).y(0)
        }
    }

    static func layoutFourGrid(_ views: [AVNumberInputView], in parent: NSView) {
        let itemWidth = (parent.frame.size.width - DashboardAttrItemHorInterspace) / 2
        for (idx, view) in views.enumerated() {
            let x = (idx == 0 || idx == 2) ? 0 : itemWidth + DashboardAttrItemHorInterspace
            let y = (idx == 0 || idx == 1) ? 0 : AVNumberInputHorizontalHeight + DashboardAttrItemVerInterspace
            lk(view).width(itemWidth).height(AVNumberInputHorizontalHeight).x(x).y(y)
        }
    }
}

final class AVDashboardAttributePointView: AVDashboardAttributeView, NSTextFieldDelegate {
    private var inputsView: [AVNumberInputView] = []
    private var modifyDisposable: Disposable?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        inputsView = ["X", "Y"].map { title in
            let view = AVNumberInputView()
            view.inputTitle = title
            view.viewStyle = .horizontal
            view.textFieldView.textField.delegate = self
            addSubview(view)
            return view
        }
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layout() {
        super.layout()
        DashboardGeometryInputHelper.layoutTwoColumn(inputsView, in: self)
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        NSSize(width: limitedSize.width, height: AVNumberInputHorizontalHeight)
    }

    override func renderWithAttribute() {
        guard case .cgPoint(let point)? = attribute?.value else { assertionFailure(); return }
        let strings = [
            NSString.appview_string(from: point.x, decimal: 3),
            NSString.appview_string(from: point.y, decimal: 3),
        ]
        for (idx, view) in inputsView.enumerated() {
            view.textFieldView.textField.isEditable = canEdit()
            view.textFieldView.textField.stringValue = strings[idx]
        }
    }

    override var dashboardViewController: AVDashboardViewController? {
        didSet { inputsView.forEach { $0.textFieldView.backgroundColorName = "DashboardCardValueBGColor" } }
    }

    func control(_ control: NSControl, textShouldBeginEditing fieldEditor: NSText) -> Bool { canEdit() }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let attribute, case .cgPoint(var point) = attribute.value else { return }
        if AVDashboardTextControlEditingFlag.sharedInstance.shouldIgnoreTextEditingChangeEvent { return }
        guard let field = notification.object as? NSTextField,
              let input = AVNumberInputView.parsedValue(with: field.stringValue, attrType: .double) else {
            renderWithAttribute()
            return
        }
        let fields = inputsView.map { $0.textFieldView.textField }
        guard let idx = fields.firstIndex(of: field) else { assertionFailure(); return }
        switch idx {
        case 0: point.x = AppViewAnyDoubleValue(input)
        case 1: point.y = AppViewAnyDoubleValue(input)
        default: return
        }
        let expected = AttributeValue.cgPoint(point)
        if expected == attribute.value { renderWithAttribute(); return }
        modifyDisposable = subscribeAttributeModification(newValue: expected, onSuccess: { [weak self] in
            self?.renderWithAttribute()
        })
    }
}

final class AVDashboardAttributeSizeView: AVDashboardAttributeView, NSTextFieldDelegate {
    private var inputsView: [AVNumberInputView] = []
    private var modifyDisposable: Disposable?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        inputsView = ["W", "H"].map { title in
            let view = AVNumberInputView()
            view.inputTitle = title
            view.viewStyle = .horizontal
            view.textFieldView.textField.delegate = self
            addSubview(view)
            return view
        }
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layout() {
        super.layout()
        DashboardGeometryInputHelper.layoutTwoColumn(inputsView, in: self)
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        NSSize(width: limitedSize.width, height: AVNumberInputHorizontalHeight)
    }

    override func renderWithAttribute() {
        guard case .cgSize(let size)? = attribute?.value else { assertionFailure(); return }
        let strings = [
            NSString.appview_string(from: size.width, decimal: 3),
            NSString.appview_string(from: size.height, decimal: 3),
        ]
        for (idx, view) in inputsView.enumerated() {
            view.textFieldView.textField.isEditable = canEdit()
            view.textFieldView.textField.stringValue = strings[idx]
        }
    }

    override var dashboardViewController: AVDashboardViewController? {
        didSet { inputsView.forEach { $0.textFieldView.backgroundColorName = "DashboardCardValueBGColor" } }
    }

    func control(_ control: NSControl, textShouldBeginEditing fieldEditor: NSText) -> Bool { canEdit() }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let attribute, case .cgSize(var size) = attribute.value else { return }
        if AVDashboardTextControlEditingFlag.sharedInstance.shouldIgnoreTextEditingChangeEvent { return }
        guard let field = notification.object as? NSTextField,
              let input = AVNumberInputView.parsedValue(with: field.stringValue, attrType: .double) else {
            renderWithAttribute()
            return
        }
        let fields = inputsView.map { $0.textFieldView.textField }
        guard let idx = fields.firstIndex(of: field) else { assertionFailure(); return }
        switch idx {
        case 0: size.width = AppViewAnyDoubleValue(input)
        case 1: size.height = AppViewAnyDoubleValue(input)
        default: return
        }
        let expected = AttributeValue.cgSize(size)
        if expected == attribute.value { renderWithAttribute(); return }
        modifyDisposable = subscribeAttributeModification(newValue: expected, onSuccess: { [weak self] in
            self?.renderWithAttribute()
        })
    }
}

final class AVDashboardAttributeRectView: AVDashboardAttributeView, NSTextFieldDelegate {
    private var mainInputsView: [AVNumberInputView] = []
    private var modifyDisposable: Disposable?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        mainInputsView = ["X", "Y", "W", "H"].map { title in
            let view = AVNumberInputView()
            view.inputTitle = title
            view.viewStyle = .horizontal
            view.textFieldView.textField.delegate = self
            view.textFieldView.backgroundColorName = "DashboardCardValueBGColor"
            addSubview(view)
            return view
        }
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layout() {
        super.layout()
        DashboardGeometryInputHelper.layoutFourGrid(mainInputsView, in: self)
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        NSSize(width: limitedSize.width, height: AVNumberInputHorizontalHeight * 2 + DashboardAttrItemVerInterspace)
    }

    override func renderWithAttribute() {
        guard case .cgRect(let rect)? = attribute?.value else { assertionFailure(); return }
        let strings = [
            NSString.appview_string(from: rect.origin.x, decimal: 3),
            NSString.appview_string(from: rect.origin.y, decimal: 3),
            NSString.appview_string(from: rect.size.width, decimal: 3),
            NSString.appview_string(from: rect.size.height, decimal: 3),
        ]
        for (idx, view) in mainInputsView.enumerated() {
            view.textFieldView.textField.isEditable = canEdit()
            view.textFieldView.textField.stringValue = strings[idx]
        }
    }

    func control(_ control: NSControl, textShouldBeginEditing fieldEditor: NSText) -> Bool { canEdit() }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let attribute, case .cgRect(var rect) = attribute.value else { return }
        if AVDashboardTextControlEditingFlag.sharedInstance.shouldIgnoreTextEditingChangeEvent { return }
        guard let field = notification.object as? NSTextField,
              let input = AVNumberInputView.parsedValue(with: field.stringValue, attrType: .double) else {
            renderWithAttribute()
            return
        }
        let fields = mainInputsView.map { $0.textFieldView.textField }
        guard let idx = fields.firstIndex(of: field) else { return }
        switch idx {
        case 0: rect.origin.x = AppViewAnyDoubleValue(input)
        case 1: rect.origin.y = AppViewAnyDoubleValue(input)
        case 2: rect.size.width = AppViewAnyDoubleValue(input)
        case 3: rect.size.height = AppViewAnyDoubleValue(input)
        default: return
        }
        let expected = AttributeValue.cgRect(rect)
        if expected == attribute.value { renderWithAttribute(); return }
        let oldRect = attribute.value.flatMap { value -> CGRect? in
            if case .cgRect(let current) = value { return current }
            return nil
        } ?? rect
        modifyDisposable = subscribeAttributeModification(
            newValue: expected,
            onError: { [weak self] in self?.renderWithAttribute() },
            onSuccess: { [weak self] in
                guard let self, let attribute = self.attribute, case .cgRect(let currentRect) = attribute.value else { return }
                if self.isAlmostEqual(oldRect, currentRect), !self.isAlmostEqual(rect, currentRect) {
                    AlertErrorText(
                        NSLocalizedString("The modification seems to have no effect.", comment: ""),
                        NSLocalizedString("After modifying successfully by AppView, the value seems to be recovered by the code in your iOS app. For example, modifying \"frame\" of a view may trigger \"layoutSubviews\", and \"layoutSubviews\" may modify the value again.", comment: ""),
                        self.window
                    )
                }
            }
        )
    }

    private func isAlmostEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.origin.x - b.origin.x) <= 0.1
            && abs(a.origin.y - b.origin.y) <= 0.1
            && abs(a.size.width - b.size.width) <= 0.1
            && abs(a.size.height - b.size.height) <= 0.1
    }
}

final class AVDashboardAttributeInsetsView: AVDashboardAttributeView, NSTextFieldDelegate {
    private var mainInputsView: [AVNumberInputView] = []
    private var modifyDisposable: Disposable?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        mainInputsView = ["T", "L", "B", "R"].map { title in
            let view = AVNumberInputView()
            view.inputTitle = title
            view.viewStyle = .horizontal
            view.textFieldView.textField.delegate = self
            addSubview(view)
            return view
        }
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layout() {
        super.layout()
        DashboardGeometryInputHelper.layoutFourGrid(mainInputsView, in: self)
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        NSSize(width: limitedSize.width, height: AVNumberInputHorizontalHeight * 2 + DashboardAttrItemVerInterspace)
    }

    override func renderWithAttribute() {
        guard case .edgeInsets(let insets)? = attribute?.value else { assertionFailure(); return }
        let strings = [
            NSString.appview_string(from: insets.top, decimal: 3),
            NSString.appview_string(from: insets.left, decimal: 3),
            NSString.appview_string(from: insets.bottom, decimal: 3),
            NSString.appview_string(from: insets.right, decimal: 3),
        ]
        for (idx, view) in mainInputsView.enumerated() {
            view.textFieldView.textField.isEditable = canEdit()
            view.textFieldView.textField.stringValue = strings[idx]
        }
    }

    override var dashboardViewController: AVDashboardViewController? {
        didSet { mainInputsView.forEach { $0.textFieldView.backgroundColorName = "DashboardCardValueBGColor" } }
    }

    func control(_ control: NSControl, textShouldBeginEditing fieldEditor: NSText) -> Bool { canEdit() }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard canEdit(), let attribute, case .edgeInsets(var insets) = attribute.value else { return }
        if AVDashboardTextControlEditingFlag.sharedInstance.shouldIgnoreTextEditingChangeEvent { return }
        guard let field = notification.object as? NSTextField,
              let input = AVNumberInputView.parsedValue(with: field.stringValue, attrType: .double) else {
            renderWithAttribute()
            return
        }
        let fields = mainInputsView.map { $0.textFieldView.textField }
        guard let idx = fields.firstIndex(of: field) else { return }
        let origin = insets
        switch idx {
        case 0: insets.top = AppViewAnyDoubleValue(input)
        case 1: insets.left = AppViewAnyDoubleValue(input)
        case 2: insets.bottom = AppViewAnyDoubleValue(input)
        case 3: insets.right = AppViewAnyDoubleValue(input)
        default: return
        }
        if origin.top == insets.top && origin.left == insets.left
            && origin.bottom == insets.bottom && origin.right == insets.right {
            renderWithAttribute()
            return
        }
        modifyDisposable = subscribeAttributeModification(newValue: .edgeInsets(insets), onSuccess: { [weak self] in
            self?.renderWithAttribute()
        })
    }
}
