//
//  AVTipsView.swift
//  AppView
//

import AppKit
import AppViewShared

class AVTipsView: AVBaseView {
    weak var bindingObject: AnyObject?

    var title: String? {
        didSet { titleLabel.stringValue = title ?? "" }
    }

    private(set) var button: NSButton!
    var buttonText: String? {
        didSet { updateButton() }
    }

    var buttonImage: NSImage? {
        didSet { updateButton() }
    }

    var image: NSImage? {
        didSet {
            imageView.image = image
            imageView.isHidden = image == nil
        }
    }

    weak var target: AnyObject?
    var clickAction: Selector?
    var didClick: ((AVTipsView) -> Void)?

    fileprivate var titleLabel: AVLabel!
    private var imageView: NSImageView!
    fileprivate var sepLayer: CALayer!

    private let insetLeft: CGFloat = 12
    private var insetRightWithButton: CGFloat = 3
    private var insetRightWithoutButton: CGFloat = 8
    private var imageRight: CGFloat = 4
    private let sepLeft: CGFloat = 7
    private let imageSize = NSSize(width: 18, height: 18)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.borderWidth = 1

        imageView = NSImageView()
        imageView.isHidden = true
        addSubview(imageView)

        titleLabel = AVLabel()
        titleLabel.font = NSFontMake(13)
        addSubview(titleLabel)

        button = NSButton()
        button.font = NSFontMake(13)
        button.isBordered = false
        button.bezelStyle = .smallSquare
        button.target = self
        button.action = #selector(handleButton)
        button.isHidden = true
        addSubview(button)

        sepLayer = CALayer()
        sepLayer.appview_removeImplicitAnimations()
        sepLayer.isHidden = true
        layer?.addSublayer(sepLayer)

        updateColors()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2

        var x = insetLeft
        if !imageView.isHidden {
            lk(imageView).size(imageSize).verAlign().x(x)
            x = imageView.frame.maxX + imageRight
        }

        lk(titleLabel).sizeToFit().verAlign().x(x)
        x = titleLabel.frame.maxX

        if !sepLayer.isHidden {
            lk(sepLayer).width(1).fullHeight().x(x + sepLeft)
            x = sepLayer.frame.maxX
        }

        if !button.isHidden {
            lk(button).x(x).toRight(insetRightWithButton).fullHeight()
        }
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        let height: CGFloat = 28
        var width = insetLeft
        if !imageView.isHidden {
            width += imageSize.width + imageRight
        }
        width += titleLabel.sizeThatFits(NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)).width
        if !sepLayer.isHidden {
            width += sepLeft + 1
        }
        if !button.isHidden {
            width += button.sizeThatFits(NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)).width + 16
        } else {
            width += insetRightWithoutButton
        }
        return NSSize(width: width, height: height)
    }

    override func updateColors() {
        super.updateColors()
        backgroundColor = isDarkMode() ? AppViewColorRGBAMake(0, 0, 0, 0.8) : AppViewColorRGBAMake(255, 255, 255, 0.9)
        titleLabel.textColor = isDarkMode() ? AppViewColorMake(197, 198, 199) : AppViewColorMake(108, 109, 110)
        let borderColor = isDarkMode() ? AppViewColorMake(43, 44, 45) : AppViewColorMake(216, 217, 218)
        layer?.borderColor = borderColor.cgColor
        sepLayer.backgroundColor = borderColor.cgColor
        updateButton()
    }

    func setImageByDeviceType(_ type: AppViewAppInfoDevice) {
        switch type {
        case .simulator:
            image = NSImageMake("icon_simulator_big")
        case .iPad:
            image = NSImageMake("icon_ipad_big")
        case .others:
            image = NSImageMake("icon_iphone_big")
        @unknown default:
            assertionFailure()
        }
    }

    func setInternalInsetsRight(_ value: CGFloat) {
        insetRightWithButton = value
        insetRightWithoutButton = value
        imageRight = value
    }

    @objc private func handleButton() {
        if let target, let clickAction {
            _ = NSApp.sendAction(clickAction, to: target, from: self)
        }
        didClick?(self)
    }

    func buttonTextColor() -> NSColor {
        isDarkMode() ? AppViewColorMake(64, 134, 216) : AppViewColorMake(74, 145, 228)
    }

    private func updateButton() {
        button.isHidden = false
        sepLayer.isHidden = false

        if let buttonText {
            button.attributedTitle = AVAttrString(buttonText).textColor(buttonTextColor()).build()
            button.image = nil
        } else if let buttonImage {
            button.title = ""
            button.image = buttonImage
        } else {
            button.isHidden = true
            sepLayer.isHidden = true
        }
        needsLayout = true
    }
}

class AVYellowTipsView: AVTipsView {
    private var isAnimating = false

    func startAnimation() {
        if isAnimating { return }
        let anim = CABasicAnimation(keyPath: "backgroundColor")
        if effectiveAppearance.lk_isDarkMode {
            anim.fromValue = NSColor.systemOrange.withAlphaComponent(0.7).cgColor
            anim.toValue = NSColor.systemOrange.withAlphaComponent(0.64).cgColor
        } else {
            anim.fromValue = NSColor.systemOrange.withAlphaComponent(0.98).cgColor
            anim.toValue = NSColor.systemOrange.withAlphaComponent(0.92).cgColor
        }
        anim.duration = 0.8
        anim.repeatCount = .infinity
        anim.autoreverses = true
        layer?.removeAllAnimations()
        layer?.add(anim, forKey: nil)
        isAnimating = true
    }

    func endAnimation() {
        layer?.removeAllAnimations()
        isAnimating = false
    }

    override func updateColors() {
        super.updateColors()
        titleLabel.textColor = .white
        layer?.borderColor = NSColor.clear.cgColor
        sepLayer.backgroundColor = AppViewColorRGBAMake(255, 255, 255, 0.5).cgColor
    }

    override func buttonTextColor() -> NSColor {
        .white
    }
}

class AVRedTipsView: AVTipsView {
    func startAnimation() {
        let anim = CABasicAnimation(keyPath: "backgroundColor")
        anim.fromValue = AppViewColorRGBAMake(208, 2, 27, 0.9).cgColor
        anim.toValue = AppViewColorRGBAMake(208, 2, 27, 0.7).cgColor
        anim.duration = 0.8
        anim.repeatCount = .infinity
        anim.autoreverses = true
        layer?.removeAllAnimations()
        layer?.add(anim, forKey: nil)
    }

    func endAnimation() {
        layer?.removeAllAnimations()
    }

    override func updateColors() {
        super.updateColors()
        titleLabel.textColor = .white
        layer?.borderColor = NSColor.clear.cgColor
        sepLayer.backgroundColor = AppViewColorRGBAMake(255, 255, 255, 0.5).cgColor
    }

    override func buttonTextColor() -> NSColor {
        .white
    }
}
