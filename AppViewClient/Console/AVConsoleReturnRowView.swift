//
//  AVConsoleReturnRowView.swift
//  AppView
//

import AppKit

class AVConsoleReturnRowView: AVTableRowView {
    private var insets = NSEdgeInsets(top: 0, left: ConsoleInsetLeft, bottom: 5, right: ConsoleInsetRight)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.isSelectable = true
        titleLabel.textColor = .labelColor
        titleLabel.font = NSFontMake(13)
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        lk(titleLabel).x(insets.left).toRight(insets.right).heightToFit().y(insets.top)
    }

    func heightForWidth(_ width: CGFloat) -> CGFloat {
        let height = titleLabel.sizeThatFits(
            NSSize(width: width - insets.left - insets.right, height: .greatestFiniteMagnitude)
        ).height
        return height + insets.top + insets.bottom
    }
}
