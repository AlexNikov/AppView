//
//  AVBaseControl.swift
//  AppView
//

import AppKit

class AVBaseControl: NSControl {
    var clickAction: Selector?
    /// Swift-native click handler; runs before legacy `clickAction` / `sendAction`.
    var onClick: (() -> Void)?
    var adjustAlphaWhenClick = false
    var didChangeAppearance: ((AVBaseControl, Bool) -> Void)? {
        didSet { triggerDidChangeAppearanceBlock() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if adjustAlphaWhenClick {
            alphaValue = 0.8
        }
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        triggerClickAction()
        if adjustAlphaWhenClick {
            alphaValue = 1
        }
    }

    func addTarget(_ target: Any?, clickAction action: Selector) {
        self.target = target as AnyObject?
        clickAction = action
    }

    func triggerClickAction() {
        onClick?()
        if let clickAction, let target {
            sendAction(clickAction, to: target)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        triggerDidChangeAppearanceBlock()
    }

    private func triggerDidChangeAppearanceBlock() {
        if let didChangeAppearance {
            let isDarkMode = effectiveAppearance.lk_isDarkMode
            didChangeAppearance(self, isDarkMode)
        }
    }

    override func sizeToFit() {
        lk(self).size(bestSize)
    }

    func shouldTrackMouseEnteredAndExited() -> Bool {
        false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard shouldTrackMouseEnteredAndExited() else { return }
        for oldArea in trackingAreas {
            removeTrackingArea(oldArea)
        }
        let newArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newArea)
    }
}
