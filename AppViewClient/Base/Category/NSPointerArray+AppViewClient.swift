//
//  NSPointerArray+AppViewClient.swift
//  AppView
//

import Foundation

extension NSPointerArray {
    func lk_indexOfPointer(_ pointer: UnsafeRawPointer?) -> UInt {
        guard let pointer else { return UInt(NSNotFound) }
        let array = copy() as! NSPointerArray
        for i in 0..<array.count {
            if let p = array.pointer(at: i), p == pointer {
                return UInt(i)
            }
        }
        return UInt(NSNotFound)
    }

    func lk_containsPointer(_ pointer: UnsafeRawPointer?) -> Bool {
        guard pointer != nil else { return false }
        return lk_indexOfPointer(pointer) != UInt(NSNotFound)
    }
}
