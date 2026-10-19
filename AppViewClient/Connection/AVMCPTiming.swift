//
//  AVMCPTiming.swift
//  AppView
//
//  Named delays for blocking MCP automation (values unchanged from legacy).
//

import Foundation

enum AVMCPTiming {
    /// Max wait for DispatchQueue.main.async hop from background MCP thread.
    static let mainQueueHop: TimeInterval = 5

    /// Busy-wait interval while Rx Single (connect/discover) completes.
    static let inFlightPollInterval: TimeInterval = 0.05

    /// Poll launch tiles after mcpReloadWithoutAutoEnter.
    static let launchTilePollInterval: TimeInterval = 0.25

    /// App-switcher popover: wait for sim + USB tiles after channel switch.
    static let appSwitcherTilePollInterval: TimeInterval = 0.3

    /// Extra slack beyond caller timeout (hierarchy fetch after connect).
    static let connectCompletionSlack: TimeInterval = 15

    /// Default MCP operation timeout when handler does not pass one.
    static let defaultOperationTimeout: TimeInterval = 45

    /// Minimum discover sync timeout (AVMCPClientDiagnostics).
    static let minimumDiscoverTimeout: TimeInterval = 25
}
