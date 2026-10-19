import AppKit
import Foundation

@_silgen_name("AVOsAppMCPValueForKey")
private func AVOsAppMCPValueForKey(_ object: AnyObject?, _ key: NSString) -> AnyObject?

/// HTTP routes for the macOS MCP listener. KVC that can raise `NSException` goes through `AVOsAppMCPKVC.m`.
final class AVOsAppMCPHandler {
    weak var dataSource: AppViewMacMCPDataSource?

    func handle(method: String, path: String, body: Data?) -> (statusCode: Int, body: Data) {
        let split = AVOsAppMCPHTTPParser.splitPath(path)
        let pathOnly = split.pathOnly
        let query = split.query

        switch (method, pathOnly) {
        case ("GET", "/status"):
            return handleStatus()
        case ("GET", "/ui/connection"):
            return handleConnectionDiagnostics()
        case ("GET", "/ui/diag-log"):
            return handleDiagLog(query: query)
        case ("POST", "/ui/diag-log/clear"):
            return handleDiagLogClear()
        case ("POST", "/action/discover-apps"):
            return handleDiscoverApps(body: body)
        case ("POST", "/action/end-inspect-session"):
            return handleEndInspectSession()
        case ("GET", "/ui/simulator-peertalk-probe"):
            return handleSimulatorPeertalkProbe()
        case ("GET", "/ui/wire-v2-ping"):
            return handleWireV2Ping(query: query)
        case ("GET", "/ui/state"):
            return handleUIState()
        case ("GET", "/hierarchy"):
            return handleHierarchy()
        case ("GET", "/ui/hierarchy"):
            return handleUIHierarchy()
        case ("GET", "/ui/tap-targets"):
            return handleUITapTargets()
        case ("GET", "/ui/launch-targets"):
            return handleLaunchTargets()
        case ("GET", "/ui/launch-health"):
            return handleLaunchHealth()
        case ("POST", "/action/refresh-launch-targets"):
            return handleRefreshLaunchTargets(body: body)
        case ("POST", "/action/open-app-switcher"):
            return handleOpenAppSwitcher()
        case ("POST", "/action/select-inspect-target"):
            return handleSelectInspectTarget(body: body)
        case ("POST", "/ui/tap"):
            return handleUITap(body: body)
        case ("POST", "/ui/open-inspector"):
            return handleOpenInspector()
        case ("GET", "/ui/client-state"):
            return handleClientState()
        case ("GET", "/ui/inspector-parity"):
            return handleInspectorParity()
        case ("GET", "/ui/event-log"):
            return handleEventLog()
        case ("POST", "/ui/event-log/clear"):
            return handleEventLogClear()
        case ("POST", "/action/reload"):
            return handleReloadHierarchy()
        case ("POST", "/action/toggle-fast-mode"):
            return handleToggleFastMode()
        case ("GET", "/ui/preview/state"):
            return handlePreviewState()
        case ("GET", "/ui/preview/structure"):
            return handlePreviewStructure()
        case ("GET", "/ui/preview/screenshot"):
            return handlePreviewScreenshot()
        case ("POST", "/ui/preview/export-screenshots"):
            return handleExportPreviewScreenshots(body: body)
        case ("GET", "/ui/preview/lighting"):
            return handlePreviewLighting()
        case ("GET", "/ui/preview/scene-graph"):
            return handlePreviewSceneGraph()
        case ("GET", "/ui/preview/texture-sources"):
            return handlePreviewTextureSources()
        case ("GET", "/ui/screen-screenshot"):
            return handleScreenScreenshot()
        default:
            break
        }

        if method == "GET", pathOnly.hasSuffix("/screenshot") {
            let parts = pathOnly.split(separator: "/").map(String.init)
            if parts.last == "screenshot", parts.count >= 3 {
                let kind = parts[parts.count - 3]
                let oid = UInt(parts[parts.count - 2]) ?? 0
                if kind == "view", oid > 0 {
                    if parts.count == 4, parts[0] == "ui" {
                        return handleUIScreenshot(oid: oid)
                    }
                    if parts.count == 3 {
                        return handleScreenshot(oid: oid)
                    }
                }
            }
        }
        return error("Not found", statusCode: 404)
    }

    // MARK: - Status and diagnostics

    private func handleStatus() -> (statusCode: Int, body: Data) {
        let info = dataSource?.mcpCurrentAppInfo()
        var data: [String: Any] = [
            "connected": info != nil,
            "appName": string(kvc(info, "appName")),
            "bundleId": string(kvc(info, "appBundleIdentifier")),
            "deviceDescription": string(kvc(info, "deviceDescription")),
            "osDescription": string(kvc(info, "osDescription")),
            "screenWidth": kvc(info, "screenWidth") ?? 0,
            "screenHeight": kvc(info, "screenHeight") ?? 0,
        ]
        if let diag = dataSource?.mcpConnectionDiagnostics(), !diag.isEmpty {
            data["client"] = diag
        }
        return ok(data)
    }

    private func handleConnectionDiagnostics() -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        return ok(dataSource.mcpConnectionDiagnostics())
    }

    private func handleDiagLog(query: String?) -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        var limit = AVOsAppMCPHTTPParser.queryInt(query, key: "tail", default: 100)
        limit = min(500, max(1, limit))
        let lines = dataSource.mcpDiagLogLines(limit: limit)
        return ok(["count": lines.count, "lines": lines])
    }

    private func handleDiagLogClear() -> (statusCode: Int, body: Data) {
        dataSource?.mcpClearDiagLog()
        return ok(["cleared": true])
    }

    private func handleDiscoverApps(body: Data?) -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        var timeout = 20.0
        if let json = parseJSON(body), let value = doubleValue(json["timeout"]) {
            timeout = value
        }
        timeout = min(60, max(3, timeout))
        guard let result = wait(timeout: timeout + 20, queue: .global(qos: .userInitiated), {
            dataSource.mcpDiscoverAppsSync(timeout: timeout)
        }) else {
            return error("discover-apps timed out waiting for worker", statusCode: 504)
        }
        return ok(result)
    }

    private func handleEndInspectSession() -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        DispatchQueue.main.async {
            dataSource.mcpEndInspectSession()
        }
        return ok(["ended": true, "async": true])
    }

    private func handleSimulatorPeertalkProbe() -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        return ok(dataSource.mcpSimulatorPeertalkPortProbe())
    }

    private func handleWireV2Ping(query: String?) -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        var timeout = TimeInterval(AVOsAppMCPHTTPParser.queryInt(query, key: "timeout", default: 5))
        timeout = min(30, max(1, timeout))
        guard let result = wait(timeout: timeout + 3, queue: .main, {
            dataSource.mcpWireV2PingSync(timeout: timeout)
        }) else {
            return error("wire-v2-ping timed out", statusCode: 504)
        }
        return ok(result)
    }

    // MARK: - iOS hierarchy

    private func handleHierarchy() -> (statusCode: Int, body: Data) {
        guard let info = dataSource?.mcpCurrentHierarchyInfo(),
              let items = kvc(info, "displayItems") as? [NSObject], !items.isEmpty else {
            return error("No hierarchy. Connect an iOS app to AppView first.", statusCode: 503)
        }
        let appName = string(kvc(kvc(info, "appInfo") as? NSObject, "appName"))
        return ok(["appName": appName, "items": items.map(serializeItem)])
    }

    private func handleScreenshot(oid: UInt) -> (statusCode: Int, body: Data) {
        guard let info = dataSource?.mcpCurrentHierarchyInfo() else {
            return error("No hierarchy", statusCode: 503)
        }
        let roots = (kvc(info, "displayItems") as? [NSObject]) ?? []
        guard let found = flatItems(roots).first(where: { oidForItem($0) == oid }) else {
            return error("Item with oid \(oid) not found", statusCode: 404)
        }
        let image = (kvc(found, "soloScreenshot") as? NSImage) ?? (kvc(found, "groupScreenshot") as? NSImage)
        guard let image else { return error("No screenshot for this item", statusCode: 404) }
        return pngJSON(image: image, missing: "Failed to get CGImage", encodeFail: "Failed to encode PNG")
    }

    private func handleScreenScreenshot() -> (statusCode: Int, body: Data) {
        guard let info = dataSource?.mcpCurrentHierarchyInfo(),
              let roots = kvc(info, "displayItems") as? [NSObject],
              let root = roots.first else {
            return error("No hierarchy", statusCode: 503)
        }
        let image = (kvc(root, "groupScreenshot") as? NSImage) ?? (kvc(root, "soloScreenshot") as? NSImage)
        guard let image else {
            return error("No screen screenshot. Reload the hierarchy and wait for screenshots.", statusCode: 404)
        }
        return pngJSON(image: image, missing: "Failed to get CGImage", encodeFail: "Failed to encode PNG")
    }

    private func serializeItem(_ item: NSObject) -> [String: Any] {
        var dict: [String: Any] = ["oid": oidForItem(item)]
        let display = (kvc(item, "viewObject") as? NSObject) ?? (kvc(item, "layerObject") as? NSObject)
        dict["className"] = rawClassName(display) ?? ""
        if let frame = (kvc(item, "frame") as? NSValue)?.rectValue {
            dict["frame"] = frameJSON(frame)
        }
        if (kvc(item, "isHidden") as? NSNumber)?.boolValue == true {
            dict["hidden"] = true
        }
        if let alpha = kvc(item, "alpha") as? NSNumber, alpha.floatValue < 0.999 {
            dict["alpha"] = alpha
        }
        if let title = kvc(item, "customDisplayTitle") as? String, !title.isEmpty {
            dict["customTitle"] = title
        }
        if let vcName = rawClassName(kvc(item, "hostViewControllerObject") as? NSObject) {
            dict["viewController"] = vcName
        }
        let children = (kvc(item, "subitems") as? [NSObject]) ?? []
        dict["children"] = children.map(serializeItem)
        return dict
    }

    private func oidForItem(_ item: NSObject) -> UInt {
        if let viewOid = kvc(kvc(item, "viewObject") as? NSObject, "oid") as? NSNumber {
            return viewOid.uintValue
        }
        if let layerOid = kvc(kvc(item, "layerObject") as? NSObject, "oid") as? NSNumber {
            return layerOid.uintValue
        }
        return 0
    }

    private func flatItems(_ items: [NSObject]) -> [NSObject] {
        var result: [NSObject] = []
        for item in items {
            result.append(item)
            if let sub = kvc(item, "subitems") as? [NSObject] {
                result.append(contentsOf: flatItems(sub))
            }
        }
        return result
    }

    // MARK: - macOS UI

    private func handleUIHierarchy() -> (statusCode: Int, body: Data) {
        let windows = NSApp.windows.map(serializeWindow)
        return ok(["appName": "AppView", "windows": windows])
    }

    private func serializeWindow(_ window: NSWindow) -> [String: Any] {
        var dict: [String: Any] = [
            "oid": pointerOid(window),
            "title": window.title,
            "visible": window.isVisible,
            "frame": frameJSON(window.frame),
        ]
        if let content = window.contentView {
            dict["contentView"] = serializeView(content)
        }
        return dict
    }

    private func serializeView(_ view: NSView) -> [String: Any] {
        var dict: [String: Any] = [
            "oid": pointerOid(view),
            "className": className(view),
            "frame": frameJSON(view.frame),
        ]
        if view.isHidden { dict["hidden"] = true }
        if view.alphaValue < 0.999 { dict["alpha"] = view.alphaValue }
        if let identifier = view.identifier?.rawValue, !identifier.isEmpty {
            dict["identifier"] = identifier
        }
        if let label = view.accessibilityLabel(), !label.isEmpty {
            dict["label"] = label
        }
        dict["children"] = view.subviews.map(serializeView)
        return dict
    }

    private func handleUIScreenshot(oid: UInt) -> (statusCode: Int, body: Data) {
        guard let found = findView(oid: oid) else {
            return error("NSView with oid \(oid) not found", statusCode: 404)
        }
        guard let rep = found.bitmapImageRepForCachingDisplay(in: found.bounds) else {
            return error("Failed to create bitmap rep", statusCode: 500)
        }
        found.cacheDisplay(in: found.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return error("Failed to encode PNG", statusCode: 500)
        }
        return ok([
            "imageBase64": png.base64EncodedString(),
            "mimeType": "image/png",
            "width": found.bounds.width,
            "height": found.bounds.height,
        ])
    }

    private func enumerateToolbarViews(in window: NSWindow, _ block: (NSView) -> Void) {
        guard let toolbar = window.toolbar else { return }
        for item in toolbar.items {
            if let view = item.view, !view.isHidden {
                block(view)
            }
        }
    }

    private func findView(oid: UInt) -> NSView? {
        for window in NSApp.windows where window.isVisible {
            var toolbarHit: NSView?
            enumerateToolbarViews(in: window) { view in
                if toolbarHit == nil, pointerOid(view) == oid {
                    toolbarHit = view
                }
            }
            if let toolbarHit { return toolbarHit }
            if let found = findView(oid: oid, in: window.contentView) { return found }
        }
        return nil
    }

    private func findView(oid: UInt, in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if pointerOid(view) == oid { return view }
        for sub in view.subviews {
            if let found = findView(oid: oid, in: sub) { return found }
        }
        return nil
    }

    private func handleUITapTargets() -> (statusCode: Int, body: Data) {
        var targets: [[String: Any]] = []
        var hierarchyRowIndex: UInt = 0
        for window in NSApp.windows where window.isVisible {
            enumerateToolbarViews(in: window) { view in
                if let info = tapTargetInfo(view: view, window: window, hierarchyRowIndex: &hierarchyRowIndex) {
                    targets.append(info)
                }
            }
            collectTapTargets(in: window.contentView, window: window, hierarchyRowIndex: &hierarchyRowIndex, targets: &targets)
        }
        return ok(["count": targets.count, "targets": targets])
    }

    private func collectTapTargets(
        in view: NSView?,
        window: NSWindow,
        hierarchyRowIndex: inout UInt,
        targets: inout [[String: Any]]
    ) {
        guard let view, !view.isHidden else { return }
        let bounds = view.bounds
        if bounds.width < 4 || bounds.height < 4 || view.alphaValue < 0.05 {
            for sub in view.subviews {
                collectTapTargets(in: sub, window: window, hierarchyRowIndex: &hierarchyRowIndex, targets: &targets)
            }
            return
        }
        if let info = tapTargetInfo(view: view, window: window, hierarchyRowIndex: &hierarchyRowIndex) {
            targets.append(info)
            if classNameMatches(className(view), "AVHierarchyRowView") {
                hierarchyRowIndex += 1
            }
        }
        for sub in view.subviews {
            collectTapTargets(in: sub, window: window, hierarchyRowIndex: &hierarchyRowIndex, targets: &targets)
        }
    }

    private func displayItem(for row: NSView) -> NSObject? {
        if let item = kvc(row, "displayItem") as? NSObject { return item }
        let sel = NSSelectorFromString("mcp_rowDisplayItem")
        guard row.responds(to: sel),
              let result = row.perform(sel)?.takeUnretainedValue() as? NSObject else {
            return nil
        }
        return result
    }

    private func tapTargetInfo(view: NSView, window: NSWindow, hierarchyRowIndex: inout UInt) -> [String: Any]? {
        let name = className(view)
        if classNameMatches(name, "AVHierarchyRowView") {
            var dict = baseTapTarget(view: view, window: window)
            dict["action"] = "hierarchySelect"
            dict["effect"] = "Select connected iOS view/layer in inspector"
            dict["hierarchyRowIndex"] = hierarchyRowIndex
            if let item = displayItem(for: view) {
                if let title = kvc(item, "title") as? String, !title.isEmpty { dict["title"] = title }
                if let subtitle = kvc(item, "subtitle") as? String, !subtitle.isEmpty { dict["subtitle"] = subtitle }
                let iosOid = (kvc(kvc(item, "viewObject") as? NSObject, "oid") as? NSNumber)?.uintValue
                    ?? (kvc(kvc(item, "layerObject") as? NSObject, "oid") as? NSNumber)?.uintValue
                    ?? 0
                if iosOid > 0 { dict["iosOid"] = iosOid }
            } else {
                if let label = view.accessibilityLabel(), !label.isEmpty { dict["title"] = label }
            }
            return dict
        }
        if classNameMatches(name, "AVWindowToolbarAppButton") {
            var dict = baseTapTarget(view: view, window: window)
            dict["action"] = "toolbarSelectApp"
            dict["effect"] = "Open app switcher popover (sim/USB tiles)"
            return dict
        }
        if classNameMatches(name, "AVLaunchAppView") {
            var dict = baseTapTarget(view: view, window: window)
            dict["action"] = "openInspector"
            let app = kvc(view, "app") as? NSObject
            let appInfo = kvc(app, "appInfo") as? NSObject
            let appName = kvc(appInfo, "appName") as? String
            let deviceDescription = kvc(appInfo, "deviceDescription") as? String
            let bundleId = kvc(appInfo, "appBundleIdentifier") as? String
            let osDescription = kvc(appInfo, "osDescription") as? String
            let a11y = view.accessibilityIdentifier()
            var channel: String?
            if !a11y.isEmpty {
                dict["accessibilityIdentifier"] = a11y
                if a11y.hasSuffix(".usb") { channel = "usb" }
                else if a11y.hasSuffix(".sim") { channel = "sim" }
            }
            if let channel, !channel.isEmpty {
                dict["channel"] = channel
                dict["effect"] = channel == "usb"
                    ? "Open inspector for USB-connected iOS app"
                    : "Open inspector for Simulator iOS app"
            } else {
                dict["effect"] = "Open inspector for this connected iOS app"
            }
            if let deviceDescription, !deviceDescription.isEmpty { dict["title"] = deviceDescription }
            else if let appName, !appName.isEmpty { dict["title"] = appName }
            if let bundleId, !bundleId.isEmpty { dict["bundleId"] = bundleId }
            if let appName, !appName.isEmpty { dict["appName"] = appName }
            if let deviceDescription, !deviceDescription.isEmpty { dict["deviceDescription"] = deviceDescription }
            if let osDescription, !osDescription.isEmpty { dict["osDescription"] = osDescription }
            return dict
        }
        let clickSel = NSSelectorFromString("triggerClickAction")
        if view.responds(to: clickSel) {
            let target = kvc(view, "target")
            let clickAction = kvc(view, "clickAction")
            if target == nil || clickAction == nil || clickAction is NSNull { return nil }
            var dict = baseTapTarget(view: view, window: window)
            dict["action"] = "clickAction"
            dict["effect"] = "Fire control click handler (triggerClickAction)"
            if let selector = clickAction as? String, !selector.isEmpty { dict["selector"] = selector }
            return dict
        }
        if let control = view as? NSControl {
            if !control.isEnabled || control.isHidden { return nil }
            var dict = baseTapTarget(view: view, window: window)
            dict["action"] = "controlClick"
            dict["effect"] = "Perform NSControl click (performClick:)"
            if control.responds(to: NSSelectorFromString("title")),
               let title = kvc(control, "title") as? String, !title.isEmpty {
                dict["title"] = title
            }
            return dict
        }
        if viewHasCustomMouseClickHandler(view) {
            var dict = baseTapTarget(view: view, window: window)
            dict["action"] = "mouseClick"
            dict["effect"] = "Deliver synthetic mouseDown/mouseUp"
            return dict
        }
        return nil
    }

    private func baseTapTarget(view: NSView, window: NSWindow) -> [String: Any] {
        var dict: [String: Any] = [
            "oid": pointerOid(view),
            "className": className(view),
            "frame": frameJSON(view.frame),
        ]
        if !window.title.isEmpty { dict["windowTitle"] = window.title }
        if let identifier = view.identifier?.rawValue, !identifier.isEmpty { dict["identifier"] = identifier }
        let a11y = view.accessibilityIdentifier()
        if !a11y.isEmpty { dict["accessibilityIdentifier"] = a11y }
        if let label = view.accessibilityLabel(), !label.isEmpty { dict["label"] = label }
        return dict
    }

    private func viewHasCustomMouseClickHandler(_ view: NSView) -> Bool {
        let name = className(view)
        let known: Set<String> = [
            "AVDashboardCardView",
            "AVDashboardAttributeColorView",
            "AVDashboardAttributeEnumsView",
            "AVTextFieldView",
        ]
        if known.contains(name) { return true }
        return name.hasPrefix("AVDashboardAttribute")
            && view.responds(to: #selector(NSView.mouseDown(with:)))
            && view.responds(to: #selector(NSView.mouseUp(with:)))
    }

    private func handleUIState() -> (statusCode: Int, body: Data) {
        var data: [String: Any] = [:]
        if let clientState = dataSource?.mcpInspectorUIState() {
            for (key, value) in clientState where value is String || value is NSNumber {
                data[key] = value
            }
        }
        var cards: UInt = 0
        var rows: UInt = 0
        for window in NSApp.windows {
            countViews(in: window.contentView, cards: &cards, rows: &rows)
        }
        data["dashboardCards"] = cards
        data["hierarchyRows"] = rows
        data["hasInspectorShell"] = NSApp.windows.contains { view($0.contentView, hasClassNamed: "AVSplitView") }
        return ok(data)
    }

    private func countViews(in view: NSView?, cards: inout UInt, rows: inout UInt) {
        guard let view else { return }
        let name = className(view)
        if classNameMatches(name, "AVDashboardCardView") { cards += 1 }
        else if classNameMatches(name, "AVHierarchyRowView") { rows += 1 }
        for sub in view.subviews { countViews(in: sub, cards: &cards, rows: &rows) }
    }

    private func view(_ view: NSView?, hasClassNamed className: String) -> Bool {
        guard let view else { return false }
        if classNameMatches(self.className(view), className) { return true }
        return view.subviews.contains { self.view($0, hasClassNamed: className) }
    }

    private func handleUITap(body: Data?) -> (statusCode: Int, body: Data) {
        guard let json = parseJSON(body) else { return error("Invalid JSON body", statusCode: 400) }
        var channel = json["channel"] as? String
        channel = channel?.lowercased()
        if channel?.isEmpty == true { channel = nil }
        var accessibilityIdentifier = json["accessibilityIdentifier"] as? String
        if accessibilityIdentifier?.isEmpty != false { accessibilityIdentifier = nil }

        if (channel?.isEmpty == false || accessibilityIdentifier?.isEmpty == false), let dataSource {
            var index = NSNotFound
            if let raw = json["index"], !(raw is NSNull) { index = integerValue(raw) ?? NSNotFound }
            var timeout = doubleValue(json["timeout"]) ?? 45
            timeout = min(120, max(5, timeout))
            guard let selectResult = wait(timeout: timeout + 60, queue: .global(qos: .userInitiated), {
                dataSource.mcpSelectInspectTarget(
                    channel: channel,
                    accessibilityIdentifier: accessibilityIdentifier,
                    index: index,
                    timeout: timeout
                )
            }) else {
                return error("select-inspect-target timed out", statusCode: 504)
            }
            let okFlag = boolValue(selectResult["ok"])
            var payload = selectResult
            payload["clicked"] = true
            payload["selectionApplied"] = okFlag
            return (okFlag ? 200 : 404, successBody(payload))
        }

        var targetView: NSView?
        var point = CGPoint.zero
        var hasPoint = false
        if let accessibilityIdentifier {
            targetView = findView(accessibilityIdentifier: accessibilityIdentifier)
        }
        if targetView == nil, let channel {
            targetView = findLaunchAppView(channel: channel)
        }
        if let oidValue = json["oid"], !(oidValue is NSNull) {
            let oid = uintValue(oidValue)
            if oid == 0 { return error("Invalid oid", statusCode: 400) }
            guard let found = findView(oid: oid) else {
                return error("NSView with oid \(oid) not found", statusCode: 404)
            }
            targetView = found
            point = defaultClickPoint(found)
            hasPoint = true
        }
        if !hasPoint {
            guard let x = doubleValue(json["x"]), let y = doubleValue(json["y"]) else {
                return error("Provide either 'oid' or window 'x'+'y'", statusCode: 400)
            }
            point = CGPoint(x: x, y: y)
            hasPoint = true
        }
        _ = hasPoint
        var window = targetView?.window ?? NSApp.keyWindow ?? NSApp.mainWindow
        guard let window else { return error("No key window", statusCode: 503) }
        if targetView == nil {
            guard let hit = window.contentView?.hitTest(point) else {
                return error("No view at the given point", statusCode: 404)
            }
            targetView = hit
        }
        guard let targetView else { return error("No view at the given point", statusCode: 404) }
        let name = className(targetView)

        if classNameMatches(name, "AVWindowToolbarAppButton"), let dataSource {
            dataSource.mcpOpenAppSwitcherPopover()
            return ok([
                "clicked": true,
                "popoverOpened": true,
                "className": name,
                "oid": pointerOid(targetView),
            ])
        }
        if classNameMatches(name, "AVLaunchAppView"), let dataSource {
            let a11y = targetView.accessibilityIdentifier()
            var launchChannel: String?
            if a11y.hasSuffix(".usb") { launchChannel = "usb" }
            else if a11y.hasSuffix(".sim") { launchChannel = "sim" }
            var timeout = doubleValue(json["timeout"]) ?? 45
            timeout = min(120, max(5, timeout))
            guard let selectResult = wait(timeout: timeout + 60, queue: .global(qos: .userInitiated), {
                dataSource.mcpSelectInspectTarget(
                    channel: launchChannel,
                    accessibilityIdentifier: a11y,
                    index: NSNotFound,
                    timeout: timeout
                )
            }) else {
                return error("select-inspect-target timed out", statusCode: 504)
            }
            let okFlag = boolValue(selectResult["ok"])
            var payload = selectResult
            payload["clicked"] = true
            payload["oid"] = pointerOid(targetView)
            payload["className"] = name
            payload["x"] = point.x
            payload["y"] = point.y
            payload["selectionApplied"] = okFlag
            if !a11y.isEmpty { payload["accessibilityIdentifier"] = a11y }
            if let launchChannel, !launchChannel.isEmpty { payload["channel"] = launchChannel }
            return (okFlag ? 200 : 404, successBody(payload))
        }

        let hierarchySelected = dataSource?.mcpSelectHierarchyRowMacView(targetView) ?? false
        var clicked = hierarchySelected
        if !clicked {
            clicked = sendSyntheticClick(at: point, on: targetView, in: window)
        }
        if !clicked { return error("Failed to deliver click", statusCode: 500) }
        var payload: [String: Any] = [
            "clicked": true,
            "oid": pointerOid(targetView),
            "className": className(targetView),
            "x": point.x,
            "y": point.y,
            "hierarchySelectionApplied": hierarchySelected,
        ]
        if let ui = dataSource?.mcpInspectorUIState() {
            if let selectedOid = ui["selectedOid"] { payload["selectedOid"] = selectedOid }
            if let selectedTitle = ui["selectedTitle"] { payload["selectedTitle"] = selectedTitle }
            if let uiMode = ui["uiMode"] { payload["uiMode"] = uiMode }
        }
        return ok(payload)
    }

    private func handleOpenAppSwitcher() -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        guard let result = wait(timeout: 45, queue: .global(qos: .userInitiated), {
            dataSource.mcpFetchAndOpenAppSwitcher(timeout: 30)
        }) else {
            return error("open-app-switcher timed out waiting for discovery", statusCode: 504)
        }
        let okFlag = boolValue(result["ok"]) || integerValue(result["count"]) ?? 0 > 0
        return (okFlag ? 200 : 404, successBody(result))
    }

    private func handleLaunchTargets() -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        var targets = dataSource.mcpLaunchInspectTargets()
        var uiMode = dataSource.mcpInspectorUIState()["uiMode"] as? String ?? "unknown"
        if targets.isEmpty, uiMode == "launch" {
            let refreshed = dataSource.mcpRefreshLaunchTargets(timeout: 30)
            if let refreshedTargets = refreshed["targets"] as? [[String: Any]], !refreshedTargets.isEmpty {
                targets = refreshedTargets
            }
        }
        return ok(["uiMode": uiMode, "count": targets.count, "targets": targets])
    }

    private func handleLaunchHealth() -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        return ok(dataSource.mcpLaunchHealth())
    }

    private func handleRefreshLaunchTargets(body: Data?) -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        let json = parseJSON(body)
        var timeout = doubleValue(json?["timeout"]) ?? 45
        timeout = min(120, max(10, timeout))
        guard let result = wait(timeout: timeout + 20, queue: .global(qos: .userInitiated), {
            dataSource.mcpRefreshLaunchTargets(timeout: timeout)
        }) else {
            return error("refresh-launch-targets timed out", statusCode: 504)
        }
        return (boolValue(result["ok"]) ? 200 : 404, successBody(result))
    }

    private func handleSelectInspectTarget(body: Data?) -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        guard let json = parseJSON(body) else { return error("Invalid JSON body", statusCode: 400) }
        var channel = json["channel"] as? String
        channel = channel?.lowercased()
        if channel?.isEmpty == true { channel = nil }
        var accessibilityIdentifier = json["accessibilityIdentifier"] as? String
        if accessibilityIdentifier?.isEmpty != false { accessibilityIdentifier = nil }
        var index = NSNotFound
        if let raw = json["index"], !(raw is NSNull) { index = integerValue(raw) ?? NSNotFound }
        var timeout = doubleValue(json["timeout"]) ?? 45
        timeout = min(120, max(5, timeout))
        if (channel?.isEmpty != false), accessibilityIdentifier == nil, index == NSNotFound {
            return error("Provide channel, accessibilityIdentifier, or index", statusCode: 400)
        }
        guard let result = wait(timeout: timeout + 60, queue: .global(qos: .userInitiated), {
            dataSource.mcpSelectInspectTarget(
                channel: channel,
                accessibilityIdentifier: accessibilityIdentifier,
                index: index,
                timeout: timeout
            )
        }) else {
            return error("select-inspect-target timed out", statusCode: 504)
        }
        return (boolValue(result["ok"]) ? 200 : 404, successBody(result))
    }

    private func findView(accessibilityIdentifier identifier: String) -> NSView? {
        for window in NSApp.windows where window.isVisible {
            var toolbarHit: NSView?
            enumerateToolbarViews(in: window) { view in
                if toolbarHit == nil, view.accessibilityIdentifier() == identifier {
                    toolbarHit = view
                }
            }
            if let toolbarHit { return toolbarHit }
            if let found = findView(accessibilityIdentifier: identifier, in: window.contentView) {
                return found
            }
        }
        return nil
    }

    private func findView(accessibilityIdentifier identifier: String, in view: NSView?) -> NSView? {
        guard let view, !view.isHidden else { return nil }
        if view.accessibilityIdentifier() == identifier { return view }
        for sub in view.subviews {
            if let found = findView(accessibilityIdentifier: identifier, in: sub) { return found }
        }
        return nil
    }

    private func findLaunchAppView(channel: String) -> NSView? {
        let suffix = ".\(channel)"
        for window in NSApp.windows where window.isVisible {
            if let found = findLaunchAppView(suffix: suffix, in: window.contentView) { return found }
        }
        return nil
    }

    private func findLaunchAppView(suffix: String, in view: NSView?) -> NSView? {
        guard let view, !view.isHidden else { return nil }
        let a11y = view.accessibilityIdentifier()
        if classNameMatches(className(view), "AVLaunchAppView"), !a11y.isEmpty, a11y.hasSuffix(suffix) {
            return view
        }
        for sub in view.subviews {
            if let found = findLaunchAppView(suffix: suffix, in: sub) { return found }
        }
        return nil
    }

    private func defaultClickPoint(_ view: NSView) -> CGPoint {
        let rect = view.convert(view.bounds, to: nil)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    private func handleEventLog() -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        let events = dataSource.mcpEventLog() ?? []
        return ok(["count": events.count, "events": events])
    }

    private func handleEventLogClear() -> (statusCode: Int, body: Data) {
        dataSource?.mcpClearEventLog()
        return ok(["cleared": true])
    }

    private func handleReloadHierarchy() -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        dataSource.mcpReloadHierarchy()
        return ok(["triggered": true])
    }

    private func handleToggleFastMode() -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        return ok(["fastMode": dataSource.mcpToggleFastMode()])
    }

    private func handlePreviewState() -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        guard let state = dataSource.mcpIosPreviewState() else {
            return error("No iOS preview available (inspector not open or hierarchy not loaded)", statusCode: 503)
        }
        return ok(state)
    }

    private func handlePreviewStructure() -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        guard let state = dataSource.mcpIosPreviewState() else {
            return error("No iOS preview available", statusCode: 503)
        }
        let layers = (state["layers"] as? [Any]) ?? (state["structure"] as? [Any]) ?? []
        return ok([
            "sceneLayout": state["sceneLayout"] ?? "flat",
            "layers": layers,
            "structure": layers,
            "dimension": state["dimension"] ?? 0,
            "visibleLayersCount": state["visibleLayersCount"] ?? layers.count,
            "displayItemNodesCount": state["displayItemNodesCount"] ?? 0,
            "flatDisplayItemsCount": state["flatDisplayItemsCount"] ?? 0,
        ])
    }

    private func handleExportPreviewScreenshots(body: Data?) -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        guard let json = parseJSON(body) else { return error("Invalid JSON body", statusCode: 400) }
        guard let directory = json["directory"] as? String, !directory.isEmpty else {
            return error("Missing \"directory\" string in body", statusCode: 400)
        }
        guard let result = dataSource.mcpExportPreviewLayerScreenshots(to: directory) else {
            return error("No iOS preview available", statusCode: 503)
        }
        if let message = result["error"] as? String {
            return error(message, statusCode: 400)
        }
        return ok(result)
    }

    private func handlePreviewLighting() -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        guard let info = dataSource.mcpIosPreviewLighting() else {
            return error("No iOS preview available", statusCode: 503)
        }
        return ok(info)
    }

    private func handlePreviewSceneGraph() -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        guard let graph = dataSource.mcpIosPreviewSceneGraph() else {
            return error("No iOS preview available", statusCode: 503)
        }
        return ok(graph)
    }

    private func handlePreviewTextureSources() -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        guard let info = dataSource.mcpIosPreviewTextureSources() else {
            return error("No iOS preview available", statusCode: 503)
        }
        return ok(info)
    }

    private func handlePreviewScreenshot() -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        guard let png = dataSource.mcpIosPreviewScreenshotPNG(), !png.isEmpty else {
            return error("No iOS preview screenshot available", statusCode: 503)
        }
        return ok([
            "imageBase64": png.base64EncodedString(),
            "mimeType": "image/png",
            "width": 640,
            "height": 480,
        ])
    }

    private func handleClientState() -> (statusCode: Int, body: Data) {
        guard let dataSource else { return error("Not implemented by this version", statusCode: 501) }
        guard let state = dataSource.mcpClientState() else {
            return error("No client state available (hierarchy not loaded)", statusCode: 503)
        }
        return ok(state)
    }

    private func handleInspectorParity() -> (statusCode: Int, body: Data) {
        if let snapshot = dataSource?.mcpInspectorParitySnapshot(), !snapshot.isEmpty {
            return ok(snapshot)
        }
        guard dataSource != nil else {
            return error("Data source does not implement hierarchy snapshot", statusCode: 501)
        }
        guard dataSource?.mcpCurrentHierarchyInfo() != nil else {
            return error("No inspector parity snapshot (connect iOS app and open inspector)", statusCode: 503)
        }
        return ok(buildInspectorParityFallback())
    }

    private func handleOpenInspector() -> (statusCode: Int, body: Data) {
        guard let dataSource else {
            return error("Data source does not implement mcp_openInspectorForAutomation", statusCode: 501)
        }
        dataSource.mcpOpenInspectorForAutomation()
        return ok(["started": true])
    }

    // MARK: - Parity

    private func rawClassName(_ object: NSObject?) -> String? {
        guard let object else { return nil }
        let sel = NSSelectorFromString("rawClassName")
        guard object.responds(to: sel),
              let name = object.perform(sel)?.takeUnretainedValue() as? String,
              !name.isEmpty else {
            return nil
        }
        return name
    }

    private func ivarNames(for object: NSObject?) -> [String] {
        guard let object, let traces = kvc(object, "ivarTraces") as? [NSObject] else { return [] }
        var names: [String] = []
        var seen = Set<String>()
        for trace in traces {
            guard let name = kvc(trace, "ivarName") as? String, !name.isEmpty, seen.insert(name).inserted else { continue }
            names.append(name)
        }
        return names.sorted()
    }

    private func title(for item: NSObject) -> String {
        if let customInfo = kvc(item, "customInfo") as? NSObject,
           let title = kvc(customInfo, "title") as? String, !title.isEmpty {
            return title
        }
        if let customTitle = kvc(item, "customDisplayTitle") as? String, !customTitle.isEmpty {
            return customTitle
        }
        if let viewName = rawClassName(kvc(item, "viewObject") as? NSObject), !viewName.isEmpty {
            return viewName
        }
        return rawClassName(kvc(item, "layerObject") as? NSObject) ?? ""
    }

    private func subtitle(for item: NSObject) -> String? {
        if let customInfo = kvc(item, "customInfo") as? NSObject {
            let subtitle = kvc(customInfo, "subtitle") as? String
            return (subtitle?.isEmpty == false) ? subtitle : nil
        }
        if let hostName = rawClassName(kvc(item, "hostViewControllerObject") as? NSObject), !hostName.isEmpty {
            return "\(hostName).view"
        }
        let represented = (kvc(item, "viewObject") as? NSObject) ?? (kvc(item, "layerObject") as? NSObject)
        guard let represented else { return nil }
        if let special = kvc(represented, "specialTrace") as? String, !special.isEmpty { return special }
        let names = ivarNames(for: represented)
        return names.isEmpty ? nil : names.joined(separator: "   ")
    }

    private func rgbaArray(for item: NSObject) -> Any {
        guard let color = kvc(item, "backgroundColor") as? NSObject,
              let rgba = kvc(color, "appview_rgbaComponents") as? [Any] else {
            return NSNull()
        }
        let nums = rgba.compactMap { $0 as? NSNumber }
        return nums.count >= 4 ? nums : NSNull()
    }

    private func parityFields(for item: NSObject, indentLevel: Int) -> [String: Any] {
        let represented = (kvc(item, "viewObject") as? NSObject) ?? (kvc(item, "layerObject") as? NSObject)
        let displaying = kvc(item, "displayingInHierarchy")
        let displayingInHierarchy = !(displaying is NSNumber) || (displaying as? NSNumber)?.boolValue == true
        return [
            "oid": oidForItem(item),
            "title": title(for: item),
            "subtitle": subtitle(for: item) ?? "",
            "specialTrace": string(kvc(represented, "specialTrace")),
            "ivarNames": ivarNames(for: represented),
            "memoryAddress": string(kvc(represented, "memoryAddress")),
            "backgroundColorRGBA": rgbaArray(for: item),
            "indentLevel": indentLevel,
            "displayingInHierarchy": displayingInHierarchy,
            "isExpandable": (kvc(item, "isExpandable") as? NSNumber)?.boolValue ?? false,
            "isExpanded": (kvc(item, "isExpanded") as? NSNumber)?.boolValue ?? false,
            "hasSoloScreenshot": kvc(item, "soloScreenshot") != nil,
            "hasGroupScreenshot": kvc(item, "groupScreenshot") != nil,
        ]
    }

    private func flattenParity(_ items: [NSObject], indentLevel: Int, into out: inout [[String: Any]]) {
        for item in items {
            let displaying = kvc(item, "displayingInHierarchy")
            if !(displaying is NSNumber) || (displaying as? NSNumber)?.boolValue == true {
                out.append(parityFields(for: item, indentLevel: indentLevel))
            }
            if let sub = kvc(item, "subitems") as? [NSObject], !sub.isEmpty {
                flattenParity(sub, indentLevel: indentLevel + 1, into: &out)
            }
        }
    }

    private func macRowBool(_ view: NSView, key: String) -> Bool {
        if let number = kvc(view, key) as? NSNumber { return number.boolValue }
        if key == "isSelected", let number = kvc(view, "_appviewSelected") as? NSNumber { return number.boolValue }
        if key == "isHovered", let number = kvc(view, "_appviewHovered") as? NSNumber { return number.boolValue }
        let sel = NSSelectorFromString(key)
        if view.responds(to: sel), let number = view.perform(sel)?.takeUnretainedValue() as? NSNumber {
            return number.boolValue
        }
        return false
    }

    private func collectHierarchyMacRows(in view: NSView?, rowIndex: inout UInt, into rows: inout [[String: Any]]) {
        guard let view else { return }
        if classNameMatches(className(view), "AVHierarchyRowView"),
           let item = kvc(view, "displayItem") as? NSObject {
            var row = parityFields(for: item, indentLevel: 0)
            row["row"] = rowIndex
            row["macIsSelected"] = macRowBool(view, key: "isSelected")
            row["macIsHovered"] = macRowBool(view, key: "isHovered")
            if let label = kvc(view, "subtitleLabel") as? NSView {
                row["subtitleLabelHidden"] = label.isHidden
            }
            rows.append(row)
            rowIndex += 1
        }
        for sub in view.subviews {
            collectHierarchyMacRows(in: sub, rowIndex: &rowIndex, into: &rows)
        }
    }

    private func collectHierarchyMacRows() -> [[String: Any]] {
        var rows: [[String: Any]] = []
        var rowIndex: UInt = 0
        for window in NSApp.windows {
            collectHierarchyMacRows(in: window.contentView, rowIndex: &rowIndex, into: &rows)
        }
        return rows
    }

    private func selectionParity(oid: UInt, tree: [[String: Any]], macRows: [[String: Any]]) -> [String: Any] {
        var selection = tree.first { ($0["oid"] as? UInt) == oid || ($0["oid"] as? NSNumber)?.uintValue == oid } ?? [
            "oid": oid,
            "title": "",
            "subtitle": "",
            "specialTrace": "",
            "ivarNames": [String](),
            "backgroundColorRGBA": NSNull(),
        ]
        let macSelected = macRows.contains { row in
            let rowOid = (row["oid"] as? NSNumber)?.uintValue ?? (row["oid"] as? UInt) ?? 0
            return rowOid == oid && boolValue(row["macIsSelected"])
        }
        selection["macRowIsSelected"] = macSelected
        return selection
    }

    private func buildInspectorParityFallback() -> [String: Any] {
        var uiMode = "unknown"
        var selectedOid: UInt = 0
        if let ui = dataSource?.mcpInspectorUIState() {
            if let mode = ui["uiMode"] as? String, !mode.isEmpty { uiMode = mode }
            selectedOid = (ui["selectedOid"] as? NSNumber)?.uintValue ?? 0
        }
        if selectedOid == 0, let client = dataSource?.mcpClientState() {
            selectedOid = (client["selectedOid"] as? NSNumber)?.uintValue ?? 0
            if let mode = client["uiMode"] as? String, !mode.isEmpty { uiMode = mode }
        }
        let roots = (kvc(dataSource?.mcpCurrentHierarchyInfo(), "displayItems") as? [NSObject]) ?? []
        var tree: [[String: Any]] = []
        flattenParity(roots, indentLevel: 0, into: &tree)
        let macRows = collectHierarchyMacRows()
        let selectedMacCount = macRows.filter { boolValue($0["macIsSelected"]) }.count
        var preview: [String: Any] = [:]
        if let tex = dataSource?.mcpIosPreviewTextureSources() {
            let items = tex["items"] as? [Any] ?? []
            preview["items"] = items
            preview["displayItemNodesCount"] = tex["displayItemNodesCount"] ?? items.count
        }
        if preview["items"] == nil {
            preview["items"] = [Any]()
            preview["displayItemNodesCount"] = 0
        }
        return [
            "schemaVersion": 1,
            "uiMode": uiMode,
            "flatItemsCount": tree.count,
            "displayingFlatItemsCount": tree.count,
            "selection": selectionParity(oid: selectedOid, tree: tree, macRows: macRows),
            "hierarchyTree": tree,
            "hierarchyMacRows": macRows,
            "hierarchyMacSelectedRowCount": selectedMacCount,
            "preview": preview,
            "dashboard": [
                "selectedOid": selectedOid,
                "attributes": [Any](),
                "attributeCount": 0,
            ],
            "paritySource": "handler_fallback",
        ]
    }

    private func sendSyntheticClick(at pointInWindow: CGPoint, on hitView: NSView, in window: NSWindow) -> Bool {
        let clickSel = NSSelectorFromString("triggerClickAction")
        if hitView.responds(to: clickSel) {
            _ = hitView.perform(clickSel)
            NSLog("[AppViewMCP] triggerClickAction %@", className(hitView))
            return true
        }
        var view: NSView? = hitView
        while let current = view {
            if let control = current as? NSControl, control.isEnabled, !control.isHidden {
                control.performClick(nil)
                NSLog("[AppViewMCP] performClick %@ at (%.1f, %.1f)", className(control), pointInWindow.x, pointInWindow.y)
                return true
            }
            view = current.superview
        }
        view = hitView
        while let current = view {
            if current.responds(to: #selector(NSView.mouseDown(with:))),
               current.responds(to: #selector(NSView.mouseUp(with:))) {
                let local = current.convert(pointInWindow, from: nil)
                let down = NSEvent.mouseEvent(
                    with: .leftMouseDown,
                    location: pointInWindow,
                    modifierFlags: [],
                    timestamp: Date.timeIntervalSinceReferenceDate,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 1
                )
                let up = NSEvent.mouseEvent(
                    with: .leftMouseUp,
                    location: pointInWindow,
                    modifierFlags: [],
                    timestamp: Date.timeIntervalSinceReferenceDate,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 0
                )
                if let down, let up {
                    current.mouseDown(with: down)
                    current.mouseUp(with: up)
                    NSLog(
                        "[AppViewMCP] mouseDown/Up %@ local (%.1f, %.1f) window (%.1f, %.1f)",
                        className(current), local.x, local.y, pointInWindow.x, pointInWindow.y
                    )
                    return true
                }
            }
            view = current.superview
        }
        return false
    }

    // MARK: - Helpers

    private func kvc(_ object: NSObject?, _ key: String) -> Any? {
        AVOsAppMCPValueForKey(object, key as NSString)
    }

    private func className(_ object: NSObject) -> String {
        NSStringFromClass(type(of: object))
    }

    private func classNameMatches(_ runtimeName: String, _ shortName: String) -> Bool {
        !runtimeName.isEmpty && !shortName.isEmpty
            && (runtimeName == shortName || runtimeName.hasSuffix(".\(shortName)"))
    }

    private func pointerOid(_ object: NSObject) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(object).toOpaque())
    }

    private func frameJSON(_ rect: NSRect) -> [String: CGFloat] {
        ["x": rect.origin.x, "y": rect.origin.y, "width": rect.size.width, "height": rect.size.height]
    }

    private func string(_ value: Any?) -> String {
        value as? String ?? ""
    }

    private func parseJSON(_ body: Data?) -> [String: Any]? {
        guard let body, !body.isEmpty else { return [:] }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }

    private func doubleValue(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private func integerValue(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private func uintValue(_ value: Any?) -> UInt {
        if let number = value as? NSNumber { return number.uintValue }
        if let text = value as? String { return UInt(text) ?? 0 }
        return 0
    }

    private func boolValue(_ value: Any?) -> Bool {
        (value as? NSNumber)?.boolValue ?? false
    }

    private func wait<T>(timeout: TimeInterval, queue: DispatchQueue, _ work: @escaping () -> T) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?
        queue.async {
            result = work()
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
        return result
    }

    private func pngJSON(image: NSImage, missing: String, encodeFail: String) -> (statusCode: Int, body: Data) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return error(missing, statusCode: 500)
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return error(encodeFail, statusCode: 500)
        }
        return ok([
            "imageBase64": png.base64EncodedString(),
            "mimeType": "image/png",
            "width": image.size.width,
            "height": image.size.height,
        ])
    }

    private func ok(_ data: Any) -> (statusCode: Int, body: Data) {
        (200, successBody(data))
    }

    private func successBody(_ data: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["success": true, "data": data])) ?? Data()
    }

    private func error(_ message: String, statusCode: Int) -> (statusCode: Int, body: Data) {
        let body = (try? JSONSerialization.data(withJSONObject: ["success": false, "error": message])) ?? Data()
        return (statusCode, body)
    }
}
