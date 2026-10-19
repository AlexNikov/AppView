//
//  AVWindowToolbarScaleView.swift
//  AppView
//

import AppKit

class AVWindowToolbarScaleView: AVBaseView {
    private(set) var slider: NSSlider!
    private(set) var decreaseButton: NSButton!
    private(set) var increaseButton: NSButton!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        slider = NSSlider()
        addSubview(slider)
        decreaseButton = NSButton.lk_button(with: NSImageMake("icon_decrease") ?? NSImage(), target: nil, action: nil)
        addSubview(decreaseButton)
        increaseButton = NSButton.lk_button(with: NSImageMake("icon_increase") ?? NSImage(), target: nil, action: nil)
        addSubview(increaseButton)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        lk(decreaseButton).width(20).fullHeight().x(0)
        lk(increaseButton).width(20).fullHeight().right(0)
        lk(slider).fullHeight().x(decreaseButton.frame.maxX).toMaxX(increaseButton.frame.origin.x)
    }
}
