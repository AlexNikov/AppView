//
//  AVTutorialPopoverController.swift
//  AppView
//

import AppKit

class AVTutorialPopoverController: AVBaseViewController {
    var showTimestamp: TimeInterval = 0
    var hasClickedCloseButton = false
    var learnedBlock: (() -> Void)?

    private var imageView: NSImageView!
    private var label: AVLabel!
    private var closeButton: NSButton!
    private weak var popover: NSPopover?

    private let insets = NSEdgeInsets(top: 12, left: 8, bottom: 10, right: 8)
    private let labelMarginLeft: CGFloat = 5

    init(text: String, popover: NSPopover) {
        self.popover = popover
        super.init(containerView: nil)
        label.stringValue = text
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func makeContainerView() -> NSView {
        let containerView = super.makeContainerView()

        imageView = NSImageView()
        imageView.image = NSImageMake("Icon_Inspiration")
        containerView.addSubview(imageView)

        label = AVLabel()
        label.font = NSFontMake(13)
        containerView.addSubview(label)

        closeButton = NSButton.lk_normalButton(
            withTitle: NSLocalizedString("Do not show again", comment: ""),
            target: self,
            action: #selector(handleCloseButton)
        )
        containerView.addSubview(closeButton)

        return containerView
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        lk(imageView).sizeToFit().x(insets.left)
        lk(label).x(imageView.frame.maxX + labelMarginLeft).toRight(insets.right).heightToFit().y(insets.top)
        lk(imageView).midY(label.frame.midY - 1)
        lk(closeButton).sizeToFit().horAlign().bottom(insets.bottom)
    }

    func contentSize() -> NSSize {
        let imageWidth = imageView.image?.size.width ?? 0
        let maxWidth: CGFloat = 400
        let labelMaxWidth = maxWidth - imageWidth - insets.left - insets.right - labelMarginLeft
        let labelSize = label.sizeThatFits(NSSize(width: labelMaxWidth, height: .greatestFiniteMagnitude))
        return NSSize(
            width: imageWidth + insets.left + insets.right + labelSize.width + labelMarginLeft,
            height: labelSize.height + 60
        )
    }

    @objc private func handleCloseButton() {
        hasClickedCloseButton = true
        popover?.close()
    }
}
