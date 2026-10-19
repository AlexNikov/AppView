//
//  AVTableRowView.swift
//  AppView
//

import AppKit
import AppViewShared

class AVTableRowView: NSTableRowView {
    private(set) var titleLabel: AVLabel!
    private(set) var subtitleLabel: AVLabel!
    private var backgroundColorLayer: CALayer!

    private var _appviewSelected = false
    private var _appviewHovered = false
    private var _isDarkMode = false

    override var isSelected: Bool {
        get { _appviewSelected }
        set {
            _appviewSelected = newValue
            updateBackgroundLayerColor()
        }
    }

    var isHovered: Bool {
        get { _appviewHovered }
        set {
            _appviewHovered = newValue
            updateBackgroundLayerColor()
        }
    }

    var isDarkMode: Bool {
        _isDarkMode
    }

    weak var horizontalScrollWidthManager: AVTableViewHorizontalScrollWidthManager?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        backgroundColorLayer = CALayer()
        backgroundColorLayer.appview_removeImplicitAnimations()
        layer?.addSublayer(backgroundColorLayer)

        titleLabel = AVLabel()
        titleLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(titleLabel)

        subtitleLabel = AVLabel()
        addSubview(subtitleLabel)

        _isDarkMode = effectiveAppearance.lk_isDarkMode
        updateBackgroundLayerColor()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        lk(backgroundColorLayer).fullFrame()
    }

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        _isDarkMode = effectiveAppearance.lk_isDarkMode
        updateBackgroundLayerColor()
    }

    func setIsDarkMode(_ isDarkMode: Bool) {
        _isDarkMode = isDarkMode
        updateBackgroundLayerColor()
    }

    private func updateBackgroundLayerColor() {
        if _appviewSelected {
            backgroundColorLayer.backgroundColor = AVHelper.accentColor().cgColor
        } else if _appviewHovered {
            backgroundColorLayer.backgroundColor = _isDarkMode
                ? AppViewColorRGBAMake(255, 255, 255, 0.15).cgColor
                : AppViewColorRGBAMake(0, 0, 0, 0.1).cgColor
        } else {
            backgroundColorLayer.backgroundColor = NSColor.clear.cgColor
        }
    }
}

class AVTableBlankRowView: AVTableRowView {}
