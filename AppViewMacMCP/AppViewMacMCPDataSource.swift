import AppKit
import Foundation

/// Swift MCP API for AppView macOS client (`:47192`). Implemented by `AppDelegate`.
@objc public protocol AppViewMacMCPDataSource: AnyObject {
    func mcpCurrentHierarchyInfo() -> NSObject?
    func mcpCurrentAppInfo() -> NSObject?
    func mcpInspectorUIState() -> [String: Any]
    func mcpOpenInspectorForAutomation()
    /// Toolbar App button — open sim/USB switcher popover (inspector only).
    func mcpOpenAppSwitcherPopover()
    /// MCP-sync variant: discover apps (no images), show popover, return tiles. Blocks until done.
    func mcpFetchAndOpenAppSwitcher(timeout: TimeInterval) -> [String: Any]
    func mcpClientState() -> [String: Any]?
    func mcpEventLog() -> [Any]?
    func mcpClearEventLog()
    func mcpConnectionDiagnostics() -> [String: Any]
    func mcpDiagLogLines(limit: Int) -> [String]
    func mcpClearDiagLog()
    func mcpDiscoverAppsSync(timeout: TimeInterval) -> [String: Any]
    func mcpEndInspectSession()
    func mcpSimulatorPeertalkPortProbe() -> [String: Any]
    func mcpWireV2PingSync(timeout: TimeInterval) -> [String: Any]
    func mcpReloadHierarchy()
    func mcpToggleFastMode() -> Bool
    func mcpSelectHierarchyRowMacView(_ view: NSView) -> Bool
    func mcpIosPreviewState() -> [String: Any]?
    func mcpIosPreviewScreenshotPNG() -> Data?
    func mcpIosPreviewLighting() -> [String: Any]?
    func mcpIosPreviewSceneGraph() -> [String: Any]?
    func mcpIosPreviewTextureSources() -> [String: Any]?
    func mcpExportPreviewLayerScreenshots(to directory: String) -> [String: Any]?
    /// Unified parity snapshot: hierarchy tree subtitles, mac row selection, preview background, dashboard attrs.
    func mcpInspectorParitySnapshot() -> [String: Any]?
    /// Launch screen / app-switcher popover tiles (`channel`: `sim` | `usb`).
    func mcpLaunchInspectTargets() -> [[String: Any]]
    /// Enter inspector from launch or switch sim ↔ USB (`channel`, `accessibilityIdentifier`, or `index`).
    func mcpSelectInspectTarget(
        channel: String?,
        accessibilityIdentifier: String?,
        index: Int,
        timeout: TimeInterval
    ) -> [String: Any]
    /// Reload launch screen and wait for sim/USB tiles.
    func mcpRefreshLaunchTargets(timeout: TimeInterval) -> [String: Any]
    /// Launch screen freeze / stall detection.
    func mcpLaunchHealth() -> [String: Any]
}
