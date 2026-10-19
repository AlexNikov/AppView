//
//  AVLogRowView.swift
//  AppView
//

import AppKit
import AppViewShared

class AVLogRowView: AVTableRowView {
    private var levelDotLayer: CALayer!
    private var timestampLabel: AVLabel!

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        levelDotLayer = CALayer()
        levelDotLayer.appview_removeImplicitAnimations()
        levelDotLayer.cornerRadius = 4
        layer?.addSublayer(levelDotLayer)

        titleLabel.font = NSFontMake(12)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isSelectable = true

        subtitleLabel.font = NSFontMake(11)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.isSelectable = true

        timestampLabel = AVLabel()
        timestampLabel.font = NSFontMake(11)
        timestampLabel.alignment = .right
        addSubview(timestampLabel)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func configure(with entry: AVLogEntry) {
        titleLabel.stringValue = entry.title
        if let detail = entry.detail, !detail.isEmpty {
            subtitleLabel.stringValue = detail
            subtitleLabel.isHidden = false
        } else {
            subtitleLabel.stringValue = ""
            subtitleLabel.isHidden = true
        }
        timestampLabel.stringValue = AVLogRowView.dateFormatter.string(from: entry.timestamp)

        switch entry.level {
        case .error:
            levelDotLayer.backgroundColor = AppViewColorRGBAMake(208, 2, 27, 1).cgColor
            titleLabel.textColor = isDarkMode
                ? AppViewColorMake(255, 100, 100)
                : AppViewColorMake(180, 0, 20)
        case .info:
            levelDotLayer.backgroundColor = AppViewColorRGBAMake(120, 120, 120, 0.7).cgColor
            titleLabel.textColor = .labelColor
        }

        subtitleLabel.textColor = .secondaryLabelColor
        timestampLabel.textColor = .tertiaryLabelColor
        needsLayout = true
    }

    override func layout() {
        super.layout()

        let dotSize: CGFloat = 8
        let leftInset: CGFloat = ConsoleInsetLeft
        let rightInset: CGFloat = ConsoleInsetRight

        lk(timestampLabel).sizeToFit().right(rightInset).verAlign()

        let dotX = leftInset
        let dotY = (bounds.height - dotSize) / 2
        levelDotLayer.frame = CGRect(x: dotX, y: dotY, width: dotSize, height: dotSize)

        let contentLeft = leftInset + dotSize + 6
        let contentRight = timestampLabel.frame.minX - 4

        if subtitleLabel.isHidden {
            lk(titleLabel).x(contentLeft).width(contentRight - contentLeft).heightToFit().verAlign()
        } else {
            let rowMid = bounds.height / 2
            lk(titleLabel).x(contentLeft).width(contentRight - contentLeft).heightToFit()
            titleLabel.frame.origin.y = rowMid - titleLabel.frame.height - 1
            lk(subtitleLabel).x(contentLeft).width(contentRight - contentLeft).heightToFit()
            subtitleLabel.frame.origin.y = rowMid + 1
        }
    }

    static func rowHeight(for entry: AVLogEntry) -> CGFloat {
        entry.detail != nil ? 36 : 20
    }
}
