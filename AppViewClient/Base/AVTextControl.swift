//
//  AVTextControl.swift
//  AppView
//

import AppKit

class AVTextControl: AVBaseControl {
    private(set) var label: AVLabel!
    private var rightImageView: NSImageView?

    var insets = NSEdgeInsetsZero {
        didSet { needsLayout = true }
    }

    var rightImage: NSImage? {
        didSet {
            if let rightImage {
                if rightImageView == nil {
                    let imageView = NSImageView()
                    rightImageView = imageView
                    addSubview(imageView)
                }
                rightImageView?.image = rightImage
            } else {
                rightImageView?.removeFromSuperview()
                rightImageView = nil
            }
            needsLayout = true
        }
    }

    var spaceBetweenLabelAndImage: CGFloat = 0 {
        didSet { needsLayout = true }
    }

    var rightImageOffsetY: CGFloat = 0 {
        didSet { needsLayout = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label = AVLabel()
        label.alignment = .center
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        var labelMaxX = bounds.width - insets.right
        if let rightImageView, !rightImageView.isHidden {
            lk(rightImageView).sizeToFit().verAlign().right(insets.right).offsetY(rightImageOffsetY)
            labelMaxX = rightImageView.frame.origin.x - spaceBetweenLabelAndImage
        }
        lk(label).x(insets.left).toMaxX(labelMaxX).heightToFit().verAlign()
        if insets.top != insets.bottom {
            lk(label).offsetY(insets.top - insets.bottom)
        }
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        var labelMaxWidth = limitedSize.width - insets.left - insets.right
        if let rightImageView, !rightImageView.isHidden {
            labelMaxWidth -= (rightImageView.bestWidth + spaceBetweenLabelAndImage)
        }
        let labelSize = label.sizeThatFits(NSSize(width: labelMaxWidth, height: .greatestFiniteMagnitude))
        var resultWidth = labelSize.width + insets.left + insets.right
        if let rightImageView, !rightImageView.isHidden {
            resultWidth += (rightImageView.bestWidth + spaceBetweenLabelAndImage)
        }
        let resultHeight = labelSize.height + insets.top + insets.bottom
        return NSSize(width: resultWidth, height: resultHeight)
    }
}
