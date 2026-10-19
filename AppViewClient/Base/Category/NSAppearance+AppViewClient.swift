//
//  NSAppearance+AppViewClient.swift
//  AppView
//

import AppKit

extension NSAppearance {
    var lk_isDarkMode: Bool {
        if #available(macOS 10.14, *) {
            let darkNames: Set<NSAppearance.Name> = [
                .darkAqua,
                .vibrantDark,
                .accessibilityHighContrastDarkAqua,
                .accessibilityHighContrastVibrantDark,
            ]
            return darkNames.contains(name)
        }
        return false
    }
}
