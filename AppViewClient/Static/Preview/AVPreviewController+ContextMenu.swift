import AppKit
import AppViewShared

extension AVPreviewController: NSMenuDelegate {
    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let displayItem = rightClickingDisplayItem else { return }

        if !displayItem.isUserCustom() {
            menu.addItem(menuItem(
                title: NSLocalizedString("Focus", comment: ""),
                action: #selector(handleFocusCurrentItem(_:))
            ))
            menu.addItem(menuItem(
                title: NSLocalizedString("Print", comment: ""),
                action: #selector(handlePrintItem(_:))
            ))
            menu.addItem(.separator())

            if !dataSource.isReadOnly() {
                let isUpdating = AVStaticAsyncUpdateManager.sharedInstance.isUpdating
                menu.addItem(menuItem(
                    title: NSLocalizedString("Reload layer", comment: ""),
                    action: #selector(handleReloadSelfItem(_:)),
                    enabled: !isUpdating
                ))
                menu.addItem(menuItem(
                    title: NSLocalizedString("Reload layer and its children", comment: ""),
                    action: #selector(handleReloadSelfAndChildrenItem(_:)),
                    enabled: !isUpdating
                ))
                menu.addItem(.separator())
            }
        }

        if displayItem.isExpandable {
            if displayItem.isExpanded {
                menu.addItem(menuItem(
                    title: NSLocalizedString("Collapse children", comment: ""),
                    action: #selector(handleCollapseChildren(_:))
                ))
            } else {
                menu.addItem(menuItem(
                    title: NSLocalizedString("Expand recursively", comment: ""),
                    action: #selector(handleExpandRecursively(_:))
                ))
            }
            menu.addItem(.separator())
        }

        menu.addItem(menuItem(
            title: NSLocalizedString("Hide screenshot this time", comment: ""),
            action: #selector(handleCancelPreview(_:))
        ))

        if !displayItem.isUserCustom(), displayItem.groupScreenshot != nil {
            menu.addItem(.separator())
            menu.addItem(menuItem(
                title: NSLocalizedString("Export screenshot…", comment: ""),
                action: #selector(handleExportScreenshot(_:))
            ))
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        isKeyingDownCommand = NSEvent.modifierFlags.contains(.command)
    }

    @objc func handlePrintItem(_ sender: Any?) {
        guard let item = rightClickingDisplayItem else { return }
        NotificationCenter.default.post(
            name: NSNotification.Name("AVAppShowConsoleNotificationName"),
            object: item
        )
    }

    @objc func handleReloadSelfItem(_ sender: Any?) {
        guard let item = rightClickingDisplayItem else { return }
        AVStaticAsyncUpdateManager.sharedInstance.reloadSingleDisplayItem(item)
    }

    @objc func handleReloadSelfAndChildrenItem(_ sender: Any?) {
        guard let item = rightClickingDisplayItem else { return }
        AVStaticAsyncUpdateManager.sharedInstance.reloadDisplayItemAndChildren(item)
    }

    @objc func handleFocusCurrentItem(_ sender: Any?) {
        guard let item = rightClickingDisplayItem else { return }
        dataSource.focusDisplayItem(item)
    }

    @objc func handleExpandRecursively(_ sender: Any?) {
        guard let item = rightClickingDisplayItem else { return }
        dataSource.expandItemsRooted(by: item)
    }

    @objc func handleCollapseChildren(_ sender: Any?) {
        guard let item = rightClickingDisplayItem else { return }
        dataSource.collapseAllChildren(of: item)
    }

    @objc func handleCancelPreview(_ sender: Any?) {
        TutorialMng.togglePreview = true
        guard let item = rightClickingDisplayItem else { return }
        item.noPreview = true
        dataSource.itemDidChangeNoPreviewRelay.accept(())
    }

    @objc func handleExportScreenshot(_ sender: Any?) {
        guard let item = rightClickingDisplayItem else { return }
        AVExportManager.exportScreenshot(with: item)
    }

    private func menuItem(title: String, action: Selector, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem()
        item.title = title
        item.target = self
        item.action = action
        item.isEnabled = enabled
        return item
    }
}
