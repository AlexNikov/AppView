//
//  AppViewMsgAttribute.swift
//  AppView
//

import Foundation
import RxSwift

/// Legacy payload type kept for `AppViewAnyDoubleValue` compatibility during migration.
struct AppViewMsgActionParams {
    var value: Any?
    var userInfo: Any?
    weak var relatedObject: AnyObject?

    var doubleValue: Double {
        guard let number = value as? NSNumber else {
            assertionFailure()
            return 0
        }
        return number.doubleValue
    }

    var integerValue: Int {
        guard let number = value as? NSNumber else {
            assertionFailure()
            return 0
        }
        return number.intValue
    }

    var boolValue: Bool {
        guard let number = value as? NSNumber else {
            assertionFailure()
            return false
        }
        return number.boolValue
    }
}
