//
//  AVBaseView.swift
//  AppView
//

import AppKit

class AVVisualEffectView: NSVisualEffectView {
    override var isFlipped: Bool { true }
}

class AVBaseView: NSView {
    var tooltipString: String? {
        didSet {
            if tooltipString != nil {
                addToolTip(bounds, owner: self, userData: nil)
            } else {
                removeAllToolTips()
            }
        }
    }

    var backgroundColor: NSColor? {
        didSet {
            layer?.backgroundColor = backgroundColor?.cgColor
        }
    }

    var backgroundColors: AVTwoColors? {
        didSet { updateColors() }
    }

    var borderPosition: AVViewBorderPosition = .none {
        didSet {
            if borderPosition == .none {
                customBorderLayer?.removeFromSuperlayer()
                return
            }
            if customBorderLayer == nil {
                let layer = CALayer()
                customBorderLayer = layer
                layer.appview_removeImplicitAnimations()
                updateColors()
                self.layer?.addSublayer(layer)
            }
            needsLayout = true
        }
    }

    var borderColors: AVTwoColors? = AVColorsCombine(SeparatorLightModeColor, SeparatorDarkModeColor) {
        didSet { updateColors() }
    }


    var didChangeAppearanceBlock: ((AVBaseView, Bool) -> Void)? {
        didSet { triggerDidChangeAppearanceBlock() }
    }

    var didLayout: (() -> Void)?

    var hasEffectedBackground = false {
        didSet {
            if hasEffectedBackground {
                guard backgroundEffectView == nil else { return }
                let effectView = AVVisualEffectView()
                backgroundEffectView = effectView
                effectView.blendingMode = .withinWindow
                effectView.state = .active
                lk_insertSubviewAtBottom(effectView)
                needsLayout = true
            } else {
                backgroundEffectView?.removeFromSuperview()
                backgroundEffectView = nil
            }
        }
    }

    private var customBorderLayer: CALayer?
    private var backgroundEffectView: AVVisualEffectView?

    override var isVisible: Bool {
        superview != nil && !isHidden && alphaValue >= 0.01
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        borderColors = AVColorsCombine(SeparatorLightModeColor, SeparatorDarkModeColor)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isHidden || alphaValue <= 0 { return nil }
        return super.hitTest(point)
    }

    override func layout() {
        super.layout()

        if let backgroundEffectView {
            lk(backgroundEffectView).fullFrame()
        }

        if tooltipString != nil {
            addToolTip(bounds, owner: self, userData: nil)
        } else {
            removeAllToolTips()
        }

        if let customBorderLayer {
            switch borderPosition {
            case .none:
                break
            case .top:
                lk(customBorderLayer).fullWidth().height(1).y(0)
            case .left:
                lk(customBorderLayer).fullHeight().width(1).x(0)
            case .bottom:
                lk(customBorderLayer).fullFrame().height(1).bottom(0)
            case .right:
                lk(customBorderLayer).fullHeight().width(1).right(0)
            @unknown default:
                break
            }
        }

        didLayout?()
    }

    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        tooltipString ?? ""
    }

    func heightForWidth(_ width: CGFloat) -> CGFloat {
        sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    override func updateLayer() {
        super.updateLayer()
        if let backgroundColorName {
            layer?.backgroundColor = NSColor(named: backgroundColorName)?.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        triggerDidChangeAppearanceBlock()
    }

    func isDarkMode() -> Bool {
        effectiveAppearance.lk_isDarkMode
    }

    private func triggerDidChangeAppearanceBlock() {
        didChangeAppearanceBlock?(self, isDarkMode())
        updateColors()
    }

    func updateColors() {
        if let backgroundColors {
            layer?.backgroundColor = backgroundColors.color?.cgColor
        }
        if let borderColors {
            layer?.borderColor = borderColors.color?.cgColor
            customBorderLayer?.backgroundColor = borderColors.color?.cgColor
        }
    }


    func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        .zero
    }

    func sizeToFit() {}
}
