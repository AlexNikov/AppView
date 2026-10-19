import AppKit
import AppViewShared

final class AVDashboardAttributeRowsCountView: AVDashboardAttributeView {
    private var inputsView: [AVNumberInputView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        inputsView = []
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        for (idx, view) in inputsView.enumerated() {
            let y = CGFloat(idx) * (AVNumberInputHorizontalHeight + DashboardAttrItemVerInterspace)
            lk(view).fullWidth().height(AVNumberInputHorizontalHeight).y(y)
        }
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        var size = limitedSize
        let height = CGFloat(inputsView.count) * (AVNumberInputHorizontalHeight + DashboardAttrItemVerInterspace) - DashboardAttrItemVerInterspace
        size.height = max(height, 0)
        return size
    }

    override func renderWithAttribute() {
        guard let attribute,
              case .customObject(let rawValue)? = attribute.value,
              let numbers = rawValue as? [NSNumber] else {
            assertionFailure()
            return
        }
        inputsView = inputsView.appview_resize(withCount: numbers.count, add: { [weak self] _ in
            let view = AVNumberInputView()
            view.textFieldView.textField.isEditable = false
            view.viewStyle = .horizontal
            view.textFieldView.backgroundColorName = "DashboardCardValueBGColor"
            self?.addSubview(view)
            return view
        }, remove: { _, view in
            view.removeFromSuperview()
        }, doNext: { idx, view in
            view.inputTitle = "Section \(Int(idx) + 1)"
            view.textFieldView.textField.stringValue = "\(numbers[Int(idx)])"
        })
        needsLayout = true
    }

    override var dashboardViewController: AVDashboardViewController? {
        didSet {
            inputsView.forEach { $0.textFieldView.backgroundColorName = "DashboardCardValueBGColor" }
        }
    }
}
