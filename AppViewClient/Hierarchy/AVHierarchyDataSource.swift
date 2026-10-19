//
//  AVHierarchyDataSource.swift
//  AppView
//

import AppKit
import AppViewShared
import RxRelay
import RxSwift

enum AVHierarchyDataSourceState: UInt {
    case normal
    case search
    case focus
}

class AVHierarchyDataSource: NSObject {
    let stateRelay = BehaviorRelay<AVHierarchyDataSourceState>(value: .normal)
    private let flatItemsRelay = BehaviorRelay<[AppViewDisplayItem]?>(value: nil)
    let displayingFlatItemsRelay = BehaviorRelay<[AppViewDisplayItem]?>(value: nil)
    let rawHierarchyInfoRelay = BehaviorRelay<AppViewHierarchyInfo?>(value: nil)

    private(set) var willReloadHierarchyInfo = PublishRelay<Void>()

    let itemDidChangeHiddenAlphaValueRelay = PublishRelay<AppViewDisplayItem>()
    var itemDidChangeHiddenAlphaValue: Observable<AppViewDisplayItem> {
        itemDidChangeHiddenAlphaValueRelay.asObservable()
    }

    let itemDidChangeNoPreviewRelay = PublishRelay<Void>()
    var itemDidChangeNoPreview: Observable<Void> {
        itemDidChangeNoPreviewRelay.asObservable()
    }

    let didReloadHierarchyInfoRelay = PublishRelay<Void>()
    var didReloadHierarchyInfo: Observable<Void> {
        didReloadHierarchyInfoRelay.asObservable()
    }

    let didReloadFlatItemsWithSearchOrFocusRelay = PublishRelay<Void>()
    var didReloadFlatItemsWithSearchOrFocus: Observable<Void> {
        didReloadFlatItemsWithSearchOrFocusRelay.asObservable()
    }

    let itemDidChangeAttrGroupRelay = PublishRelay<AppViewDisplayItem>()
    var itemDidChangeAttrGroup: Observable<AppViewDisplayItem> {
        itemDidChangeAttrGroupRelay.asObservable()
    }

    var rawFlatItems: [AppViewDisplayItem]? {
        didSet { rebuildOidToDisplayItemMap() }
    }

    /// Whether the most recent reload preserved the previous app state (keepState: true).
    /// False means a new app session — the 3D preview may auto-fit the scale to include off-screen content.
    var lastReloadKeptState: Bool = false

    weak var _selectedItem: AppViewDisplayItem?
    let selectedItemTick = PublishRelay<Void>()

    weak var _hoveredItem: AppViewDisplayItem?
    let hoveredItemTick = PublishRelay<Void>()

    var selectColorMenu: NSMenu!
    var customColorMenuItemTag: Int { 10 }
    var toggleColorFormatMenuItemTag: Int { 11 }

    func preferenceManager() -> AVPreferenceManager {
        assertionFailure("should implement by subclass")
        return AVPreferenceMain()
    }

    var serverSideIsSwiftProject = false

    func isReadOnly() -> Bool { true }

    func buildDisplayingFlatItems() {
        displayingFlatItems = flatItems?.filter { $0.displayingInHierarchy } ?? []
    }

    var oidToDisplayItemMap: [UInt: AppViewDisplayItem] = [:]
    var colorToAliasMap: [String: [String]] = [:]

    private let kvoDisposeBag = DisposeBag()

    func reload(with info: AppViewHierarchyInfo, keepState: Bool) {
        performReload(with: info, keepState: keepState)
    }

    override init() {
        super.init()

        AVPreferenceMain().rgbaFormatObservable
            .skip(1)
            .distinctUntilChanged()
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, _ in
                owner.setUpColors()
            }
            .disposed(by: kvoDisposeBag)
    }

    deinit {
        NSLog("%@ dealloc", String(describing: type(of: self)))
    }
}

// MARK: - flatItems relay access

extension AVHierarchyDataSource {
    var flatItemsObservable: Observable<[AppViewDisplayItem]?> {
        flatItemsRelay.asObservable()
    }

    var flatItems: [AppViewDisplayItem]? {
        get { flatItemsRelay.value }
        set { flatItemsRelay.accept(newValue) }
    }
}
