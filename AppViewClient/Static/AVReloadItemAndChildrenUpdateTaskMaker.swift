//
//  AVReloadItemAndChildrenUpdateTaskMaker.swift
//  AppViewClient
//

import AppKit
import Foundation
import AppViewShared

final class AVReloadItemAndChildrenUpdateTaskMaker: NSObject {
    static func make(with item: AppViewDisplayItem?) -> [AppViewStaticAsyncUpdateTask]? {
        guard let item, !AVStaticAsyncUpdateManager.sharedInstance.isUpdating else {
            assertionFailure()
            return nil
        }
        let serverVersion = AVAppsManager.sharedInstance.inspectingApp?.appInfo?.serverReadableVersion
        let supported = AVVersionComparer.compare(
            withExpectedVersion: "1.2.7",
            realVersion: serverVersion ?? ""
        )
        if !supported {
            let title = NSLocalizedString("Operation failed.", comment: "")
            let detail = NSLocalizedString(
                "Please upgrade the AppViewServer SDK version in your iOS project to 1.2.7 or higher.",
                comment: ""
            )
            let error = AppViewErrorMake(title, detail)
            if let window = NSApplication.shared.keyWindow {
                NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
            }
            return nil
        }

        var task = AppViewStaticAsyncUpdateTask()
        guard let layerObject = item.layerObject else { return nil }
        task.oid = layerObject.oid
        task.taskType = .noScreenshot
        task.attrRequest = .notNeed
        task.needBasisVisualInfo = true
        task.needSubitems = true
        task.frameSize = item.frame.size
        task.clientReadableVersion = AVHelper.appviewReadableVersion()
        return [task]
    }
}
