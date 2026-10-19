//
//  AVWindow.swift
//  AppView
//

import AppKit

class AVWindow: NSWindow, NSDraggingDestination {
    static func panelWindow(withWidth width: CGFloat, height: CGFloat, contentView: AVPanelContentView) -> AVWindow {
        let window = AVWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: .titled,
                              backing: .buffered,
                              defer: true)
        window.contentView = contentView
        return window
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        registerForDraggedTypes([.fileURL])
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let path = NSURL(from: sender.draggingPasteboard)?.path else { return false }
        var error: NSError?
        let isSucc = AVNavigationManager.sharedInstance.showReader(withFilePath: path, error: &error)
        if !isSucc, let error {
            AlertError(error, self)
        }
        return isSucc
    }
}
