//
//  AVReloadSingleItemUpdateTaskMaker.swift
//  AppViewClient
//

import AppKit
import Foundation
import AppViewShared

final class AVReloadSingleItemUpdateTaskMaker: NSObject {
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

        var tasks: [AppViewStaticAsyncUpdateTask] = []
        if item.doNotFetchScreenshotReason == .permitted {
            var task = taskFromItem(item)
            task.taskType = .groupScreenshot
            tasks.append(task)
            if item.isExpandable {
                var task2 = taskFromItem(item)
                task2.taskType = .soloScreenshot
                tasks.append(task2)
            }
        } else {
            var task = taskFromItem(item)
            task.taskType = .noScreenshot
            tasks.append(task)
        }
        if !tasks.isEmpty {
            tasks[0].needBasisVisualInfo = true
        }
        return tasks
    }

    private static func taskFromItem(_ item: AppViewDisplayItem) -> AppViewStaticAsyncUpdateTask {
        var task = AppViewStaticAsyncUpdateTask()
        task.oid = item.layerObject?.oid ?? 0
        task.frameSize = item.frame.size
        task.clientReadableVersion = AVHelper.appviewReadableVersion()
        return task
    }
}
