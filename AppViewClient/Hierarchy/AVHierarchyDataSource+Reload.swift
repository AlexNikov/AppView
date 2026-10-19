import AppCenterAnalytics
import AppKit
import AppViewShared

// MARK: - Reload

extension AVHierarchyDataSource {
    func performReload(with info: AppViewHierarchyInfo, keepState: Bool) {
        AVDebugEventLog.shared.record("reload", [
            "keepState": keepState,
            "flatItems": flatItems?.count ?? 0,
        ])
        rawHierarchyInfo = info
        willReloadHierarchyInfo.accept(())

        if !(info.colorAlias?.isEmpty ?? true) {
            AVPreferenceMain().receivingConfigTime_Color = Date().timeIntervalSince1970
        }
        if !(info.collapsedClassList?.isEmpty ?? true) {
            AVPreferenceMain().receivingConfigTime_Class = Date().timeIntervalSince1970
        }

        var prevSelectedOid: UInt = 0
        var prevExpansionMap: [NSNumber: NSNumber]?
        var preservedAttrGroupsByOid: [UInt: (attrs: [AppViewAttributesGroup]?, custom: [AppViewAttributesGroup]?)] = [:]
        if keepState, let selectedItem {
            prevSelectedOid = selectedItem.layerObject?.oid ?? selectedItem.viewObject?.oid ?? 0
            prevExpansionMap = [:]
            flatItems?.forEach { obj in
                if let oid = obj.layerObject?.oid ?? obj.viewObject?.oid {
                    prevExpansionMap?[NSNumber(value: oid)] = NSNumber(value: obj.isExpanded)
                    let hasAttrs = !(obj.attributesGroupList?.isEmpty ?? true)
                        || !(obj.customAttrGroupList?.isEmpty ?? true)
                    if hasAttrs {
                        preservedAttrGroupsByOid[oid] = (
                            attrs: obj.attributesGroupList?.map { $0.duplicated() },
                            custom: obj.customAttrGroupList?.map { $0.duplicated() }
                        )
                    }
                }
            }
        }

        setUpColors()

        rawFlatItems = AppViewDisplayItem.flatItems(fromHierarchicalItems: info.displayItems ?? [])
        let flatItemsCopy = rawFlatItems ?? []

        var classesPreferredToCollapse: Set<String> = [
            "UILabel", "UIPickerView", "UIProgressView", "UIActivityIndicatorView", "UIAlertView",
            "UIActionSheet", "UISearchBar", "UIButton", "UITextView", "UIDatePicker", "UIPageControl",
            "UISegmentedControl", "UITextField", "UISlider", "UISwitch", "UIVisualEffectView",
            "UIImageView", "WKCommonWebView", "UITextEffectsWindow",
        ]
        if let collapsedClassList = info.collapsedClassList {
            classesPreferredToCollapse.formUnion(collapsedClassList)
        }

        let classesWithNoPreview: Set<String> = ["UITextEffectsWindow", "UIRemoteKeyboardWindow"]

        var hasCustomSubviews = false
        var hasCustomAttrs = false

        for obj in flatItemsCopy {
            if obj.itemIsKindOfClasses(withNames: classesPreferredToCollapse) {
                obj.enumerateSelfAndChildren { item in
                    item.preferToBeCollapsed = true
                }
            }

            if obj.indentLevel() == 0, obj.itemIsKindOfClasses(withNames: classesWithNoPreview) {
                obj.noPreview = true
            }

            if !obj.isUserCustom(), !obj.shouldCaptureImage {
                obj.enumerateSelfAndChildren { item in
                    item.noPreview = true
                    item.doNotFetchScreenshotReason = .userConfig
                }
            }

            if !serverSideIsSwiftProject,
               let className = obj.displayingObject()?.lk_completedDemangledClassName,
               className.contains(".") {
                serverSideIsSwiftProject = true
            }

            if (obj.customInfo?.danceuiSource?.count ?? 0) > 0, let danceSource = obj.customInfo?.danceuiSource {
                AVDanceUIAttrMaker.makeDanceUIJumpAttribute(obj, danceSource: danceSource)
            }

            if obj.isUserCustom() { hasCustomSubviews = true }
            if (obj.customAttrGroupList?.count ?? 0) > 0 { hasCustomAttrs = true }
        }

        Analytics.trackEvent("CustomSubview", withProperties: ["Has": hasCustomSubviews ? "True" : "False"])
        Analytics.trackEvent("CustomAttrs", withProperties: ["Has": hasCustomAttrs ? "True" : "False"])

        if keepState, !preservedAttrGroupsByOid.isEmpty {
            for obj in flatItemsCopy {
                guard let oid = obj.layerObject?.oid ?? obj.viewObject?.oid,
                      let preserved = preservedAttrGroupsByOid[oid] else { continue }
                if obj.attributesGroupList?.isEmpty ?? true,
                   let attrs = preserved.attrs, !attrs.isEmpty {
                    obj.attributesGroupList = attrs
                }
                if obj.customAttrGroupList?.isEmpty ?? true,
                   let custom = preserved.custom, !custom.isEmpty {
                    obj.customAttrGroupList = custom
                }
            }
        }

        flatItems = flatItemsCopy

        var shouldSelectedItem: AppViewDisplayItem?
        if keepState, let prevSelectedItem = displayItem(withOid: prevSelectedOid) {
            shouldSelectedItem = prevSelectedItem
        }

        var expansionIndex = preferenceManager().expansionIndex
        if ProcessInfo.processInfo.environment["APPVIEW_VERIFY_LOG"] != nil {
            expansionIndex = max(expansionIndex, 3)
            if shouldSelectedItem == nil {
                shouldSelectedItem = flatItemsCopy.first { ($0.title() ?? "").hasPrefix("UIView") }
                    ?? flatItemsCopy.first
            }
        }
        if (flatItems?.count ?? 0) > 300, expansionIndex > 2 {
            expansionIndex = 2
        }

        if shouldSelectedItem != nil {
            adjustExpansionByIndex(
                expansionIndex,
                referenceDict: keepState ? prevExpansionMap : nil,
                selectedItem: nil
            )
        } else {
            adjustExpansionByIndex(
                expansionIndex,
                referenceDict: keepState ? prevExpansionMap : nil,
                selectedItem: &shouldSelectedItem
            )
        }

        if (flatItems?.count ?? 0) > 20,
           (displayingFlatItems?.count ?? 0) < 10,
           expansionIndex > 1 {
            NSLog("adjust expansion again")
            adjustExpansionByIndex(expansionIndex, referenceDict: nil, selectedItem: nil)
        }

        if shouldSelectedItem == nil {
            shouldSelectedItem = flatItems?.first
        }
        if let pinned = appview_verifyPinnedSelection(in: flatItems) {
            shouldSelectedItem = pinned
        }
        selectedItem = shouldSelectedItem

        if state != .normal {
            state = .normal
        }

        lastReloadKeptState = keepState
        didReloadHierarchyInfoRelay.accept(())

        if !keepState {
            AVVerifyCustomInfoLogger.logHierarchyReload(
                flatItems: flatItems ?? [],
                displayingCount: displayingFlatItems?.count ?? 0,
                selectedItem: selectedItem
            )
        }
    }
}
