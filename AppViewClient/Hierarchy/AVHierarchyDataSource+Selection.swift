import AppKit
import AppViewShared
import RxRelay
import RxSwift

// MARK: - Selection & hover

extension AVHierarchyDataSource {
    var selectedItemObservable: Observable<AppViewDisplayItem?> {
        selectedItemTick
            .startWith(())
            .map { [weak self] in self?._selectedItem }
            .distinctUntilChanged { $0 === $1 }
    }

    var selectedItem: AppViewDisplayItem? {
        get { _selectedItem }
        set { updateSelectedItem(newValue) }
    }

    var hoveredItemObservable: Observable<AppViewDisplayItem?> {
        hoveredItemTick
            .startWith(())
            .map { [weak self] in self?._hoveredItem }
            .distinctUntilChanged { $0 === $1 }
    }

    var hoveredItem: AppViewDisplayItem? {
        get { _hoveredItem }
        set { updateHoveredItem(newValue) }
    }

    func updateSelectedItem(_ newValue: AppViewDisplayItem?) {
        if _selectedItem === newValue { return }
        let prevSelected = _selectedItem
        _selectedItem = newValue
        prevSelected?.notifySelectionChangeToDelegates()
        _selectedItem?.notifySelectionChangeToDelegates()
        selectedItemTick.accept(())
        AVUserActionManager.sharedInstance.send(.selectedItemChange)
        if NSColorPanel.sharedColorPanelExists {
            NSColorPanel.shared.close()
        }
        if newValue == nil,
           preferenceManager().measureState != .no {
            preferenceManager().measureState = .no
        }
    }

    func updateHoveredItem(_ newValue: AppViewDisplayItem?) {
        if _hoveredItem === newValue { return }
        let prevHovered = _hoveredItem
        _hoveredItem = newValue
        prevHovered?.notifyHoverChangeToDelegates()
        _hoveredItem?.notifyHoverChangeToDelegates()
        hoveredItemTick.accept(())
    }

    /// Golden hierarchy verify expects the MCPSample root `UIView` row, not a child label.
    func appview_verifyPinnedSelection(in items: [AppViewDisplayItem]?) -> AppViewDisplayItem? {
        guard ProcessInfo.processInfo.environment["APPVIEW_VERIFY"] == "1" else { return nil }
        return items?.first {
            ($0.title() ?? "") == "UIView" && ($0.subtitle() ?? "") == "SampleViewController.view"
        }
    }
}
