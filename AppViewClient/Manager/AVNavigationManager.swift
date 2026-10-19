//
//  AVNavigationManager.swift
//  AppView
//

import AppKit
import AppViewShared

class AVNavigationManager: NSObject, NSWindowDelegate {
    private static let _appviewShared = AVNavigationManager()
    static let sharedInstance = _appviewShared

    private(set) var launchWindowController: AVLaunchWindowController?
    private(set) var staticWindowController: AVStaticWindowController?
    var readWindowControllers = NSMutableArray()

    var windowTitleBarHeight: CGFloat = 0

    private var preferenceWindowController: AVPreferenceWindowController?
    private var jsonWindowController: AVJSONAttributeWindowController?

    private override init() {
        super.init()
    }

    func showLaunch() {
        // End inspect only when leaving the static workspace (avoid killing Peertalk during launch polling).
        if staticWindowController?.window?.isVisible == true {
            AVAppsManager.sharedInstance.endInspectingSession()
            staticWindowController?.close()
        }
        launchWindowController = AVLaunchWindowController()
        launchWindowController?.showWindow(self)
    }

    func showStaticWorkspace() {
        if staticWindowController == nil {
            staticWindowController = AVStaticWindowController()
            staticWindowController?.window?.delegate = self
        }
        staticWindowController?.showWindow(self)
    }

    func closeLaunch() {
        launchWindowController?.close()
        launchWindowController = nil
    }

    func showPreference() {
        if preferenceWindowController == nil {
            preferenceWindowController = AVPreferenceWindowController()
            preferenceWindowController?.window?.delegate = self
        }
        preferenceWindowController?.showWindow(self)
    }

    func currentKeyWindowController() -> AVWindowController? {
        guard let keyWindow = NSApplication.shared.keyWindow,
              let controller = keyWindow.windowController as? AVWindowController else {
            return nil
        }
        return controller
    }

    func showReader(withFilePath filePath: String, error: NSErrorPointer) -> Bool {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let dataObj = try AVWireCodec.loadHierarchyFile(from: data)
            let hierarchyFile = dataObj

            if let verifyError = AppViewHierarchyFile.verify(hierarchyFile) {
                if let error {
                    error.pointee = verifyError as NSError
                }
                return false
            }

            let title = FileManager.default.displayName(atPath: filePath)
            showReader(withHierarchyFile: hierarchyFile, title: title)
            return true
        } catch let readError as NSError {
            if let error {
                error.pointee = readError
            }
            return false
        }
    }

    func showReader(withHierarchyFile file: AppViewHierarchyFile, title: String?) {
        let wc = AVReadWindowController(file: file)
        wc.window?.title = title ?? ""
        wc.window?.delegate = self
        wc.showWindow(self)
        readWindowControllers.add(wc)
    }

    func showJsonWindow(_ json: String) {
        if jsonWindowController == nil {
            jsonWindowController = AVJSONAttributeWindowController()
            jsonWindowController?.window?.delegate = self
        }
        if let controller = jsonWindowController?.contentViewController as? AVJSONAttributeViewController {
            controller.render(withJSON: json)
        }
        jsonWindowController?.showWindow(self)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }

        if closingWindow == preferenceWindowController?.window {
            preferenceWindowController = nil
        } else if closingWindow == staticWindowController?.window {
            AVAppsManager.sharedInstance.endInspectingSession()
            closingWindow.saveFrame(usingName: AVWindowSizeName_Static)
        } else {
            let controllers = readWindowControllers.compactMap { $0 as? AVReadWindowController }
            if let wc = controllers.first(where: { $0.window == closingWindow }) {
                readWindowControllers.remove(wc)
            }
        }
    }
}
