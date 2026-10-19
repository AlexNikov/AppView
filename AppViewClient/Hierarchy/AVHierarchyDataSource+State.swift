import AppViewShared
import RxRelay
import RxSwift

// MARK: - State & item relays

extension AVHierarchyDataSource {
    var stateObservable: Observable<AVHierarchyDataSourceState> {
        stateRelay.asObservable()
    }

    var state: AVHierarchyDataSourceState {
        get { stateRelay.value }
        set {
            guard newValue != stateRelay.value else { return }
            stateRelay.accept(newValue)
        }
    }

    var displayingFlatItemsObservable: Observable<[AppViewDisplayItem]?> {
        displayingFlatItemsRelay.asObservable()
    }

    var displayingFlatItems: [AppViewDisplayItem]? {
        get { displayingFlatItemsRelay.value }
        set { displayingFlatItemsRelay.accept(newValue) }
    }

    var rawHierarchyInfoObservable: Observable<AppViewHierarchyInfo?> {
        rawHierarchyInfoRelay.asObservable()
    }

    var rawHierarchyInfo: AppViewHierarchyInfo? {
        get { rawHierarchyInfoRelay.value }
        set { rawHierarchyInfoRelay.accept(newValue) }
    }
}
