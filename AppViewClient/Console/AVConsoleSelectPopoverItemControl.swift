//
//  AVConsoleSelectPopoverItemControl.swift
//  AppView
//

import AppKit
import AppViewShared

final class AVConsoleSelectPopoverItemControl: AVBaseControl {
    private var imageView: NSImageView!
    private var titleLabel: AVLabel!
    private var subtitleLabel: AVLabel!
    private var subtitleMarginTop: CGFloat = 0

    var isChecked = false {
        didSet { imageView.isHidden = !isChecked }
    }

    var title: String? {
        didSet {
            titleLabel.stringValue = title ?? ""
            needsLayout = true
        }
    }

    var subtitle: String? {
        didSet {
            subtitleLabel.stringValue = subtitle ?? ""
            subtitleLabel.isHidden = subtitle?.isEmpty != false
            needsLayout = true
        }
    }

    var representedObject: AppViewObject? {
        didSet {
            titleLabel.textColor = representedObject != nil ? .labelColor : .secondaryLabelColor
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView = NSImageView()
        imageView.image = NSImageMake("Console_Checked")
        addSubview(imageView)

        titleLabel = AVLabel()
        titleLabel.font = NSFontMake(12)
        titleLabel.maximumNumberOfLines = 1
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(titleLabel)

        subtitleLabel = AVLabel()
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.font = NSFontMake(11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.isHidden = true
        addSubview(subtitleLabel)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        lk(imageView).sizeToFit().x(3).verAlign()
        lk(titleLabel).x(imageView.frame.maxX + 4).toRight(0).heightToFit()
        if !subtitleLabel.isHidden {
            lk(subtitleLabel).x(titleLabel.frame.origin.x).toRight(0).heightToFit().y(titleLabel.frame.maxY + subtitleMarginTop)
        }
        lk(titleLabel, subtitleLabel).visibles().groupVerAlign()
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        var size = limitedSize
        let imageHeight = imageView.image?.size.height ?? 0
        var textHeight = titleLabel.sizeThatFits(NSSizeMax).height
        if !subtitleLabel.isHidden {
            textHeight += subtitleLabel.sizeThatFits(NSSizeMax).height + subtitleMarginTop
        }
        size.height = max(imageHeight, textHeight)
        return size
    }

    override func sizeToFit() {
        lk(self).size(sizeThatFits(NSSizeMax))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let text = title, !text.isEmpty else {
            super.rightMouseDown(with: event)
            return
        }
        let menu = NSMenu()
        let item = NSMenuItem(title: NSLocalizedString("Copy", comment: ""), action: #selector(handleCopy(_:)), keyEquivalent: "")
        item.representedObject = text
        item.target = self
        menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func handleCopy(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
