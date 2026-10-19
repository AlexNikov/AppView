//
//  AVPerformanceReporter.swift
//  AppViewClient
//
//  Created by 李凯 on 2022/5/3.
//

import AppCenter
import AppCenterAnalytics
import Foundation
import QuartzCore

class AVPerformanceReporter: NSObject {
    static let sharedInstance: AVPerformanceReporter = {
        AVPerformanceReporter()
    }()

    private var reloadStartTime: CFTimeInterval = 0
    private var hierarchyFetchedTime: CFTimeInterval = 0

    func willStartReload() {
        reloadStartTime = CACurrentMediaTime()
    }

    func didFetchHierarchy() {
        hierarchyFetchedTime = CACurrentMediaTime()
        let desc = resolveDurationDescription(CACurrentMediaTime() - reloadStartTime)
        Analytics.trackEvent("Perf(FetchHierarchy)", withProperties: ["time": desc])
    }

    func didComplete() {
        let desc = resolveDurationDescription(CACurrentMediaTime() - hierarchyFetchedTime)
        Analytics.trackEvent("Perf(UpdateDetails)", withProperties: ["time": desc])

        let desc2 = resolveDurationDescription(CACurrentMediaTime() - reloadStartTime)
        Analytics.trackEvent("Perf(Reload)", withProperties: ["time": desc2])
    }

    private func resolveDurationDescription(_ duration: CFTimeInterval) -> String {
        if duration < 0.1 { return "< 0.1s" }
        if duration < 0.5 { return "0.1s ~ 0.5s" }
        if duration < 1.0 { return "0.5s ~ 1.0s" }
        if duration < 3.0 { return "1s ~ 3s" }
        if duration < 6.0 { return "3s ~ 6s" }
        if duration < 10.0 { return "6s ~ 10s" }
        if duration < 20.0 { return "10s ~ 20s" }
        if duration < 30.0 { return "20s ~ 30s" }
        return "> 30s"
    }
}
