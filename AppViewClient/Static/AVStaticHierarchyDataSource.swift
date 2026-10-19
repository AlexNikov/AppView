//
//  AVStaticHierarchyDataSource.swift
//  AppView
//

import AppCenterAnalytics
import AppKit
import Foundation
import AppViewShared
import RxRelay
import RxSwift

final class AVStaticHierarchyDataSource: AVHierarchyDataSource {
    static let sharedInstance = AVStaticHierarchyDataSource()

    private(set) var appInfo: AppViewAppInfo?

    let itemsDidChangeFrameRelay = PublishRelay<AppViewDisplayItem>()
    var itemsDidChangeFrame: Observable<AppViewDisplayItem> {
        itemsDidChangeFrameRelay.asObservable()
    }

    private var shouldIgnoreFastModeAutoUpdate = false
    private var isUsingDanceUI = false
  /// Coalesced while `AVStaticAsyncUpdateManager` is fetching (avoids a second full 3D rebuild mid-batch).
    private var pendingHierarchyPreviewReload = false

    private override init() {
        super.init()
        // ObjC baseline does not refetch on selectedItem KVO — only via buildDisplayingFlatItems.
    }

    /// Drop cached iOS hierarchy when ending an inspect session (MCP reconnect / demo switch).
    func clearSessionHierarchy() {
        rawHierarchyInfo = nil
        rawFlatItems = nil
        flatItems = nil
        displayingFlatItems = nil
        selectedItem = nil
        appInfo = nil
    }

    override func reload(with info: AppViewHierarchyInfo, keepState: Bool) {
        // Wire v2 hierarchy omits appInfo unless the payload includes it — restore for preview centering.
        if info.appInfo == nil, let inspectingAppInfo = AVAppsManager.sharedInstance.inspectingApp?.appInfo {
            info.appInfo = inspectingAppInfo
        }

        // Strip before super.reload — didReloadHierarchyInfo renders 3D from flatItems.
        stripEmbeddedScreenshots(from: info.displayItems)

        super.reload(with: info, keepState: keepState)

        AVConnectionManager.sharedInstance.flushWireScreenshotBuffers(
            on: AVAppsManager.sharedInstance.inspectingApp?.channel
        )

        appInfo = info.appInfo
        guard let appInfo = info.appInfo, appInfo.screenScale > 0 else { return }
        let screenScale = max(appInfo.screenScale, 1)

        let maxLengthInPx = AppViewNodeImageMaxLengthInPx - 100
        for obj in flatItems ?? [] {
            let widthInPx = obj.frame.size.width * screenScale
            let heightInPx = obj.frame.size.height * screenScale
            if widthInPx > maxLengthInPx || heightInPx > maxLengthInPx {
                obj.doNotFetchScreenshotReason = AppViewDoNotFetchScreenshotReason.tooLarge
            }
        }

        updateMessageStatus()

        // Archive screenshots use drawHierarchy and bake descendants — drop all before detail fetch.
        flatItems?.forEach { item in
            item.soloScreenshot = nil
            item.groupScreenshot = nil
        }

        buildDisplayingFlatItems()

        let shouldUpdateAll = AVPreferenceMain().fastMode == false
        if shouldUpdateAll {
            AVStaticAsyncUpdateManager.sharedInstance.updateAll()
        }
    }

    /// Hierarchy archive embeds drawHierarchy screenshots (often with full subtree).
    private func stripEmbeddedScreenshots(from items: [AppViewDisplayItem]?) {
        guard let items else { return }
        for item in items {
            item.soloScreenshot = nil
            item.groupScreenshot = nil
            stripEmbeddedScreenshots(from: item.subitems)
        }
    }

    func modify(with detail: AppViewDisplayItemDetail?) {
        guard let detail else { return }
        guard let displayItem = displayItem(withOid: detail.displayItemOid) else {
            assertionFailure()
            return
        }

        let titleBefore    = displayItem.title()    ?? ""
        let subtitleBefore = displayItem.subtitle() ?? ""

        if let customDisplayTitle = detail.customDisplayTitle,
           !customDisplayTitle.isEmpty,
           customDisplayTitle != displayItem.customDisplayTitle {
            displayItem.customDisplayTitle = customDisplayTitle
        }
        if let danceUISource = detail.danceUISource {
            displayItem.danceuiSource = danceUISource
            if !isUsingDanceUI {
                isUsingDanceUI = true
                Analytics.trackEvent("UseDance")
            }
        }
        var screenshotChanged = false
        if let groupScreenshot = detail.groupScreenshot {
            displayItem.groupScreenshot = groupScreenshot
            screenshotChanged = true
        }
        if let soloScreenshot = detail.soloScreenshot {
            displayItem.soloScreenshot = soloScreenshot
            screenshotChanged = true
        }
        if screenshotChanged {
            refreshPreviewAppearanceUpToRoot(from: displayItem)
        }

        if detail.frameValue != nil || detail.boundsValue != nil {
            modifyDisplayItem(
                displayItem,
                newFrame: detail.frameValue?.rectValue ?? displayItem.frame,
                newBounds: detail.boundsValue?.rectValue ?? displayItem.bounds
            )
        }

        var didChangeHiddenAlpha = false
        if let hiddenValue = detail.hiddenValue, hiddenValue.boolValue != displayItem.isHidden {
            displayItem.isHidden = hiddenValue.boolValue
            didChangeHiddenAlpha = true
        }
        if let alphaValue = detail.alphaValue, alphaValue.floatValue != displayItem.alpha {
            displayItem.alpha = alphaValue.floatValue
            didChangeHiddenAlpha = true
        }
        if didChangeHiddenAlpha {
            itemDidChangeHiddenAlphaValueRelay.accept(displayItem)
        }

        var attrChanged = false
        if let attributesGroupList = detail.attributesGroupList, !attributesGroupList.isEmpty {
            displayItem.attributesGroupList = attributesGroupList
            attrChanged = true
        } else if didChangeHiddenAlpha {
            Self.syncVisibilityAttributes(on: displayItem)
            attrChanged = true
        }
        if let customAttrGroupList = detail.customAttrGroupList, !customAttrGroupList.isEmpty {
            displayItem.customAttrGroupList = customAttrGroupList
            attrChanged = true
        }
        if attrChanged {
            itemDidChangeAttrGroupRelay.accept(displayItem)
        }

        if let subitems = detail.subitems,
           (displayItem.subitems?.count ?? 0) > 0 || subitems.count > 0 {
            shouldIgnoreFastModeAutoUpdate = true

            switch state {
            case .focus:
                endFocus()
            case .search:
                endSearch()
            default:
                break
            }

            let flatItemsBefore = flatItems?.count ?? 0
            let oldSubitemOids = Self.oidList(from: displayItem.subitems)
            NSLog("AVStaticHierarchyDataSource - subitems for oid=%lu count=%d flatItems=%d",
                  detail.displayItemOid, subitems.count, flatItemsBefore)
            var expansionByOid: [UInt: Bool] = [:]
            flatItems?.forEach { item in
                if let oid = item.layerObject?.oid ?? item.viewObject?.oid {
                    expansionByOid[oid] = item.isExpanded
                }
            }

            displayItem.subitems = subitems
            let newRawFlatItems = AppViewDisplayItem.flatItems(
                fromHierarchicalItems: rawHierarchyInfo?.displayItems ?? []
            )
            rawFlatItems = newRawFlatItems
            flatItems = rawFlatItems

            flatItems?.forEach { item in
                if let oid = item.layerObject?.oid ?? item.viewObject?.oid,
                   let wasExpanded = expansionByOid[oid] {
                    item.isExpanded = wasExpanded
                }
            }
            let newSubitemOids = Self.oidList(from: subitems)
            let treeStructureChanged = flatItemsBefore != newRawFlatItems.count
                || oldSubitemOids != newSubitemOids
            NSLog("AVStaticHierarchyDataSource - expansion restored for %d oids", expansionByOid.count)
            AVDebugEventLog.shared.record("modify_subitems", [
                "oid": detail.displayItemOid,
                "subitems_count": subitems.count,
                "flatItems_before": flatItemsBefore,
                "flatItems_after": newRawFlatItems.count,
                "treeStructureChanged": treeStructureChanged,
            ])

            if treeStructureChanged {
                if AVStaticAsyncUpdateManager.sharedInstance.isUpdating {
                    pendingHierarchyPreviewReload = true
                } else {
                    didReloadHierarchyInfoRelay.accept(())
                }
            }

            displayItem.enumerateSelfAndChildren { obj in
                if obj === displayItem { return }
                if !obj.isUserCustom(), !obj.shouldCaptureImage {
                    obj.enumerateSelfAndChildren { item in
                        item.noPreview = true
                        item.doNotFetchScreenshotReason = .userConfig
                    }
                }
                if let danceSource = obj.customInfo?.danceuiSource, !danceSource.isEmpty {
                    AVDanceUIAttrMaker.makeDanceUIJumpAttribute(obj, danceSource: danceSource)
                }
            }
            buildDisplayingFlatItems()
            shouldIgnoreFastModeAutoUpdate = false
        }

        let titleAfter    = displayItem.title()    ?? ""
        let subtitleAfter = displayItem.subtitle() ?? ""
        if titleBefore != titleAfter || subtitleBefore != subtitleAfter {
            NSLog("AVStaticHierarchyDataSource - title changed oid=%lu '%@'|'%@' → '%@'|'%@'",
                  detail.displayItemOid, titleBefore, subtitleBefore, titleAfter, subtitleAfter)
            AVDebugEventLog.shared.record("title_changed", [
                "oid": detail.displayItemOid,
                "title_before": titleBefore, "title_after": titleAfter,
                "subtitle_before": subtitleBefore, "subtitle_after": subtitleAfter,
            ])
        }

        AVVerifyCustomInfoLogger.logDetailModify(detail: detail, displayItem: displayItem)
    }

    override func buildDisplayingFlatItems() {
        super.buildDisplayingFlatItems()
        let fastMode = AVPreferenceMain().fastMode
        AVVerifyCustomInfoLogger.logAsyncUpdate(
            "buildDisplayingFlatItems count=\(displayingFlatItems?.count ?? 0) fastMode=\(fastMode) ignoreAuto=\(shouldIgnoreFastModeAutoUpdate)"
        )
        if ProcessInfo.processInfo.environment["APPVIEW_VERIFY_LOG"] != nil {
            if !shouldIgnoreFastModeAutoUpdate {
                AVStaticAsyncUpdateManager.sharedInstance.updateForDisplayingItems()
            }
            return
        }
        if fastMode, !shouldIgnoreFastModeAutoUpdate {
            AVStaticAsyncUpdateManager.sharedInstance.updateForDisplayingItems()
        }
    }

    override func preferenceManager() -> AVPreferenceManager {
        AVPreferenceMain()
    }

    override func isReadOnly() -> Bool {
        false
    }

    private func modifyDisplayItem(
        _ item: AppViewDisplayItem,
        newFrame: CGRect,
        newBounds: CGRect
    ) {
        if item.frame == newFrame, item.bounds == newBounds {
            return
        }
        item.frame = newFrame
        item.bounds = newBounds
        itemsDidChangeFrameRelay.accept(item)
    }

    private func updateMessageStatus() {
        if serverSideIsSwiftProject, appInfo?.swiftEnabledInAppViewServer == -1 {
            AVMessageManager.sharedInstance.addMessage(AVMessage_SwiftSubspec)
        } else {
            AVMessageManager.sharedInstance.removeMessage(AVMessage_SwiftSubspec)
        }

        if queryIfUsingNewestServerVersion() {
            AVMessageManager.sharedInstance.removeMessage(AVMessage_NewServerVersion)
        } else {
            AVMessageManager.sharedInstance.addMessage(AVMessage_NewServerVersion)
        }
    }

    func consumePendingHierarchyPreviewReload() -> Bool {
        let pending = pendingHierarchyPreviewReload
        pendingHierarchyPreviewReload = false
        return pending
    }

    /// Parent planes in 3D hide texture when children load; refresh ancestors after each screenshot chunk.
    private func refreshPreviewAppearanceUpToRoot(from item: AppViewDisplayItem) {
        item.enumerateSelfAndAncestors { ancestor, _ in
            (ancestor.previewNode as? AVDisplayItemNode)?.refreshPreviewAppearance()
        }
    }

    private static func oidList(from items: [AppViewDisplayItem]?) -> [UInt] {
        (items ?? []).map { $0.viewObject?.oid ?? $0.layerObject?.oid ?? 0 }
    }

    /// Patch/detail chunks may update `isHidden`/`alpha` without resending full attr groups.
    private static func syncVisibilityAttributes(on displayItem: AppViewDisplayItem) {
        for group in displayItem.queryAllAttrGroupList() {
            for section in group.attrSections ?? [] {
                for attr in section.attributes ?? [] {
                    guard let id = attr.identifier else { continue }
                    if id == AppViewAttr_ViewLayer_Visibility_Hidden {
                        attr.value = .bool(displayItem.isHidden)
                    } else if id == AppViewAttr_ViewLayer_Visibility_Opacity {
                        attr.value = .double(Double(displayItem.alpha))
                    }
                }
            }
        }
    }

    private func queryIfUsingNewestServerVersion() -> Bool {
        let newestVersion = AVServerVersionRequestor.shared.query() ?? ""
        if newestVersion.isEmpty {
            return true
        }
        guard let appInfo else { return false }
        let userVersion = appInfo.serverReadableVersion
        Analytics.trackEvent("ServerVersion", withProperties: ["version": userVersion ?? ""])
        return AVVersionComparer.compare(withNewest: newestVersion, user: userVersion ?? "")
    }
}
