//
//  AVImageControl.swift
//  AppView
//

import AppKit

class AVImageControl: AVBaseControl {
    var imageView: NSImageView!
    var image: NSImage? {
        didSet {
            imageView.image = image
            needsLayout = true
        }
    }

    static func button(withImage image: NSImage?) -> AVImageControl {
        let button = AVImageControl()
        button.image = image
        return button
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView = NSImageView()
        imageView.wantsLayer = true
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
        imageView.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        imageView.layer?.frame = imageView.frame
    }

    override func sizeThatFits(_ size: NSSize) -> NSSize {
        imageView.image?.size ?? .zero
    }
}
