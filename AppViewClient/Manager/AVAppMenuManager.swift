//
//  AVAppMenuManager.swift
//  AppView
//

import AppCenterAnalytics
import AppKit

protocol AVAppMenuManagerDelegate: AnyObject {
    func appMenuManagerDidSelectReload()
    func appMenuManagerDidSelectDimension()
    func appMenuManagerDidSelectZoomIn()
    func appMenuManagerDidSelectZoomOut()
    func appMenuManagerDidSelectDecreaseInterspace()
    func appMenuManagerDidSelectIncreaseInterspace()
    func appMenuManagerDidSelectExpansionIndex(_ index: UInt)
    func appMenuManagerDidSelectFilter()
    func appMenuManagerDidSelectExport()
    func appMenuManagerDidSelectOpenInNewWindow()
}

private enum MenuTag: Int {
    case preferences = 12
    case reload = 21
    case dimension = 22
    case zoomIn = 23
    case zoomOut = 24
    case decreaseInterspace = 25
    case increaseInterspace = 26
    case expansion = 27
    case filter = 28
    case openInNewWindow = 31
    case export = 32
    case copyPod = 66
    case copySPM = 67
}

class AVAppMenuManager: NSObject, NSMenuDelegate {
    private static let _shared = AVAppMenuManager()

    class func sharedInstance() -> AVAppMenuManager {
        _shared
    }

    private typealias WindowMenuAction = (AVWindowController) -> Void

    private var delegatingTagActions: [Int: WindowMenuAction] = [:]

    func setup() {
        delegatingTagActions = [
            MenuTag.reload.rawValue: { $0.appMenuManagerDidSelectReload() },
            MenuTag.dimension.rawValue: { $0.appMenuManagerDidSelectDimension() },
            MenuTag.zoomIn.rawValue: { $0.appMenuManagerDidSelectZoomIn() },
            MenuTag.zoomOut.rawValue: { $0.appMenuManagerDidSelectZoomOut() },
            MenuTag.decreaseInterspace.rawValue: { $0.appMenuManagerDidSelectDecreaseInterspace() },
            MenuTag.increaseInterspace.rawValue: { $0.appMenuManagerDidSelectIncreaseInterspace() },
            MenuTag.export.rawValue: { $0.appMenuManagerDidSelectExport() },
            MenuTag.openInNewWindow.rawValue: { $0.appMenuManagerDidSelectOpenInNewWindow() },
            MenuTag.filter.rawValue: { $0.appMenuManagerDidSelectFilter() },
        ]

        guard let menu = NSApp.mainMenu else { return }

        let menuAppView = menu.item(at: 0)?.submenu
        menuAppView?.autoenablesItems = false
        menuAppView?.delegate = self

        menuAppView?.item(withTag: MenuTag.preferences.rawValue)?.target = self
        menuAppView?.item(withTag: MenuTag.preferences.rawValue)?.action = #selector(handlePreferences)
        let menuFile = menu.item(at: 1)?.submenu
        menuFile?.autoenablesItems = false
        menuFile?.delegate = self

        // File → Open: filter by `.appview` extension. NSDocumentController's UTI-only
        // panel greys out archives that Launch Services still tags as public.data.
        if let openItem = menuFile?.items.first(where: {
            $0.action == #selector(NSDocumentController.openDocument(_:)) || $0.keyEquivalent == "o"
        }) {
            openItem.target = self
            openItem.action = #selector(handleOpenDocument)
        }

        let menuView = menu.item(at: 3)?.submenu
        menuView?.autoenablesItems = false
        menuView?.delegate = self

        let menuHelp = menu.item(at: 5)?.submenu
        menuHelp?.autoenablesItems = true
        menuHelp?.delegate = self

        configureHelpMenu(menuHelp)

        let itemArray = (menuFile?.items ?? []) + (menuView?.items ?? [])
        for item in itemArray {
            guard delegatingTagActions[item.tag] != nil || item.tag == MenuTag.expansion.rawValue else { continue }
            if item.hasSubmenu, item.tag == MenuTag.expansion.rawValue {
                item.submenu?.items.enumerated().forEach { idx, expansionItem in
                    expansionItem.target = self
                    expansionItem.representedObject = NSNumber(value: idx)
                    expansionItem.action = #selector(routeMenuItem(_:))
                }
            } else {
                item.target = self
                item.action = #selector(routeMenuItem(_:))
            }
        }
    }

    @objc private func handleOpenDocument() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["appview"]
        panel.allowsOtherFileTypes = false
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }
        var error: NSError?
        if !AVNavigationManager.sharedInstance.showReader(withFilePath: path, error: &error) {
            AlertError(error ?? AVAppViewClientErrors.inner, NSApp.keyWindow)
        }
    }

    private func configureHelpMenu(_ menuHelp: NSMenu?) {
        bindHelpItem(menuHelp, tag: .copyPod, action: #selector(handleCopyPod))
        bindHelpItem(menuHelp, tag: .copySPM, action: #selector(handleCopySPM))
    }

    private func bindHelpItem(_ menu: NSMenu?, tag: MenuTag, action: Selector) {
        menu?.item(withTag: tag.rawValue)?.target = self
        menu?.item(withTag: tag.rawValue)?.action = action
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let delegate = AVNavigationManager.sharedInstance.currentKeyWindowController()
        for item in menu.items {
            if delegatingTagActions[item.tag] != nil || item.tag == MenuTag.expansion.rawValue {
                item.isEnabled = delegate != nil
            } else {
                item.isEnabled = true
            }
        }
    }

    @objc private func handlePreferences() {
        AVNavigationManager.sharedInstance.showPreference()
    }

    @objc private func routeMenuItem(_ item: NSMenuItem) {
        guard let delegate = AVNavigationManager.sharedInstance.currentKeyWindowController() else {
            assertionFailure()
            return
        }
        if item.tag == MenuTag.expansion.rawValue {
            guard let idxNum = item.representedObject as? NSNumber else {
                assertionFailure()
                return
            }
            delegate.appMenuManagerDidSelectExpansionIndex(idxNum.uintValue)
            Analytics.trackEvent("Hierarchy Expansion", withProperties: ["level": "\(idxNum)"])
            return
        }
        guard let action = delegatingTagActions[item.tag] else {
            assertionFailure()
            return
        }
        action(delegate)
    }

    @objc private func handleCopyPod() {
        let paste = NSPasteboard.general
        paste.clearContents()
        paste.writeObjects(["pod 'AppViewServer', :configurations => ['Debug']"] as [NSString])
    }

    @objc private func handleCopySPM() {
        let paste = NSPasteboard.general
        paste.clearContents()
        paste.writeObjects(["https://github.com/AlexNikov/AppViewServer/"] as [NSString])
    }
}
