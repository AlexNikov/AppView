//
//  AVServerVersionRequestor.swift
//  AppViewClient
//

import Foundation

/// Previously fetched newest AppViewServer version from the upstream website.
/// Network check against that host was removed; callers treat `nil` as "unknown / skip".
class AVServerVersionRequestor: NSObject {
    static let shared: AVServerVersionRequestor = {
        let instance = AVServerVersionRequestor()
        return instance
    }()

    func preload() {}

    func query() -> String? {
        nil
    }
}
