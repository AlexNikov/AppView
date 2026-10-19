//
//  AVConsoleSubmitRowView.swift
//  AppView
//

import AppKit
import AppViewShared

class AVConsoleSubmitRowView: AVTableRowView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.isSelectable = true
        titleLabel.font = NSFontMake(13)
        subtitleLabel.isSelectable = true
        subtitleLabel.textColor = .labelColor
        subtitleLabel.font = NSFontMake(13)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        var titleSize = titleLabel.sizeThatFits(NSSizeMax)
        titleSize.width = min(titleSize.width, bounds.width * 0.5)
        lk(titleLabel).x(ConsoleInsetLeft).width(titleSize.width).height(titleSize.height).verAlign()
        lk(subtitleLabel).x(titleLabel.frame.maxX + 5).toRight(ConsoleInsetRight).heightToFit().verAlign()
    }

    override func setIsDarkMode(_ isDarkMode: Bool) {
        super.setIsDarkMode(AppViewClientIsDarkMode())
        titleLabel.textColor = AppViewClientIsDarkMode() ? AppViewColorMake(85, 200, 95) : AppViewColorMake(54, 155, 62)
    }
}
