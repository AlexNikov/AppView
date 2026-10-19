import AppKit
import AppViewShared

// MARK: - KeyDown

extension AVHierarchyDataSource {
    func keyDown(_ event: NSEvent) -> Bool {
        guard let currentItem = selectedItem else { return false }
        let selectedRowIdx = displayingFlatItems?.firstIndex(of: currentItem) ?? NSNotFound
        if selectedRowIdx == NSNotFound { return false }

        guard let displayingFlatItems else { return false }

        switch event.keyCode {
        case 125:
            let nextRow = selectedRowIdx + 1
            if displayingFlatItems.appview_hasIndex(nextRow) {
                selectedItem = displayingFlatItems[nextRow]
                return true
            }
        case 126:
            let prevRow = selectedRowIdx - 1
            if displayingFlatItems.appview_hasIndex(prevRow) {
                selectedItem = displayingFlatItems[prevRow]
                return true
            }
        case 123:
            if currentItem.isExpandable, currentItem.isExpanded {
                collapseItem(currentItem)
                return true
            } else if let superItem = currentItem.superItem,
                      displayingFlatItems.contains(superItem) {
                collapseItem(superItem)
                selectedItem = superItem
                return true
            }
        case 124:
            if currentItem.isExpandable, !currentItem.isExpanded {
                expandItem(currentItem)
                return true
            } else {
                for i in (selectedRowIdx + 1)..<displayingFlatItems.count {
                    let next = displayingFlatItems[i]
                    if !next.inHiddenHierarchy {
                        selectedItem = next
                        return true
                    }
                }
            }
        default:
            break
        }

        return false
    }
}
