//
//  NSButton+AppViewClient.swift
//  AppView
//

import AppKit

extension NSButton {
    static func lk_normalButton(
        withTitle title: String,
        target: Any?,
        action: Selector?
    ) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .rounded
        button.title = title
        button.font = NSFont.systemFont(ofSize: 13)
        button.target = target as AnyObject?
        button.action = action
        button.frame = NSRect(x: 0, y: 0, width: 84, height: 40)
        return button
    }

    static func lk_button(
        with image: NSImage,
        target: Any?,
        action: Selector?
    ) -> NSButton {
        let button = NSButton()
        button.image = image
        button.bezelStyle = .roundRect
        button.isBordered = false
        button.target = target as AnyObject?
        button.action = action
        return button
    }
}
