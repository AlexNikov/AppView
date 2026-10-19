//
//  AVAttrString+Conversion.swift
//  AppView
//

import AppKit
import Foundation

struct AppViewRGBPair {
    let light: String
    let dark: String

    func resolvedColor() -> NSColor? {
        AVAttrStringConversion.color(fromRGBPair: self)
    }
}

enum AVAttrStringConversion {
    static func attributedString(from text: String) -> NSMutableAttributedString {
        NSMutableAttributedString(string: text)
    }

    static func color(fromRGBPair pair: AppViewRGBPair) -> NSColor? {
        let rgb = AppViewClientIsDarkMode() ? pair.dark : pair.light
        return color(fromRGB: rgb)
    }

    static func color(fromRGB rgb: String) -> NSColor? {
        color(from: rgb as Any?)
    }

    static func color(from obj: Any?) -> NSColor? {
        guard let obj else { return nil }
        if let color = obj as? NSColor { return color }
        if let string = obj as? String {
            if let color = colorStringDictionary()[string] { return color }
            if let array = numberArray(from: string), array.count == 3 || array.count == 4 {
                let alpha = array.count == 4 ? array[3].floatValue : 1
                return NSColor(
                    red: CGFloat(array[0].floatValue / 255.0),
                    green: CGFloat(array[1].floatValue / 255.0),
                    blue: CGFloat(array[2].floatValue / 255.0),
                    alpha: CGFloat(alpha)
                )
            }
            if let finalColor = color(fromHexString: string) { return finalColor }
        }
        return nil
    }

    static func font(size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size)
    }

    static func font(from obj: Any?) -> NSFont? {
        guard let obj else { return nil }
        if let font = obj as? NSFont { return font }
        if let number = obj as? NSNumber { return NSFont.systemFont(ofSize: number.doubleValue) }
        if let string = obj as? String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if let number = formatter.number(from: string) {
                return NSFont.systemFont(ofSize: number.doubleValue)
            }
        }
        return nil
    }

    static func image(named name: String) -> NSImage? {
        NSImage(named: name)
    }

    static func paragraphStyle(for string: NSAttributedString) -> NSMutableParagraphStyle {
        var effectiveRange = NSRange(location: 0, length: 0)
        let fullRange = NSRange(location: 0, length: string.length)
        if let existing = string.attribute(.paragraphStyle, at: 0, longestEffectiveRange: &effectiveRange, in: fullRange) as? NSParagraphStyle,
           effectiveRange.length == string.length {
            return existing.mutableCopy() as! NSMutableParagraphStyle
        }
        return NSMutableParagraphStyle()
    }

    private static func colorStringDictionary() -> [String: NSColor] {
        [
            "clear": .clear,
            "white": .white,
            "black": .black,
            "gray": NSColor(red: 179 / 255.0, green: 179 / 255.0, blue: 179 / 255.0, alpha: 1),
            "red": NSColor(red: 250 / 255.0, green: 58 / 255.0, blue: 58 / 255.0, alpha: 1),
            "green": NSColor(red: 159 / 255.0, green: 214 / 255.0, blue: 97 / 255.0, alpha: 1),
            "blue": NSColor(red: 49 / 255.0, green: 189 / 255.0, blue: 243 / 255.0, alpha: 1),
            "yellow": NSColor(red: 255 / 255.0, green: 207 / 255.0, blue: 71 / 255.0, alpha: 1),
        ]
    }

    private static func color(fromHexString hexString: String) -> NSColor? {
        func component(_ string: String, start: Int, length: Int) -> CGFloat {
            let startIndex = string.index(string.startIndex, offsetBy: start)
            let endIndex = string.index(startIndex, offsetBy: length)
            let substring = String(string[startIndex..<endIndex])
            let fullHex = length == 2 ? substring : substring + substring
            var hexComponent: UInt64 = 0
            Scanner(string: fullHex).scanHexInt64(&hexComponent)
            return CGFloat(hexComponent) / 255.0
        }

        let colorString = hexString.replacingOccurrences(of: "#", with: "").uppercased()
        let alpha: CGFloat
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        switch colorString.count {
        case 3:
            alpha = 1.0
            red = component(colorString, start: 0, length: 1)
            green = component(colorString, start: 1, length: 1)
            blue = component(colorString, start: 2, length: 1)
        case 4:
            alpha = component(colorString, start: 0, length: 1)
            red = component(colorString, start: 1, length: 1)
            green = component(colorString, start: 2, length: 1)
            blue = component(colorString, start: 3, length: 1)
        case 6:
            alpha = 1.0
            red = component(colorString, start: 0, length: 2)
            green = component(colorString, start: 2, length: 2)
            blue = component(colorString, start: 4, length: 2)
        case 8:
            alpha = component(colorString, start: 0, length: 2)
            red = component(colorString, start: 2, length: 2)
            green = component(colorString, start: 4, length: 2)
            blue = component(colorString, start: 6, length: 2)
        default:
            return nil
        }
        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static func numberArray(from string: String) -> [NSNumber]? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        var numbers: [NSNumber] = []
        for component in trimmed.components(separatedBy: ",") {
            if let number = formatter.number(from: component) {
                numbers.append(number)
            }
        }
        return numbers.isEmpty ? nil : numbers
    }
}
