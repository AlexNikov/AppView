//
//  AVLabel.swift
//  AppView
//

import AppKit

class AVLabel: NSTextField {
    var textColors: AVTwoColors? {
        didSet { updateColors() }
    }

    var backgroundColors: AVTwoColors? {
        didSet { updateColors() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        backgroundColor = .clear
        isBezeled = false
        drawsBackground = true
        isEditable = false
        isSelectable = false
        updateColors()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var stringValue: String {
        get { super.stringValue }
        set { super.stringValue = newValue }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        if let textColors {
            textColor = textColors.color
        }
        if let backgroundColors {
            backgroundColor = backgroundColors.color
        }
    }
}
