//
//  AVHierarchyItem.swift
//  AppView
//

import Foundation

enum AVHierarchyItemStatus: UInt {
    case notExpandable
    case expanded
    case collapsed
}

class AVHierarchyItem: NSObject {
    var subItems: [AVHierarchyItem]?

    private(set) weak var superItem: AVHierarchyItem?

    var status: AVHierarchyItemStatus = .notExpandable

    private(set) var indentation: UInt = 0

    func flatItems() -> [AVHierarchyItem] {
        var array: [AVHierarchyItem] = [self]

        if status == .expanded {
            subItems?.forEach { obj in
                obj.indentation = indentation + 1
                array.append(contentsOf: obj.flatItems())
            }
        }

        return array
    }

    class func flatItems(fromRootItems items: [AVHierarchyItem]) -> [AVHierarchyItem] {
        items.flatMap { $0.flatItems() }
    }
}
