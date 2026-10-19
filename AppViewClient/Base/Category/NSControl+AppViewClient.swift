//
//  NSControl+AppViewClient.swift
//  AppView
//

import AppKit

private let nsControlMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

extension NSControl {
    func heightForWidth(_ width: CGFloat) -> CGFloat {
        sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    var bestHeight: CGFloat {
        sizeThatFits(nsControlMaxSize).height
    }

    var bestWidth: CGFloat {
        sizeThatFits(nsControlMaxSize).width
    }

    var bestSize: NSSize {
        sizeThatFits(nsControlMaxSize)
    }
}
