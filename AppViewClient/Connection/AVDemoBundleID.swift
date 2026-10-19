//
//  AVDemoBundleID.swift
//  AppView
//
//  Known AppView iOS demo bundles for MCP auto-select and launch auto-enter.
//  Keep in sync with AppView/Scripts/appview_demo_bundle_ids.env (sourced by verify scripts).
//

import Foundation

enum AVDemoBundleID: String, CaseIterable {
    case mcpSample = "AppView.AppViewMCPSample"
    case customInfoSwift = "AppView.AppViewCustomInfoDemoSwift"
    case customInfoLegacy = "AppView.AppViewCustomInfoDemo"
    case collectionLayoutSwift = "AppView.AppViewCollectionLayoutDemo"
    case collectionLayoutObjC = "AppView.AppViewCollectionLayoutDemoObjC"

    static let preferredOrder: [AVDemoBundleID] = [
        .mcpSample, .customInfoSwift, .customInfoLegacy,
        .collectionLayoutSwift, .collectionLayoutObjC,
    ]

    static func matches(_ bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        return Self(rawValue: bundleId) != nil
    }

    /// First demo app in preferred order from discovered list.
    static func firstMatch(in apps: [AVInspectableApp]) -> AVInspectableApp? {
        for id in preferredOrder {
            if let app = apps.first(where: { $0.appInfo?.appBundleIdentifier == id.rawValue }) {
                return app
            }
        }
        return nil
    }
}
