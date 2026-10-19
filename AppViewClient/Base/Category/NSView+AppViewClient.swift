//
//  NSView+AppViewClient.swift
//  AppView
//

import AppKit

extension NSView {
    @objc var isVisible: Bool {
        !isHidden && alphaValue > 0
    }

    var backgroundColorName: String? {
        get {
            appview_getBindObject(forKey: "lk_backgroundColorName") as? String
        }
        set {
            appview_bindObject(newValue, forKey: "lk_backgroundColorName")
            if let name = newValue {
                layer?.backgroundColor = NSColor(named: name)?.cgColor
            } else {
                layer?.backgroundColor = nil
            }
        }
    }

    func showDebugBorder() {
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.cgColor
    }

    func lk_insertSubviewAtBottom(_ view: NSView) {
        if let firstSubview = subviews.first {
            addSubview(view, positioned: .below, relativeTo: firstSubview)
        } else {
            addSubview(view)
        }
    }
}
