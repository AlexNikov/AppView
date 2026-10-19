//
//  AVPreferencePopupView.swift
//  AppView
//

import AppKit
import AppViewShared

class AVPreferencePopupView: AVBaseView {
    private var titleLabel: AVLabel!
    private var button: NSPopUpButton!
    private var messageLabel: AVLabel!
    private var messages: [String] = []

    var buttonX: CGFloat = 0 {
        didSet { needsLayout = true }
    }

    var isEnabled = true {
        didSet { button.isEnabled = isEnabled }
    }

    var selectedIndex: UInt = 0 {
        didSet {
            messageLabel.stringValue = messages.appview_hasIndex(Int(selectedIndex)) ? messages[Int(selectedIndex)] : ""
            button.selectItem(at: Int(selectedIndex))
            didChange?(selectedIndex)
        }
    }

    var didChange: ((UInt) -> Void)?

    convenience init(title: String, message: String, options: [String]) {
        self.init(
            title: title,
            messages: Array(repeating: message, count: options.count),
            options: options
        )
    }

    init(title: String, messages: [String], options: [String]) {
        super.init(frame: .zero)
        isEnabled = true
        self.messages = messages

        titleLabel = AVLabel()
        titleLabel.stringValue = title
        titleLabel.font = NSFontMake(IsEnglish ? 13 : 15)
        addSubview(titleLabel)

        button = NSPopUpButton()
        button.font = NSFontMake(IsEnglish ? 13 : 14)
        button.target = self
        button.action = #selector(handleButton)
        button.addItems(withTitles: options)
        button.isEnabled = isEnabled
        addSubview(button)

        messageLabel = AVLabel()
        messageLabel.font = NSFontMake(IsEnglish ? 12 : 13)
        messageLabel.textColor = .secondaryLabelColor
        addSubview(messageLabel)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        let buttonHeight = button.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).height
        lk(button).width(200).height(buttonHeight + 2).x(buttonX).y(0)
        lk(messageLabel).x(button.frame.origin.x).toRight(0).y(button.frame.maxY + 4).toBottom(0)
        lk(titleLabel).sizeToFit().maxX(buttonX - 3).y(0)
    }

    @objc private func handleButton() {
        selectedIndex = UInt(button.indexOfSelectedItem)
        didChange?(selectedIndex)
    }
}
