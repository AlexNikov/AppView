//
//  AVTwoColors.swift
//  AppView
//

import AppKit

class AVTwoColors: NSObject {
    static func colors(withColorInLightMode colorInLightMode: NSColor, colorInDarkMode: NSColor) -> AVTwoColors {
        let colors = AVTwoColors()
        colors.colorInLightMode = colorInLightMode
        colors.colorInDarkMode = colorInDarkMode
        return colors
    }

    var colorInLightMode: NSColor?
    var colorInDarkMode: NSColor?

    var color: NSColor? {
        return AppViewClientIsDarkMode() ? colorInDarkMode : colorInLightMode
    }
}
