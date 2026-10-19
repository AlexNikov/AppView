//
//  AVTextFieldView.swift
//  AppView
//

import AppKit
import RxSwift

class AVTextFieldView: AVBaseView {
    private(set) var textField: NSTextField!
    private var imageView: NSImageView?
    private(set) var closeButton: NSButton?

    var insets = NSEdgeInsetsZero {
        didSet { needsLayout = true }
    }

    var textColors: AVTwoColors? {
        didSet { updateColors() }
    }

    var image: NSImage? {
        didSet {
            if let image {
                if imageView == nil {
                    let iv = NSImageView()
                    imageView = iv
                    addSubview(iv)
                }
                imageView?.image = image
            } else {
                imageView?.removeFromSuperview()
                imageView = nil
            }
            needsLayout = true
        }
    }

    static func label() -> AVTextFieldView {
        let view = AVTextFieldView()
        view.textField.wantsLayer = true
        view.textField.backgroundColor = .clear
        view.textField.isBezeled = false
        view.textField.drawsBackground = true
        view.textField.isEditable = false
        view.textField.isSelectable = false
        return view
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textField = NSTextField()
        addSubview(textField)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        if let imageView {
            if textField.isEditable {
                lk(imageView).sizeToFit().x(insets.left).verAlign().offsetY(1)
                if let closeButton {
                    lk(closeButton).y(1).toBottom(0).width(100).right(insets.right)
                    lk(textField).x(imageView.frame.maxX + 5).toMaxX(closeButton.frame.origin.x - 5).heightToFit().verAlign()
                } else {
                    lk(textField).x(imageView.frame.maxX + 5).toRight(insets.right).heightToFit().verAlign()
                }
            } else {
                lk(imageView, textField).sizeToFit().verAlign()
                lk(textField).x(imageView.frame.maxX)
                lk(imageView, textField).groupHorAlign()
            }
        } else {
            lk(textField).x(insets.left).toRight(insets.right).heightToFit().verAlign().offsetY(insets.top - insets.bottom)
        }
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        var textFieldMaxWidth = limitedSize.width - insets.left - insets.right
        if imageView != nil {
            textFieldMaxWidth -= image?.size.width ?? 0
        }
        let textFieldSize = textField.sizeThatFits(NSSize(width: textFieldMaxWidth, height: .greatestFiniteMagnitude))
        let resultHeight = textFieldSize.height + insets.top + insets.bottom
        var resultWidth = textFieldSize.width + insets.left + insets.right
        if imageView != nil {
            resultWidth += image?.size.width ?? 0
        }
        return NSSize(width: resultWidth, height: resultHeight)
    }

    override func updateColors() {
        super.updateColors()
        if let textColors {
            textField.textColor = textColors.color
        }
    }

    private let disposeBag = DisposeBag()

    func initCloseButton() {
        guard closeButton == nil else { return }
        let button = NSButton()
        button.title = NSLocalizedString("CancelSearch", comment: "")
        button.bezelStyle = .regularSquare
        closeButton = button
        addSubview(button)
        needsLayout = true

        textField.lk_textOrEmpty.map { _ in () }
        .subscribe(onNext: { [weak self] _ in
            guard let self else { return }
            self.closeButton?.isHidden = self.textField.stringValue.isEmpty
        })
        .disposed(by: disposeBag)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if textField.isEditable {
            window?.makeFirstResponder(textField)
        }
    }
}
