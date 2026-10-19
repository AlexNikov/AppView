//
//  AVTextsMenuView.swift
//  AppView
//

import AppKit
import AppViewShared

enum AVTextsMenuViewType: Int {
    case justified
    case center
}

class AVTextsMenuView: AVBaseView {
    var insets = NSEdgeInsets(top: 0, left: 3, bottom: 0, right: 5)
    var type: AVTextsMenuViewType = .justified {
        didSet { updateAlignments() }
    }

    var texts: [AppViewStringTwoTuple]? {
        didSet { applyTexts() }
    }

    var font: NSFont? {
        didSet {
            leftLabels.forEach { $0.font = font }
            rightLabels.forEach { $0.font = font }
        }
    }

    var verSpace: CGFloat = 2
    var horSpace: CGFloat = 10

    private var leftLabels: [AVLabel] = []
    private var rightLabels: [AVLabel] = []
    private var buttons: [Int: NSButton] = [:]
    private let buttonMarginLeft: CGFloat = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func add(_ button: NSButton, atIndex idx: Int) {
        guard buttons[idx] == nil else {
            assertionFailure()
            return
        }
        buttons[idx] = button
        addSubview(button)
        needsLayout = true
    }

    override func layout() {
        super.layout()

        let visibleRightLabels = (rightLabels as NSArray).lk_visibleViews() as? [AVLabel] ?? []
        let visibleLeftLabels = (leftLabels as NSArray).lk_visibleViews() as? [AVLabel] ?? []

        if type == .center {
            var leftLabelMaxWidth = insets.left
            for (idx, leftLabel) in visibleLeftLabels.enumerated() {
                let prevLeftLabel = idx > 0 ? visibleLeftLabels[idx - 1] : nil
                let y = prevLeftLabel.map { $0.frame.maxY + verSpace } ?? 0
                lk(leftLabel).sizeToFit().y(y)
                leftLabelMaxWidth = max(leftLabelMaxWidth, leftLabel.frame.width + insets.left)
            }
            for (idx, leftLabel) in visibleLeftLabels.enumerated() {
                lk(leftLabel).maxX(leftLabelMaxWidth)
                let midY = leftLabel.frame.midY
                let rightLabel = visibleRightLabels[idx]
                lk(rightLabel).x(leftLabelMaxWidth + horSpace).sizeToFit().midY(midY)
                if let button = buttons[idx] {
                    var x = rightLabel.frame.maxX
                    if !rightLabel.stringValue.isEmpty {
                        x += buttonMarginLeft
                    }
                    lk(button).sizeToFit().x(x).midY(midY + 1)
                }
            }
        } else {
            for (idx, rightLabel) in visibleRightLabels.enumerated() {
                let prevLeftLabel = idx > 0 ? visibleLeftLabels[idx - 1] : nil
                let leftLabel = visibleLeftLabels[idx]
                let y = prevLeftLabel.map { $0.frame.maxY + verSpace } ?? 0
                lk(leftLabel).sizeToFit().x(0).y(y)

                var rightLabelMaxX = frame.width
                if let button = buttons[idx] {
                    lk(button).sizeToFit().right(0).midY(leftLabel.frame.midY)
                    rightLabelMaxX = button.frame.minX - buttonMarginLeft
                }
                lk(rightLabel)
                    .x(leftLabel.frame.maxX + horSpace)
                    .toMaxX(rightLabelMaxX)
                    .appview_heightToFit()
                    .midY(leftLabel.frame.midY)
            }
        }
    }

    private func applyTexts() {
        let texts = texts ?? []
        dequeueLabels(&leftLabels, count: texts.count) { idx, label in
            label.stringValue = texts[idx].first ?? ""
        }
        dequeueLabels(&rightLabels, count: texts.count) { idx, label in
            label.stringValue = texts[idx].second ?? ""
        }
        assert(leftLabels.count == rightLabels.count)
        updateColors()
        updateAlignments()
        needsLayout = true
    }

    private func dequeueLabels(
        _ labels: inout [AVLabel],
        count: Int,
        configure: (Int, AVLabel) -> Void
    ) {
        while labels.count < count {
            let label = AVLabel()
            label.isSelectable = true
            label.font = font
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingMiddle
            addSubview(label)
            labels.append(label)
        }
        for (idx, label) in labels.enumerated() {
            if idx >= count {
                label.isHidden = true
            } else {
                label.isHidden = false
                configure(idx, label)
            }
        }
    }

    private func updateAlignments() {
        for label in leftLabels {
            label.alignment = type == .justified ? .left : .right
        }
        for label in rightLabels {
            label.alignment = type == .justified ? .right : .left
        }
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        var resultHeight: CGFloat = 0
        var leftMaxWidth: CGFloat = 0
        var rightMaxWidth: CGFloat = 0

        let visibleLeft = (leftLabels as NSArray).lk_visibleViews() as? [AVLabel] ?? []
        let visibleRight = (rightLabels as NSArray).lk_visibleViews() as? [AVLabel] ?? []

        for (idx, obj) in visibleLeft.enumerated() {
            let size = obj.bestSize
            leftMaxWidth = max(leftMaxWidth, size.width)
            resultHeight += size.height
            if idx > 0 { resultHeight += verSpace }
        }

        for (idx, obj) in visibleRight.enumerated() {
            var width = obj.bestWidth
            if let button = buttons[idx] {
                width += button.bestWidth
                if !obj.stringValue.isEmpty {
                    width += buttonMarginLeft
                }
            }
            rightMaxWidth = max(rightMaxWidth, width)
        }

        let resultWidth = leftMaxWidth + rightMaxWidth + horSpace + insets.left + insets.right
        return NSSize(width: resultWidth, height: resultHeight)
    }

    override func updateColors() {
        super.updateColors()
        let dark = isDarkMode()
        for label in leftLabels {
            label.textColor = (dark ? NSColorGray9 : NSColorGray1).withAlphaComponent(0.7)
        }
        for label in rightLabels {
            label.textColor = dark ? .white : .black
        }
    }
}
