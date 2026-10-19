//
//  AVLayerLayout.swift
//  AppView
//

import AppKit
import QuartzCore

enum AVLayerLayout {
    private static func snapToPixel(_ rawValue: CGFloat) -> CGFloat {
        if rawValue == -CGFloat.greatestFiniteMagnitude || rawValue == CGFloat.greatestFiniteMagnitude {
            return rawValue
        }
        let screenScale = NSScreen.main?.backingScaleFactor ?? 2.0
        return ceil(rawValue * screenScale) / screenScale
    }

    static func setFrame(_ layer: CALayer, origin: CGPoint, size: CGSize) {
        var rect = CGRect(origin: origin, size: size)
        rect.origin.x = snapToPixel(rect.origin.x)
        rect.origin.y = snapToPixel(rect.origin.y)
        rect.size.width = snapToPixel(rect.size.width)
        rect.size.height = snapToPixel(rect.size.height)
        layer.frame = rect
    }

    static func fullFrame(_ layer: CALayer, in superBounds: CGRect) {
        setFrame(layer, origin: .zero, size: superBounds.size)
    }

    static func pin(
        _ layer: CALayer,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) {
        setFrame(layer, origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }

    static func separator(
        _ layer: CALayer,
        x: CGFloat,
        width: CGFloat,
        y: CGFloat,
        in superWidth: CGFloat? = nil
    ) {
        let w = width > 0 ? width : (superWidth.map { $0 - x } ?? width)
        pin(layer, x: x, y: y, width: w, height: 1)
    }

    static func verAlign(_ layer: CALayer, in superBounds: CGRect, width: CGFloat, height: CGFloat) {
        let y = (superBounds.height - height) / 2
        pin(layer, x: layer.frame.origin.x, y: y, width: width, height: height)
    }

    static func horAlign(_ layer: CALayer, in superBounds: CGRect, width: CGFloat, height: CGFloat) {
        let x = (superBounds.width - width) / 2
        pin(layer, x: x, y: layer.frame.origin.y, width: width, height: height)
    }

    static func fullWidth(_ layer: CALayer, in superBounds: CGRect, height: CGFloat, y: CGFloat = 0) {
        pin(layer, x: 0, y: y, width: superBounds.width, height: height)
    }

    static func fullHeight(_ layer: CALayer, in superBounds: CGRect, width: CGFloat, x: CGFloat = 0) {
        pin(layer, x: x, y: 0, width: width, height: superBounds.height)
    }

    static func toRight(_ layer: CALayer, inset: CGFloat, in superBounds: CGRect) {
        var rect = layer.frame
        let width = snapToPixel(superBounds.width - rect.minX - inset)
        rect.size.width = max(0, width)
        layer.frame = rect
    }

    static func toMaxX(_ layer: CALayer, maxX: CGFloat) {
        var rect = layer.frame
        var clamped = maxX
        if clamped < rect.minX { clamped = rect.minX }
        rect.size.width = snapToPixel(clamped - rect.minX)
        layer.frame = rect
    }

    static func progressFill(_ layer: CALayer, progress: CGFloat, in bounds: CGRect) {
        pin(layer, x: 0, y: 0, width: bounds.width * progress, height: bounds.height)
    }
}
