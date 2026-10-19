//
//  AppViewUITestSupport.swift
//  AppView
//

import AppKit
import AppViewShared

enum AppViewUITestSupport {
    static let inspectorWindowWidth: CGFloat = 1280
    static let inspectorWindowHeight: CGFloat = 800
    static let minimumFlatItemsForReady = 5
    static let previewStructureAccessibilityID = "appview.uitest.preview.structure"
    private static let previewStructureSeparator = "\u{001E}"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-AppViewUITest")
            || ProcessInfo.processInfo.environment["APPVIEW_UI_TEST"] == "1"
    }

    static var shouldShowHiddenItems: Bool {
        ProcessInfo.processInfo.environment["APPVIEW_UI_TEST_SHOW_HIDDEN"] == "1"
    }

    static func applyLaunchConfiguration() {
        guard isEnabled else { return }
        NSApp.appearance = NSAppearance(named: .aqua)
        if shouldShowHiddenItems {
            AVPreferenceMain().showHiddenItems = true
        } else {
            AVPreferenceMain().showHiddenItems = false
        }
    }

    static func inspectorContentSize() -> NSSize {
        NSSize(width: inspectorWindowWidth, height: inspectorWindowHeight)
    }

    static func startInspectorReadinessObserver() {
        guard isEnabled else { return }
        var pollCount = 0
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            pollCount += 1
            updateInspectorReadinessIfNeeded()
            let value = AVNavigationManager.sharedInstance.staticWindowController?.window?.accessibilityValue() as? String
            if value == "ready" || pollCount >= 120 {
                timer.invalidate()
            }
        }
    }

    static func updateInspectorReadinessIfNeeded() {
        guard isEnabled else { return }
        let dataSource = AVStaticHierarchyDataSource.sharedInstance
        guard let windowController = AVNavigationManager.sharedInstance.staticWindowController else { return }
        guard let window = windowController.window else { return }
        let flatCount = dataSource.flatItems?.count ?? 0
        let fetching = windowController.mcpFetchingHierarchy || windowController.mcpFetchingDetails
        if flatCount >= minimumFlatItemsForReady && !fetching {
            if shouldShowHiddenItems {
                AVPreferenceMain().showHiddenItems = true
                AVPreviewView.sharedForMCP?.showHiddenItems = true
            } else {
                AVPreviewView.sharedForMCP?.showHiddenItems = false
            }
            window.setAccessibilityValue("ready")
            publishPreviewStructureIfNeeded()
        } else {
            window.setAccessibilityValue("loading")
        }
    }

    static func publishPreviewStructureIfNeeded() {
        guard isEnabled else { return }
        guard let previewView = AVPreviewView.sharedForMCP else { return }
        if shouldShowHiddenItems {
            previewView.showHiddenItems = true
        } else {
            previewView.showHiddenItems = false
        }
        let state = previewView.mcpPreviewStateDictionary()
        let nodeCount = state["displayItemNodesCount"] as? Int ?? 0
        guard nodeCount > 0 else { return }

        var lines = AppViewPreviewStructureExporter.normalizedLines(from: state)
        let hiddenTitles = previewView.appviewUITestVisibleHiddenPreviewTitles()
        lines.append("hiddenPreviewTitles=\(hiddenTitles.joined(separator: ","))")
        guard !lines.isEmpty else { return }

        guard let previewHost = AVNavigationManager.sharedInstance.staticWindowController?
            .viewController.viewsPreviewController.view else { return }

        previewHost.setAccessibilityElement(true)
        previewHost.setAccessibilityIdentifier(previewStructureAccessibilityID)
        previewHost.setAccessibilityValue(lines.joined(separator: previewStructureSeparator))
    }
}
