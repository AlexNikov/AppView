//
//  AppViewCustomDisplayItemInfo+AppViewClient.swift
//  AppViewClient
//

import AppKit
import Foundation
import AppViewShared

extension AppViewCustomDisplayItemInfo {
    func hasValidFrame() -> Bool {
        guard let frameInWindow else { return false }
        return AVHelper.validateFrame(frameInWindow)
    }
}
