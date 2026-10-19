import AppKit
import AppViewShared

final class AVJSONAttributeViewController: AVBaseViewController {
    private var contentView: AVJSONAttributeContentView!

    override func makeContainerView() -> NSView {
        let containerView = AVBaseView()
        contentView = AVJSONAttributeContentView(bigFont: true)
        containerView.addSubview(contentView)
        return containerView
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        lk(contentView).fullFrame().toY(28)
    }

    func render(withJSON json: String) {
        render(withJSONValue: .json(json))
    }

    func render(withJSONValue value: AttributeValue?) {
        contentView.render(withJSONValue: value)
    }
}
