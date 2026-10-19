//
//  AVOutlineItem.swift
//  AppView
//

import AppKit
import Foundation

enum AVOutlineItemStatus: UInt {
    case notExpandable
    case expanded
    case collapsed
}

class AVOutlineItem: NSObject {
    var subItems: [AVOutlineItem]? {
        didSet {
            if subItems != nil {
                status = .collapsed
            } else {
                status = .notExpandable
            }
        }
    }

    var status: AVOutlineItemStatus = .notExpandable
    var titleText: String?
    var image: NSImage?
    private(set) var indentation: UInt = 0

    func flatItems() -> [AVOutlineItem] {
        var array: [AVOutlineItem] = [self]
        if status == .expanded {
            for obj in subItems ?? [] {
                obj.indentation = indentation + 1
                array.append(contentsOf: obj.flatItems())
            }
        }
        return array
    }

    class func flatItems(fromRootItems items: [AVOutlineItem]) -> [AVOutlineItem] {
        items.flatMap { $0.flatItems() }
    }
}
