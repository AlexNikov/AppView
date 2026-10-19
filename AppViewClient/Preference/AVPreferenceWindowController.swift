//
//  AVPreferenceWindowController.swift
//  AppView
//

import AppKit

class AVPreferenceWindowController: AVWindowController {
    convenience init() {
        let window = AVWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 380),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: true
        )
        window.isMovableByWindowBackground = true
        window.title = NSLocalizedString("Preferences", comment: "")
        window.center()
        self.init(window: window)
        let vc = AVPreferenceViewController()
        window.contentView = vc.view
        contentViewController = vc
    }
}
