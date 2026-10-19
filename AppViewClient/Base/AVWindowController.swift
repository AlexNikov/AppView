//
//  AVWindowController.swift
//  AppView
//

import AppKit

class AVWindowController: NSWindowController, AVAppMenuManagerDelegate {
    override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        NSLog("%@ dealloc", String(describing: type(of: self)))
    }

    // Menu actions live on the class so subclasses can `override` (vtable).
    // Protocol-extension defaults are statically dispatched when called through
    // `AVWindowController` — Export / Open in New Window would silently no-op.
    // Overrides must be in the subclass *body* (not an extension) unless `@objc dynamic`.
    func appMenuManagerDidSelectReload() {}
    func appMenuManagerDidSelectDimension() {}
    func appMenuManagerDidSelectZoomIn() {}
    func appMenuManagerDidSelectZoomOut() {}
    func appMenuManagerDidSelectDecreaseInterspace() {}
    func appMenuManagerDidSelectIncreaseInterspace() {}
    func appMenuManagerDidSelectExpansionIndex(_ index: UInt) {}
    func appMenuManagerDidSelectFilter() {}
    func appMenuManagerDidSelectExport() {}
    func appMenuManagerDidSelectOpenInNewWindow() {}
}
