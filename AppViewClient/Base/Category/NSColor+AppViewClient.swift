//
//  NSColor+AppViewClient.swift
//  AppView
//

import AppKit

extension NSColor {
    func lk_rgbaComponents() -> [NSNumber] {
        let rgbColor = usingColorSpace(.sRGB)!
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [NSNumber(value: Double(r)), NSNumber(value: Double(g)), NSNumber(value: Double(b)), NSNumber(value: Double(a))]
    }

    static func lk_colorFromRGBAComponents(_ components: [NSNumber]?) -> NSColor? {
        guard let components else { return nil }
        guard components.count == 4 else {
            assertionFailure()
            return nil
        }
        return NSColor(
            red: components[0].doubleValue,
            green: components[1].doubleValue,
            blue: components[2].doubleValue,
            alpha: components[3].doubleValue
        )
    }

    var rgbaString: String {
        let rgbColor = usingColorSpace(.sRGB)!
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        if a >= 1 {
            return String(format: "(%.0f, %.0f, %.0f)", r * 255, g * 255, b * 255)
        }
        return String(format: "(%.0f, %.0f, %.0f, %.2f)", r * 255, g * 255, b * 255, a)
    }

    var hexString: String {
        let rgbColor = usingColorSpace(.sRGB)!
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        let red = Int(r * 255)
        let green = Int(g * 255)
        let blue = Int(b * 255)
        let alpha = Int(a * 255)

        let rString = NSColor.alignColorHexStringLength(NSColor.hexString(withInteger: red))
        let gString = NSColor.alignColorHexStringLength(NSColor.hexString(withInteger: green))
        let bString = NSColor.alignColorHexStringLength(NSColor.hexString(withInteger: blue))
        let aString = NSColor.alignColorHexStringLength(NSColor.hexString(withInteger: alpha))

        if a >= 1 {
            return "#\(rString)\(gString)\(bString)".lowercased()
        }
        return "#\(rString)\(gString)\(bString)\(aString)".lowercased()
    }

    private static func alignColorHexStringLength(_ hexString: String) -> String {
        hexString.count < 2 ? "0" + hexString : hexString
    }

    private static func hexString(withInteger integer: Int) -> String {
        var hexString = ""
        var value = integer
        for _ in 0..<9 {
            let remainder = value % 16
            value /= 16
            let letter = hexLetterString(withInteger: remainder)
            hexString = letter + hexString
            if value == 0 { break }
        }
        return hexString
    }

    private static func hexLetterString(withInteger integer: Int) -> String {
        assert(integer < 16, "要转换的数必须是16进制里的个位数，也即小于16，但你传给我是 \(integer)")
        switch integer {
        case 10: return "A"
        case 11: return "B"
        case 12: return "C"
        case 13: return "D"
        case 14: return "E"
        case 15: return "F"
        default: return "\(integer)"
        }
    }
}
