//
//  AppDelegate+AppViewMacMCP.swift
//  AppView
//
//  MCP HTTP server (:47192) data source for verify scripts and automation.
//

import AppKit
import AppViewMacMCP
import AppViewShared

// MARK: - MCP (AppViewMacMCPDataSource)

extension AppDelegate: AppViewMacMCPDataSource {
    func mcpCurrentHierarchyInfo() -> NSObject? {
        AVStaticHierarchyDataSource.sharedInstance.rawHierarchyInfo
    }

    func mcpCurrentAppInfo() -> NSObject? {
        AVStaticHierarchyDataSource.sharedInstance.appInfo
    }

    func mcpInspectorUIState() -> [String: Any] {
        var state: [String: Any] = ["uiMode": Self.appviewMCPUIMode()]
        let ds = AVStaticHierarchyDataSource.sharedInstance
        if let item = ds.selectedItem {
            state["selectedTitle"] = item.title() ?? ""
            state["selectedSubtitle"] = item.subtitle() ?? ""
            let oid = item.viewObject?.oid ?? item.layerObject?.oid ?? 0
            state["selectedOid"] = NSNumber(value: oid)
        }
        return state
    }

    func mcpOpenInspectorForAutomation() {
        DispatchQueue.main.async {
            let nav = AVNavigationManager.sharedInstance
            if nav.staticWindowController?.window?.isVisible == true {
                if AVStaticHierarchyDataSource.sharedInstance.rawHierarchyInfo != nil {
                    nav.staticWindowController?.mcpForceReload()
                    return
                }
                // Empty inspector (MCP reconnect) — return to launch and enter a live app.
                AVAppsManager.sharedInstance.endInspectingSession()
                nav.showLaunch()
            }
            if AVStaticHierarchyDataSource.sharedInstance.rawHierarchyInfo != nil {
                nav.showStaticWorkspace()
                nav.closeLaunch()
                return
            }
            if nav.launchWindowController == nil {
                nav.showLaunch()
            }
            NSApp.activate(ignoringOtherApps: true)
            nav.launchWindowController?.launchViewController?.appview_mcpTryEnterInspector()
        }
    }

    func mcpOpenAppSwitcherPopover() {
        DispatchQueue.main.async {
            AVNavigationManager.sharedInstance.staticWindowController?
                .popupAllInspectableApps(with: .appButton)
        }
    }

    func mcpFetchAndOpenAppSwitcher(timeout: TimeInterval) -> [String: Any] {
        AVMCPAppSwitcher.fetchAndOpen(timeout: timeout)
    }

    func mcpClientState() -> [String: Any]? {
        let ds = AVStaticHierarchyDataSource.sharedInstance
        guard let flatItems = ds.flatItems else { return nil }
        let items: [[String: Any]] = flatItems.map { item in
            var fields = AVMCPInspectorParity.itemFields(item)
            fields["isExpanded"] = item.isExpanded
            fields["computedExpandable"] = item.subitems?.isEmpty == false
            fields["subitemsCount"] = item.subitems?.count ?? -1
            fields["superItemNil"] = item.superItem == nil
            return fields
        }
        var result: [String: Any] = [
            "flatItemsCount": flatItems.count,
            "displayingFlatItemsCount": ds.displayingFlatItems?.count ?? 0,
            "items": items,
        ]
        if let sel = ds.selectedItem {
            result["selectedOid"] = NSNumber(value: sel.viewObject?.oid ?? sel.layerObject?.oid ?? 0)
        }
        if let pv = AVPreviewView.sharedForMCP {
            result["preview"] = pv.mcpDebugInfo()
        }
        let nav = AVNavigationManager.sharedInstance
        let sc = nav.staticWindowController
        result["isFetchingDetails"] = sc?.mcpFetchingDetails ?? false
        result["isFetchingHierarchy"] = sc?.mcpFetchingHierarchy ?? false
        result["uiMode"] = Self.appviewMCPUIMode()
        return result
    }

    func mcpEventLog() -> [Any]? {
        AVDebugEventLog.shared.allEvents
    }

    func mcpClearEventLog() {
        AVDebugEventLog.shared.clear()
    }

    func mcpConnectionDiagnostics() -> [String: Any] {
        AVMCPClientDiagnostics.shared.connectionStateDictionary() as? [String: Any] ?? [:]
    }

    func mcpDiagLogLines(limit: Int) -> [String] {
        AVMCPClientDiagnostics.shared.diagLogLines(limit: limit)
    }

    func mcpClearDiagLog() {
        AVMCPClientDiagnostics.shared.clearDiagLog()
    }

    func mcpDiscoverAppsSync(timeout: TimeInterval) -> [String: Any] {
        AVMCPClientDiagnostics.shared.discoverAppsSync(timeout: timeout) as? [String: Any] ?? [:]
    }

    func mcpEndInspectSession() {
        AVAppsManager.sharedInstance.endInspectingSession()
        AVNavigationManager.sharedInstance.showLaunch()
        AppViewDiagLog.log("client MCP end-inspect-session")
    }

    func mcpSimulatorPeertalkPortProbe() -> [String: Any] {
        AVMCPClientDiagnostics.shared.simulatorPeertalkPortProbe() as? [String: Any] ?? [:]
    }

    func mcpWireV2PingSync(timeout: TimeInterval) -> [String: Any] {
        mcpOnMain {
            AVMCPClientDiagnostics.shared.wireV2PingSync(timeout: timeout) as? [String: Any] ?? [:]
        }
    }

    func mcpReloadHierarchy() {
        AVNavigationManager.sharedInstance.staticWindowController?.mcpForceReload()
    }

    func mcpToggleFastMode() -> Bool {
        mcpOnMain {
            let manager = AVPreferenceMain()
            manager.fastMode = !manager.fastMode
            AVConnectionTiming.shared.recordInstant(
                "fastMode.toggle",
                durationMs: 0,
                attrs: ["enabled": manager.fastMode, "source": "mcp"]
            )
            return manager.fastMode
        }
    }

    func mcpSelectHierarchyRowMacView(_ view: NSView) -> Bool {
        var candidate: NSView? = view
        while let current = candidate {
            if let row = current as? AVHierarchyRowView, let item = row.displayItem {
                AVStaticHierarchyDataSource.sharedInstance.selectedItem = item
                return true
            }
            candidate = current.superview
        }
        return false
    }

    func mcpIosPreviewState() -> [String: Any]? {
        mcpOnMain { AVPreviewView.sharedForMCP?.mcpPreviewStateDictionary() as? [String: Any] }
    }

    func mcpIosPreviewScreenshotPNG() -> Data? {
        mcpOnMain { AVPreviewView.sharedForMCP?.mcpSnapshotPNGData() }
    }

    func mcpIosPreviewLighting() -> [String: Any]? {
        mcpOnMain { AVPreviewView.sharedForMCP?.mcpLightingInfo() as? [String: Any] }
    }

    func mcpIosPreviewSceneGraph() -> [String: Any]? {
        mcpOnMain { AVPreviewView.sharedForMCP?.mcpSceneGraphDump() as? [String: Any] }
    }

    func mcpIosPreviewTextureSources() -> [String: Any]? {
        mcpOnMain { AVPreviewView.sharedForMCP?.mcpTextureSourcesInfo() as? [String: Any] }
    }

    func mcpExportPreviewLayerScreenshots(to directory: String) -> [String: Any]? {
        mcpOnMain { AVPreviewView.sharedForMCP?.mcpExportLayerScreenshots(toDirectory: directory) }
    }

    func mcpInspectorParitySnapshot() -> [String: Any]? {
        mcpOnMain {
            let nav = AVNavigationManager.sharedInstance
            guard nav.staticWindowController?.window?.isVisible == true,
                  let staticVC = nav.staticWindowController?.viewController else {
                return nil
            }
            return staticVC.mcpInspectorParitySnapshot(uiMode: Self.appviewMCPUIMode())
        }
    }

    func mcpLaunchInspectTargets() -> [[String: Any]] {
        AVMCPInspectTarget.launchTargets()
    }

    func mcpSelectInspectTarget(
        channel: String?,
        accessibilityIdentifier: String?,
        index: Int,
        timeout: TimeInterval
    ) -> [String: Any] {
        let resolvedIndex: Int? = index == Int(NSNotFound) ? nil : (index >= 0 ? index : nil)
        return AVMCPInspectTarget.selectInspectTarget(
            channel: channel,
            accessibilityIdentifier: accessibilityIdentifier,
            index: resolvedIndex,
            timeout: timeout
        )
    }

    func mcpRefreshLaunchTargets(timeout: TimeInterval) -> [String: Any] {
        AVMCPInspectTarget.refreshLaunchTargets(timeout: timeout)
    }

    func mcpLaunchHealth() -> [String: Any] {
        AVMCPLaunchHealth.snapshot()
    }

    private func mcpOnMain<T>(_ work: () -> T) -> T {
        if Thread.isMainThread {
            return work()
        }
        return DispatchQueue.main.sync(execute: work)
    }

    private static func appviewMCPUIMode() -> String {
        let nav = AVNavigationManager.sharedInstance
        if nav.staticWindowController?.window?.isVisible == true {
            return "inspector"
        }
        if nav.launchWindowController?.window?.isVisible == true {
            return "launch"
        }
        return "unknown"
    }
}
