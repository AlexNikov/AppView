import AppCenterAnalytics
import AppKit
import AppViewShared

private extension AppViewDisplayItem {
    var isExpandedBeforeSearchOrFocus: Bool {
        get { appview_getBindBOOL(forKey: "isExpandedBeforeSearching") }
        set { appview_bindBOOL(newValue, forKey: "isExpandedBeforeSearching") }
    }
}

// MARK: - Search & Focus

extension AVHierarchyDataSource {
    func search(with string: String) {
        guard !string.isEmpty else {
            assertionFailure()
            return
        }

        if state != .search {
            rawFlatItems?.forEach { obj in
                obj.isExpandedBeforeSearchOrFocus = obj.isExpanded
            }
            state = .search
        }

        selectedItem = nil

        let keyShouldShow = "show"
        rawFlatItems?.forEach { displayItem in
            displayItem.appview_bindBOOL(false, forKey: keyShouldShow)
            displayItem.highlightedSearchString = nil
        }

        rawFlatItems?.forEach { displayItem in
            if displayItem.isMatched(withSearchString: string) {
                displayItem.highlightedSearchString = string
                displayItem.enumerateAncestors { ancestor, _ in
                    ancestor.isExpanded = true
                    ancestor.appview_bindBOOL(true, forKey: keyShouldShow)
                }
                displayItem.enumerateSelfAndChildren { selfOrChild in
                    selfOrChild.isExpanded = false
                    selfOrChild.appview_bindBOOL(true, forKey: keyShouldShow)
                }
            }
        }

        let filteredItems = rawFlatItems?.appview_filter { displayItem in
            let shouldShow = displayItem.appview_getBindBOOL(forKey: keyShouldShow)
            if shouldShow {
                displayItem.isInSearch = true
            }
            return shouldShow
        } as? [AppViewDisplayItem]

        flatItems = filteredItems
        didReloadFlatItemsWithSearchOrFocusRelay.accept(())
        buildDisplayingFlatItems()
    }

    func focusDisplayItem(_ item: AppViewDisplayItem) {
        Analytics.trackEvent("Focus")

        if state == .normal {
            rawFlatItems?.forEach { obj in
                obj.isExpandedBeforeSearchOrFocus = obj.isExpanded
            }
        } else if state == .search {
            rawFlatItems?.forEach { obj in
                obj.isInSearch = false
                obj.highlightedSearchString = nil
            }
        }
        state = .focus

        var newFlatItems: [AppViewDisplayItem] = []
        item.enumerateSelfAndChildren { currItem in
            newFlatItems.append(currItem)
        }
        flatItems = newFlatItems
        didReloadFlatItemsWithSearchOrFocusRelay.accept(())
        buildDisplayingFlatItems()
    }

    func endFocus() {
        guard state != .normal else { return }
        state = .normal

        rawFlatItems?.forEach { obj in
            obj.isExpanded = obj.isExpandedBeforeSearchOrFocus
        }

        flatItems = rawFlatItems
        didReloadFlatItemsWithSearchOrFocusRelay.accept(())
        buildDisplayingFlatItems()
    }

    func endSearch() {
        guard state != .normal else { return }
        state = .normal

        rawFlatItems?.forEach { obj in
            obj.isInSearch = false
            obj.highlightedSearchString = nil
            obj.isExpanded = obj.isExpandedBeforeSearchOrFocus
        }

        selectedItem?.enumerateAncestors { item, _ in
            item.isExpanded = true
        }

        flatItems = rawFlatItems
        didReloadFlatItemsWithSearchOrFocusRelay.accept(())
        buildDisplayingFlatItems()
    }
}
