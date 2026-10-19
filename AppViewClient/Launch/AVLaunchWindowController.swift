//
//  AVLaunchWindowController.swift
//  AppView
//

import AppKit

class AVLaunchWindowController: AVWindowController {
    private(set) var launchViewController: AVLaunchViewController!

    convenience init() {
        let window = AVWindow(
            contentRect: NSRect(x: 0, y: 0, width: 252, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()

        self.init(window: window)

        window.setAccessibilityIdentifier("appview.launch.window")

        launchViewController = AVLaunchViewController(window: window)
        window.contentView = launchViewController.view
        contentViewController = launchViewController
    }
}
