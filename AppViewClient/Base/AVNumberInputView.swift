//
//  AVNumberInputView.swift
//  AppView
//

import AppKit
import AppViewShared

let AVNumberInputHorizontalHeight: CGFloat = 21
let AVNumberInputVerticalHeight: CGFloat = 38

class AVNumberInputView: AVBaseView {
    var inputTitle: String? {
        didSet {
            titleLabel.stringValue = inputTitle ?? ""
            updateTitleLabelFontAndColor()
            needsLayout = true
        }
    }

    var viewStyle: AVNumberInputViewStyle = .horizontal {
        didSet {
            if viewStyle == .horizontal {
                textFieldView.textField.alignment = .left
                textFieldView.insets = NSEdgeInsets(top: 3, left: 3, bottom: 3, right: 3)
            } else {
                textFieldView.textField.alignment = .center
                textFieldView.insets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
            }
            updateTitleLabelFontAndColor()
            needsLayout = true
        }
    }

    private(set) var textFieldView: AVTextFieldView!
    private var titleLabel: AVLabel!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textFieldView = AVTextFieldView()
        textFieldView.backgroundColorName = "DashboardCardValueBGColor"
        textFieldView.layer?.cornerRadius = DashboardCardControlCornerRadius
        let cell = NSTextFieldCell()
        textFieldView.textField.cell = cell
        cell.focusRingType = .none
        cell.usesSingleLineMode = true
        cell.lineBreakMode = .byTruncatingTail
        cell.isScrollable = true
        cell.isEditable = true
        cell.isSelectable = true
        textFieldView.textField.drawsBackground = false
        textFieldView.textField.textColor = NSColor(named: "DashboardCardValueColor")
        textFieldView.textField.font = NSFontMake(12)
        addSubview(textFieldView)

        titleLabel = AVLabel()
        titleLabel.alignment = .center
        addSubview(titleLabel)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        lk(textFieldView).fullWidth().height(AVNumberInputHorizontalHeight)
        if viewStyle == .horizontal {
            lk(titleLabel).sizeToFit().lk_minWidth(15).verAlign().right(2)
            var insets = textFieldView.insets
            insets.right = bounds.width - titleLabel.frame.origin.x + 2
            textFieldView.insets = insets
        } else if viewStyle == .vertical {
            lk(titleLabel).sizeToFit().horAlign().y(textFieldView.frame.maxY + 3)
        } else {
            assertionFailure()
        }
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        var size = limitedSize
        if viewStyle == .horizontal {
            size.height = AVNumberInputHorizontalHeight
        } else if viewStyle == .vertical {
            size.height = AVNumberInputVerticalHeight
        } else {
            assertionFailure()
        }
        return size
    }

    static func parsedValue(with string: String, attrType: AppViewAttrType) -> Any? {
        switch attrType {
        case .int, .long, .longLong:
            let scanner = Scanner(string: string)
            var value: Int64 = 0
            return scanner.scanInt64(&value) ? NSNumber(value: value) : nil
        case .float, .double:
            return Double(string).map { NSNumber(value: $0) }
        default:
            assertionFailure("不支持该 AttrType")
            return nil
        }
    }

    private func updateTitleLabelFontAndColor() {
        if viewStyle == .horizontal {
            if (inputTitle?.count ?? 0) > 1 {
                titleLabel.textColor = NSColor(named: "DashboardCardValueColor")
                titleLabel.font = NSFontMake(12)
            } else {
                titleLabel.textColor = NSColor(named: "DashboardInputAccessoryColor")
                titleLabel.font = NSFontMake(10)
            }
        } else {
            titleLabel.font = NSFontMake(11)
            titleLabel.textColor = NSColor(named: "DashboardCardValueColor")
        }
        needsLayout = true
    }
}
