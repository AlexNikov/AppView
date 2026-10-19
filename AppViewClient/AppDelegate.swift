//
//  AppDelegate.swift
//  AppView
//

import AppCenter
import AppCenterAnalytics
import AppCenterCrashes
import AppKit
import AppViewMacMCP
import AppViewShared
import RxSwift

class AppDelegate: NSObject, NSApplicationDelegate {
    private var launchedToOpenFile = false
    private let disposeBag = DisposeBag()

    func applicationWillFinishLaunching(_ notification: Notification) {
        AVAppMenuManager.sharedInstance().setup()
        AVOsAppMCPServerSwift.shared.start(onPort: 47192, dataSource: self)

        AVPreferenceMain().appearanceTypeObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { _, type in
                switch type {
                case .dark:
                    NSApp.appearance = NSAppearance(named: .darkAqua)
                case .light:
                    NSApp.appearance = NSAppearance(named: .aqua)
                case .system:
                    NSApp.appearance = nil
                @unknown default:
                    NSApp.appearance = nil
                }
            }
            .disposed(by: disposeBag)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AVOsAppMCPServerSwift.shared.start(onPort: 47192, dataSource: self)
        _ = AVConnectionManager.sharedInstance

        if AppViewUITestSupport.isEnabled {
            AppViewUITestSupport.applyLaunchConfiguration()
            if !launchedToOpenFile {
                AVNavigationManager.sharedInstance.showLaunch()
            }
            AppViewUITestSupport.startInspectorReadinessObserver()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.openInspectorForUITestIfNeeded()
            }
        } else if !launchedToOpenFile {
            AVNavigationManager.sharedInstance.showLaunch()
        }

        if AppViewUITestSupport.isEnabled {
            AppCenter.enabled = false
        } else if let key = resolveAppCenterKey() {
            AppCenter.start(withAppSecret: key, services: [
                Analytics.self,
                Crashes.self,
            ])
            AppCenter.enabled = AVPreferenceMain().enableReport
        } else {
            AppCenter.enabled = false
        }

        #if DEBUG
        runTests()
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openExportedHierarchy(atPath: filename)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.isFileURL {
            _ = openExportedHierarchy(atPath: url.path)
        }
    }

    @discardableResult
    private func openExportedHierarchy(atPath path: String) -> Bool {
        launchedToOpenFile = true
        var error: NSError?
        let isSuccessful = AVNavigationManager.sharedInstance.showReader(
            withFilePath: path,
            error: &error
        )
        if !isSuccessful {
            AlertError(error ?? AVAppViewClientErrors.inner, NSApp.keyWindow)
        }
        return isSuccessful
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AVAppsManager.sharedInstance.endInspectingSession()
        AppViewDiagLog.log("client applicationWillTerminate — released Peertalk")
        let tempImageFilesToDelete = AVHelper.sharedInstance.tempImageFiles ?? []
        if tempImageFilesToDelete.count == 0 {
            return .terminateNow
        }
        for case let path as String in tempImageFilesToDelete {
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                assertionFailure()
            }
        }
        return .terminateNow
    }

    private func resolveAppCenterKey() -> String? {
        let bundleID = Bundle.main.bundleIdentifier
        if bundleID == "hughkli.AppView" {
            return "fce2565c-518c-4851-be73-fa8317dd1590"
        }
        assertionFailure()
        return nil
    }

    private func openInspectorForUITestIfNeeded() {
        DispatchQueue.main.async {
            let nav = AVNavigationManager.sharedInstance
            if nav.staticWindowController?.window?.isVisible == true {
                if AVStaticHierarchyDataSource.sharedInstance.rawHierarchyInfo != nil {
                    nav.staticWindowController?.mcpForceReload()
                }
                return
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

    private func runTests() {
        let allGroupIDs = AppViewDashboardBlueprint.groupIDs()
        let allGroupIDsUnique = Set(allGroupIDs)
        if allGroupIDs.count != allGroupIDsUnique.count {
            assertionFailure()
        }

        var allSecIDs: [AppViewAttrSectionIdentifier] = []
        for groupID in allGroupIDs {
            let secIDs = AppViewDashboardBlueprint.sectionIDs(forGroupID: groupID)
            allSecIDs.append(contentsOf: secIDs)
        }
        let allSecIDsUnique = Set(allSecIDs)
        if allSecIDs.count != allSecIDsUnique.count {
            assertionFailure()
        }

        var allAttrIDs: [AppViewAttrIdentifier] = []
        for secID in allSecIDs {
            let attrIDs = AppViewDashboardBlueprint.attrIDs(forSectionID: secID)
            allAttrIDs.append(contentsOf: attrIDs)
        }
        let allAttrIDsUnique = Set(allAttrIDs)
        if allAttrIDs.count != allAttrIDsUnique.count {
            assertionFailure()
        }
    }
}
