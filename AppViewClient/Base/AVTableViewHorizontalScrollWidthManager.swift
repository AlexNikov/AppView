//
//  AVTableViewHorizontalScrollWidthManager.swift
//  AppViewClient
//

import Foundation

class AVTableViewHorizontalScrollWidthManager: NSObject {
    var maxRowWidth: CGFloat = 0
    var didReachNewMaxWidth: (() -> Void)?

    func rowDidLayout(withWidth width: CGFloat) {
        if width > maxRowWidth {
            maxRowWidth = width
            didReachNewMaxWidth?()
        }
    }
}
