//
//  AVStaticHierarchyController.swift
//  AppView
//

import AppKit
import AppViewShared

final class AVStaticHierarchyController: AVHierarchyController, AVHierarchyViewDelegate {
    override init(dataSource: AVHierarchyDataSource) {
        super.init(dataSource: dataSource)
        hierarchyView.delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func hierarchyView(_ view: AVHierarchyView, needToCancelPreviewOfItem item: AppViewDisplayItem) {
        item.noPreview = true
        guard let staticSource = dataSource as? AVStaticHierarchyDataSource else { return }
        staticSource.itemDidChangeNoPreviewRelay.accept(())
    }

    func hierarchyView(_ view: AVHierarchyView, needToShowPreviewOfItem item: AppViewDisplayItem) {
        item.enumerateSelfAndAncestors { ancestor, _ in
            if ancestor.noPreview {
                ancestor.noPreview = false
            }
        }
        guard let staticSource = dataSource as? AVStaticHierarchyDataSource else { return }
        staticSource.itemDidChangeNoPreviewRelay.accept(())
    }
}
