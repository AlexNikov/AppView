//
//  AVPopPanel.swift
//  AppView
//

import AppKit
import AppViewShared

class AVPopPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: .nonactivatingPanel,
                   backing: .buffered,
                   defer: true)
        let contentView = AVBaseView()
        contentView.layer?.cornerRadius = 6
        contentView.layer?.borderWidth = 1
        contentView.didChangeAppearanceBlock = { view, isDarkMode in
            view.backgroundColor = isDarkMode ? AppViewColorMake(44, 44, 44) : AppViewColorMake(236, 236, 236)
            view.layer?.borderColor = isDarkMode ? SeparatorDarkModeColor.cgColor : SeparatorLightModeColor.cgColor
        }
        self.contentView = contentView
        backgroundColor = .clear
    }

    override var canBecomeKey: Bool { true }
}
