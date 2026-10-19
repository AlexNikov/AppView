import AppKit
import AppViewShared

// MARK: - Expansion

extension AVHierarchyDataSource {
    func adjustExpansionByIndex(
        _ index: Int,
        referenceDict: [NSNumber: NSNumber]?,
        selectedItem outputSelectedItem: UnsafeMutablePointer<AppViewDisplayItem?>?
    ) {
        AVDebugEventLog.shared.record("adjust_expansion", [
            "index": index,
            "hasReferenceDict": referenceDict != nil,
        ])
        var index = index
        if index < 0 || index > 4 {
            assertionFailure("adjustExpansionByIndex, index 为 \(index)")
            index = max(min(index, 4), 0)
        }

        preferenceManager().expansionIndex = index

        var expandedCount = flatItems?.count ?? 0
        flatItems?.forEach { obj in
            obj.hasDeterminedExpansion = false

            if !obj.isExpandable {
                obj.hasDeterminedExpansion = true
                expandedCount -= 1
                return
            }

            if let referenceDict,
               let oid = obj.layerObject?.oid,
               let prevState = referenceDict[NSNumber(value: oid)] {
                obj.isExpanded = prevState.boolValue
                obj.hasDeterminedExpansion = true
                if !obj.isExpanded {
                    expandedCount -= 1
                }
            }
        }

        if index == 0 {
            var preferedSelectedItem: AppViewDisplayItem?
            flatItems?.forEach { obj in
                if obj.hasDeterminedExpansion { return }
                obj.isExpanded = false
                if obj.representedAsKeyWindow {
                    preferedSelectedItem = obj
                }
            }
            outputSelectedItem?.pointee = preferedSelectedItem

        } else if index == 4 {
            flatItems?.forEach { obj in
                if obj.hasDeterminedExpansion { return }
                if obj.inNoPreviewHierarchy {
                    obj.isExpanded = false
                    return
                }
                obj.isExpanded = true
            }

            if outputSelectedItem != nil {
                var preferedSelectedItem: AppViewDisplayItem?
                let keyWindowRootItem = rawHierarchyInfo?.displayItems?.first { $0.representedAsKeyWindow }

                if let keyWindowRootItem {
                    let keyWindowFlatItems = AppViewDisplayItem.flatItems(fromHierarchicalItems: [keyWindowRootItem])
                    for obj in keyWindowFlatItems.reversed() {
                        if obj.hostViewControllerObject != nil {
                            preferedSelectedItem = obj
                            break
                        }
                    }
                }
                outputSelectedItem?.pointee = preferedSelectedItem
            }

        } else {
            var keyWindowItem = rawHierarchyInfo?.displayItems?.first { $0.representedAsKeyWindow }
            if keyWindowItem == nil {
                keyWindowItem = rawHierarchyInfo?.displayItems?.first
            }

            rawHierarchyInfo?.displayItems?.forEach { windowItem in
                if windowItem === keyWindowItem { return }
                let windowFlatItems = AppViewDisplayItem.flatItems(fromHierarchicalItems: [windowItem])
                windowFlatItems.forEach { obj in
                    if obj.hasDeterminedExpansion { return }
                    obj.isExpanded = false
                    obj.hasDeterminedExpansion = true
                }
            }

            let uiTransitionViewItems = (keyWindowItem?.subitems as? [AppViewDisplayItem])?.appview_filter { obj in
                obj.title() == "UITransitionView"
            } as? [AppViewDisplayItem] ?? []

            for (idx, obj) in uiTransitionViewItems.enumerated() {
                if obj.hasDeterminedExpansion { continue }
                if idx == uiTransitionViewItems.count - 1 {
                    obj.isExpanded = true
                } else {
                    obj.isExpanded = false
                }
                obj.hasDeterminedExpansion = true
            }

            var viewControllerItems: [AppViewDisplayItem] = []
            if let keyWindowItem {
                let keyWindowFlatItems = AppViewDisplayItem.flatItems(fromHierarchicalItems: [keyWindowItem])
                for obj in keyWindowFlatItems {
                    if obj.hostViewControllerObject != nil {
                        viewControllerItems.append(obj)
                        continue
                    }
                    if obj.hasDeterminedExpansion { continue }
                    if obj.inNoPreviewHierarchy || obj.preferToBeCollapsed
                        || (!AVPreferenceMain().showHiddenItems && obj.inHiddenHierarchy) {
                        obj.isExpanded = false
                        obj.hasDeterminedExpansion = true
                        continue
                    }
                    if obj.itemIsKindOfClasses(withNames: ["UINavigationBar", "UITabBar"]) {
                        obj.enumerateSelfAndChildren { item in
                            if item.hasDeterminedExpansion { return }
                            item.isExpanded = false
                            item.hasDeterminedExpansion = true
                        }
                    }
                }
            }

            outputSelectedItem?.pointee = viewControllerItems.last

            if index == 1 {
                for viewControllerItem in viewControllerItems.reversed() {
                    viewControllerItem.enumerateSelfAndAncestors { item, _ in
                        if item.hasDeterminedExpansion { return }
                        item.isExpanded = item !== viewControllerItem
                        item.hasDeterminedExpansion = true
                    }
                }
                flatItems?.forEach { obj in
                    if obj.hasDeterminedExpansion { return }
                    obj.isExpanded = false
                }

            } else if index == 2 {
                for viewControllerItem in viewControllerItems.reversed() {
                    viewControllerItem.enumerateAncestors { item, _ in
                        if item.hasDeterminedExpansion { return }
                        item.isExpanded = true
                        item.hasDeterminedExpansion = true
                    }

                    let hasTableOrCollectionView = viewControllerItem.subitems?.first?
                        .itemIsKindOfClasses(withNames: ["UITableView", "UICollectionView"]) ?? false
                    let indentsForward: Int = hasTableOrCollectionView ? 2 : 3

                    viewControllerItem.enumerateSelfAndChildren { item in
                        if item.hasDeterminedExpansion { return }
                        if item.indentLevel() < viewControllerItem.indentLevel() + indentsForward {
                            item.isExpanded = true
                            item.hasDeterminedExpansion = true
                        }
                    }
                }
                flatItems?.forEach { obj in
                    if obj.hasDeterminedExpansion { return }
                    obj.isExpanded = false
                }

            } else if index == 3 {
                flatItems?.forEach { obj in
                    if obj.hasDeterminedExpansion { return }
                    obj.isExpanded = true
                    obj.hasDeterminedExpansion = true
                }
            }
        }

        buildDisplayingFlatItems()
    }

    func collapseItem(_ item: AppViewDisplayItem) {
        guard item.isExpandable, item.isExpanded else { return }
        let oid = item.layerObject?.oid ?? item.viewObject?.oid ?? 0
        NSLog("AVHierarchyDataSource - collapseItem oid=%lu title=%@", UInt(oid), item.title() ?? "?")
        AVDebugEventLog.shared.record("collapse", ["oid": UInt(oid), "title": item.title() ?? ""])
        item.isExpanded = false
        buildDisplayingFlatItems()
        reconcileSelectedItemAfterExpansionChange()
    }

    func expandItem(_ item: AppViewDisplayItem) {
        guard item.isExpandable, !item.isExpanded else { return }
        let oid = item.layerObject?.oid ?? item.viewObject?.oid ?? 0
        NSLog("AVHierarchyDataSource - expandItem oid=%lu title=%@", UInt(oid), item.title() ?? "?")
        AVDebugEventLog.shared.record("expand", ["oid": UInt(oid), "title": item.title() ?? "?"])
        item.isExpanded = true
        buildDisplayingFlatItems()
        reconcileSelectedItemAfterExpansionChange()
    }

    func expandToShowItem(_ item: AppViewDisplayItem) {
        item.enumerateAncestors { targetItem, _ in
            if !targetItem.isExpanded {
                targetItem.isExpanded = true
            }
        }
        buildDisplayingFlatItems()
    }

    func expandItemsRooted(by item: AppViewDisplayItem) {
        if item.preferToBeCollapsed {
            item.enumerateSelfAndChildren { targetItem in
                if targetItem.isExpandable, !targetItem.isExpanded {
                    targetItem.isExpanded = true
                }
            }
        } else {
            item.enumerateSelfAndChildren { targetItem in
                if targetItem.isExpandable, !targetItem.isExpanded, !targetItem.preferToBeCollapsed {
                    targetItem.isExpanded = true
                }
            }
        }
        buildDisplayingFlatItems()
    }

    func collapseAllChildren(of item: AppViewDisplayItem) {
        item.enumerateSelfAndChildren { enumeratedItem in
            if enumeratedItem === item { return }
            guard enumeratedItem.isExpandable, enumeratedItem.isExpanded else { return }
            enumeratedItem.isExpanded = false
        }
        buildDisplayingFlatItems()
        reconcileSelectedItemAfterExpansionChange()
    }

    func reconcileSelectedItemAfterExpansionChange() {
        if let pinned = appview_verifyPinnedSelection(in: displayingFlatItems) {
            selectedItem = pinned
            return
        }
        guard let selected = selectedItem else { return }
        if selected.displayingInHierarchy { return }

        var candidate: AppViewDisplayItem? = selected
        while let item = candidate, !item.displayingInHierarchy {
            candidate = item.superItem
        }
        if let candidate, candidate.displayingInHierarchy, candidate !== selected {
            selectedItem = candidate
        } else if !selected.displayingInHierarchy {
            selectedItem = displayingFlatItems?.first
        }
    }
}
