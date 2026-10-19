//
//  AVLayout+UIToolkit.swift
//  AppView
//

import AppKit
import Foundation
import QuartzCore

extension AVLayoutProxy {
    @discardableResult
    func visibles() -> AVLayoutProxy {
        var proxy = self
        guard let get = proxy._get else { return proxy }

        if lkEqualClass(get, NSView.self) {
            if !isVisibleView(get as! NSView) {
                proxy.storage = .object(NSNull())
            }
        } else if lkEqualClass(get, CALayer.self) {
            if !isVisibleLayer(get as! CALayer) {
                proxy.storage = .object(NSNull())
            }
        } else if let array = get as? [Any] {
            let visibleOnes = array.filter { isVisibleViewOrLayer($0) }
            if visibleOnes.count > 1 {
                proxy.storage = .group(visibleOnes)
            } else if let first = visibleOnes.first {
                proxy.storage = .object(first)
            } else {
                proxy.storage = .object(NSNull())
            }
        }
        return proxy
    }

    private func isVisibleView(_ view: NSView) -> Bool {
        view.superview != nil && !view.isHidden && view.alphaValue >= 0.01
    }

    private func isVisibleLayer(_ layer: CALayer) -> Bool {
        layer.superlayer != nil && !layer.isHidden && layer.opacity >= 0.01
    }

    private func isVisibleViewOrLayer(_ object: Any) -> Bool {
        if let view = object as? NSView {
            return isVisibleView(view)
        }
        if let layer = object as? CALayer {
            return isVisibleLayer(layer)
        }
        return false
    }
}
