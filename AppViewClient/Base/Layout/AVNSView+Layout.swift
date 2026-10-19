//
//  AVNSView+Layout.swift
//  AppView
//

import AppKit

extension NSView {
    func lk_applyFrame(_ rect: CGRect) {
        frame = rect
    }

    var lk_layoutFrame: CGRect {
        get { frame }
        set { frame = newValue }
    }

    func lk_clampMaxWidth(_ maxWidth: CGFloat) {
        var rect = frame
        if rect.size.width > maxWidth {
            rect.size.width = maxWidth
            lk_layoutFrame = rect
        }
    }
}

extension NSControl {
    func lk_updateWidthToFit() {
        let height = bounds.height
        let width = sizeThatFits(NSSize(width: CGFloat.greatestFiniteMagnitude, height: height)).width
        var rect = frame
        rect.size.width = width
        lk_layoutFrame = rect
    }
}

extension AVBaseView {
    func lk_updateHeightToFit() {
        let limitedWidth = bounds.width
        let height = sizeThatFits(NSSize(width: limitedWidth, height: .greatestFiniteMagnitude)).height
        var rect = frame
        rect.size.height = height
        lk_layoutFrame = rect
    }

    func lk_updateSizeToFit() {
        let size = sizeThatFits(NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        var rect = frame
        rect.size = size
        lk_layoutFrame = rect
    }
}
