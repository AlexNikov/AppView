//
//  AVVersionComparer.swift
//  AppViewClient
//

import Foundation
import AppViewShared

class AVVersionComparer: NSObject {
    static func compare(withNewest latest: String, user: String) -> Bool {
        compare(withExpectedVersion: latest, realVersion: user)
    }

    static func compare(withExpectedVersion expectedVersion: String, realVersion: String) -> Bool {
        let expectedNumber = expectedVersion.appview_numbericOSVersion()
        let realNumber = realVersion.appview_numbericOSVersion()
        if expectedNumber == 0 || realNumber == 0 {
            assertionFailure()
            return false
        }
        return realNumber >= expectedNumber
    }
}
