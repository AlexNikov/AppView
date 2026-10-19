//
//  AVHierarchyController.swift
//  AppView
//

import AppKit
import AppViewShared
import RxSwift

class AVHierarchyController: AVBaseViewController {
    private(set) var dataSource: AVHierarchyDataSource!
    private(set) var hierarchyView: AVHierarchyView!
    private let disposeBag = DisposeBag()

    init(dataSource: AVHierarchyDataSource) {
        let hierarchyView = AVHierarchyView(dataSource: dataSource)
        super.init(containerView: hierarchyView)
        self.dataSource = dataSource
        self.hierarchyView = hierarchyView
        bindHierarchyViewEvents()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func bindHierarchyViewEvents() {
        hierarchyView.didSelectItemFromUser
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, item in
                owner.dataSource.selectedItem = item
            }
            .disposed(by: disposeBag)

        hierarchyView.didDoubleClickItemFromUser
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, item in
                owner.handleDoubleClick(item)
            }
            .disposed(by: disposeBag)

        hierarchyView.didHoverItemFromUser
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, item in
                owner.dataSource.hoveredItem = item
            }
            .disposed(by: disposeBag)

        hierarchyView.needExpandItemFromUser
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, pair in
                let (item, recursively) = pair
                if recursively {
                    owner.dataSource.expandItemsRooted(by: item)
                } else {
                    owner.dataSource.expandItem(item)
                }
            }
            .disposed(by: disposeBag)

        hierarchyView.needCollapseItemFromUser
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, item in
                owner.dataSource.collapseItem(item)
            }
            .disposed(by: disposeBag)

        hierarchyView.needCollapseChildrenFromUser
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, item in
                owner.dataSource.collapseAllChildren(of: item)
            }
            .disposed(by: disposeBag)

        hierarchyView.searchTextFromUser
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, string in
                if let string, !string.isEmpty {
                    NSLog("[New][HierarchyController] search: \(string)")
                    owner.dataSource.search(with: string)
                } else {
                    owner.dataSource.endSearch()
                }
            }
            .disposed(by: disposeBag)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if !TutorialMng.hasAlreadyShowedTipsThisLaunch, !TutorialMng.copyTitle {
            if let selectedView = currentSelectedRowView() {
                TutorialMng.hasAlreadyShowedTipsThisLaunch = true
                TutorialMng.showPopover(
                    of: selectedView,
                    text: NSLocalizedString("Double click to copy title", comment: ""),
                    learned: { TutorialMng.copyTitle = true }
                )
            }
        }
    }

    func currentSelectedRowView() -> NSView? {
        let row = hierarchyView.tableView.tableView.selectedRow
        guard row >= 0 else { return nil }
        return hierarchyView.tableView.tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
    }

    private func handleDoubleClick(_ item: AppViewDisplayItem) {
        if AVPreferenceManager.popupToAskDoubleClickBehaviorIfNeeded(with: hierarchyView.window) {
            return
        }
        let behavior = AVPreferenceMain().doubleClickBehavior
        if behavior == .collapse {
            guard item.isExpandable else { return }
            if item.isExpanded {
                dataSource.collapseItem(item)
            } else {
                dataSource.expandItem(item)
            }
        } else if behavior == .focus {
            dataSource.focusDisplayItem(item)
        } else {
            assertionFailure()
        }
    }
}
