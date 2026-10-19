//
//  AVOutlineRowView.swift
//  AppView
//

import AppKit

enum AVOutlineRowViewStatus: UInt {
    case notExpandable
    case expanded
    case collapsed
}

class AVOutlineRowView: AVTableRowView {
    private static let indentUnitWidth: CGFloat = 14
    private static let disclosureWidth: CGFloat = 16

    private(set) var disclosureButton: NSButton!
    private(set) var imageView: NSImageView!

    var image: NSImage? {
        didSet {
            imageView.image = image
            imageView.isHidden = image == nil
            needsLayout = true
        }
    }

    var status: AVOutlineRowViewStatus = .notExpandable {
        didSet { updateDisclosureButton() }
    }

    var indentLevel: UInt = 0 {
        didSet { needsLayout = true }
    }

    private var useCompactUI = false
    private var imageLeft: CGFloat = 5
    private var imageRight: CGFloat = 2
    private var titleLeft: CGFloat = 2
    private var subtitleLeft: CGFloat = 10

    convenience init(compactUI: Bool) {
        self.init(frame: .zero)
        useCompactUI = compactUI
        if compactUI {
            titleLeft = 0
            subtitleLeft = 2
        } else {
            titleLeft = 2
            subtitleLeft = 10
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupOutlineSubviews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupOutlineSubviews()
    }

    override var isSelected: Bool {
        get { super.isSelected }
        set {
            super.isSelected = newValue
            updateDisclosureButton()
        }
    }

    private func setupOutlineSubviews() {
        disclosureButton = NSButton()
        disclosureButton.isBordered = false
        disclosureButton.setButtonType(.momentaryChange)
        addSubview(disclosureButton)

        imageView = NSImageView()
        imageView.isHidden = true
        addSubview(imageView)
    }

    override func layout() {
        super.layout()

        lk(disclosureButton)
            .width(Self.disclosureWidth)
            .fullHeight()
            .midX(Self.dislosureMidX(withIndentLevel: indentLevel))
            .verAlign()

        var x = disclosureButton.frame.maxX
        if !imageView.isHidden {
            if let img = imageView.image {
                imageView.frame.size = img.size
            }
            lk(imageView).verAlign().x(x + imageLeft)
            x = imageView.frame.maxX + imageRight
        }

        lk(titleLabel).sizeToFit().x(x + titleLeft).verAlign()
        var maxX = titleLabel.frame.maxX

        if !subtitleLabel.isHidden {
            lk(subtitleLabel).sizeToFit().x(titleLabel.frame.maxX + subtitleLeft).verAlign()
            maxX = subtitleLabel.frame.maxX
        }
        lk(disclosureButton, titleLabel, subtitleLabel).visibles().offsetY(-1)

        horizontalScrollWidthManager?.rowDidLayout(withWidth: maxX)
    }

    class func dislosureMidX(withIndentLevel level: UInt) -> CGFloat {
        insetLeft() + CGFloat(level) * indentUnitWidth + disclosureWidth / 2.0
    }

    class func insetLeft() -> CGFloat { 6 }

    private func updateDisclosureButton() {
        switch status {
        case .notExpandable:
            disclosureButton.isHidden = true
        case .expanded:
            disclosureButton.isHidden = false
            disclosureButton.image = NSImageMake(isSelected ? "icon_arrow_down_selected" : "icon_arrow_down")
        case .collapsed:
            disclosureButton.isHidden = false
            disclosureButton.image = NSImageMake(isSelected ? "icon_arrow_right_selected" : "icon_arrow_right")
        }
    }
}
