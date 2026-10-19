//
//  AVReadHierarchyDataSource.swift
//  AppView
//

import AppKit
import AppViewShared

class AVReadHierarchyDataSource: AVHierarchyDataSource {
    private var readPreferenceManager: AVPreferenceManager!

    init(file: AppViewHierarchyFile, preferenceManager: AVPreferenceManager) {
        readPreferenceManager = preferenceManager
        super.init()

        if let info = file.hierarchyInfo {
            reload(with: info, keepState: false)
        }

        Self.applyScreenshots(from: file, to: flatItems)
    }

    override func preferenceManager() -> AVPreferenceManager {
        readPreferenceManager
    }

    /// Attach exported TIFF blobs back onto flat items, keyed by layer oid (fallback: view oid).
    static func applyScreenshots(from file: AppViewHierarchyFile, to items: [AppViewDisplayItem]?) {
        let hasSolo = !(file.soloScreenshots?.isEmpty ?? true)
        let hasGroup = !(file.groupScreenshots?.isEmpty ?? true)
        guard hasSolo || hasGroup else { return }

        items?.forEach { obj in
            let rawOid = obj.layerObject?.oid ?? obj.viewObject?.oid ?? 0
            guard rawOid != 0 else { return }
            let key = NSNumber(value: rawOid)
            if let soloData = file.soloScreenshots?[key] {
                obj.soloScreenshot = NSImage(data: soloData)
            }
            if let groupData = file.groupScreenshots?[key] {
                obj.groupScreenshot = NSImage(data: groupData)
            }
        }
    }
}
