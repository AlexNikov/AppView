//
//  AVMCPConstants.swift
//  AppView
//
//  Typed MCP wire strings (uiMode, channel) — JSON contract uses rawValue.
//

import Foundation

enum AVMCPUIMode: String, Codable {
    case inspector
    case launch
    case unknown
}

enum AVMCPChannelTag: String, Codable {
    case usb
    case sim
    case unknown

    init(usb: Bool) {
        self = usb ? .usb : .sim
    }

    init(rawChannel: String?) {
        guard let raw = rawChannel?.lowercased() else {
            self = .unknown
            return
        }
        self = AVMCPChannelTag(rawValue: raw) ?? .unknown
    }
}

enum AVMCPInspectError: String {
    case noMatchingTarget = "no_matching_target"
    case selectTimeout = "select_timeout"
}

extension AVNavigationManager {
    var mcpUIMode: AVMCPUIMode {
        if staticWindowController?.window?.isVisible == true { return .inspector }
        if launchWindowController?.window?.isVisible == true { return .launch }
        return .unknown
    }
}

extension AVAppsManager {
    static func mcpChannelTag(for app: AVInspectableApp?) -> AVMCPChannelTag {
        guard let app else { return .unknown }
        return AVMCPChannelTag(usb: inspectSessionUsesUSB(app))
    }
}
