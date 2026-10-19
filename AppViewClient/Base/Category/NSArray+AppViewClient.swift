//
//  NSArray+AppViewClient.swift
//  AppView
//

import AppKit

extension NSArray {
    func lk_visibleViews() -> [Any] {
        appview_filter { obj in
            if let view = obj as? NSView {
                return !view.isHidden
            }
            assertionFailure()
            return false
        } as? [Any] ?? []
    }
}
