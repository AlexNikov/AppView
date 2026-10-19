//
//  AVUITiming.swift
//  AppView
//

import Foundation

/// Named UI delays (replaces scattered magic `asyncAfter` constants).
enum AVUITiming {
    static let previewLayoutSettle: TimeInterval = 0.15
    static let brief: TimeInterval = 0.2
    static let dashboardLayoutSettle: TimeInterval = 0.3
    static let launchAppsReveal: TimeInterval = 0.5
    static let staticConsoleReveal: TimeInterval = 1
    static let asyncUpdateCoalesce: TimeInterval = 1
    static let aboutAutoClose: TimeInterval = 2
    static let launchPollInterval: TimeInterval = 2
}
