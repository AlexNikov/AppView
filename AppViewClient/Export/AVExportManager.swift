//
//  AVExportManager.swift
//  AppView
//

import AppKit
import AppViewShared

struct AVExportDocumentResult {
    var data: Data
    var fileName: String
}

class AVExportManager: NSObject {
    static let sharedInstance: AVExportManager = {
        AVExportManager()
    }()

    func exportDocument(
        from info: AppViewHierarchyInfo,
        imageCompression compression: CGFloat
    ) -> AVExportDocumentResult? {
        let file = makeHierarchyFile(from: info, imageCompression: compression, forDiskExport: true)
        let document = AppViewDocument()
        document.hierarchyFile = file
        let exportedData: Data
        do {
            exportedData = try document.data(ofType: "com.appview.appview")
        } catch {
            NSLog("AppView export archive failed: %@", String(describing: error))
            assertionFailure("AppView export archive failed: \(error)")
            return nil
        }

        return AVExportDocumentResult(
            data: exportedData,
            fileName: Self.suggestedFileName(for: info.appInfo)
        )
    }

    /// In-memory package for Open in New Window — keep screenshots on display items (Lookin parity).
    func hierarchyFileForReader(from info: AppViewHierarchyInfo) -> AppViewHierarchyFile {
        var file = AppViewHierarchyFile()
        file.serverVersion = info.serverVersion != 0 ? info.serverVersion : appviewServerVersionInt32
        file.hierarchyInfo = info.copy() as? AppViewHierarchyInfo
        return file
    }

    private func makeHierarchyFile(
        from info: AppViewHierarchyInfo,
        imageCompression compression: CGFloat,
        forDiskExport: Bool
    ) -> AppViewHierarchyFile {
        var file = AppViewHierarchyFile()
        file.serverVersion = info.serverVersion != 0 ? info.serverVersion : appviewServerVersionInt32
        // Copy so export never mutates the live inspector tree.
        guard let hierarchyCopy = info.copy() as? AppViewHierarchyInfo else {
            file.hierarchyInfo = info
            return file
        }
        file.hierarchyInfo = hierarchyCopy

        var soloScreenshots: [NSNumber: Data] = [:]
        var groupScreenshots: [NSNumber: Data] = [:]

        let allItems = AppViewDisplayItem.flatItems(
            fromHierarchicalItems: hierarchyCopy.displayItems ?? []
        )
        for displayItem in allItems {
            guard let oid = Self.exportOid(for: displayItem) else { continue }
            displayItem.screenshotEncodeType = .none
            let key = NSNumber(value: oid)
            if let solo = Self.compressedTIFFData(from: displayItem.soloScreenshot, compression: compression) {
                soloScreenshots[key] = solo
            }
            if let group = Self.compressedTIFFData(from: displayItem.groupScreenshot, compression: compression) {
                groupScreenshots[key] = group
            }
            // Screenshots live in the file maps, not on the wire display items.
            // Keep attributesGroupList / customAttrGroupList — reader dashboard needs them.
            if forDiskExport {
                displayItem.soloScreenshot = nil
                displayItem.groupScreenshot = nil
            }
        }
        file.soloScreenshots = soloScreenshots
        file.groupScreenshots = groupScreenshots
        return file
    }

    /// Legacy bridge for call sites that still pass an out-parameter file name.
    func data(
        from info: AppViewHierarchyInfo,
        imageCompression compression: CGFloat,
        fileName: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Data? {
        guard let result = exportDocument(from: info, imageCompression: compression) else {
            return nil
        }
        fileName?.pointee = result.fileName as NSString
        return result.data
    }

    static func exportOid(for displayItem: AppViewDisplayItem) -> UInt? {
        let oid = displayItem.layerObject?.oid ?? displayItem.viewObject?.oid ?? 0
        return oid == 0 ? nil : oid
    }

    static func suggestedFileName(for appInfo: AppViewAppInfo?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMddHHmm"
        let timeString = formatter.string(from: Date())
        var iOSVersion = appInfo?.osDescription ?? ""
        if let dotIdx = iOSVersion.firstIndex(of: ".") {
            iOSVersion = String(iOSVersion[..<dotIdx])
        }
        let appName = appInfo?.appName ?? "AppView"
        return "\(appName)_ios\(iOSVersion)_\(timeString).appview"
    }

    /// compression range 0.01 … 1 (matches Lookin).
    static func compressedTIFFData(from sourceImage: AppViewImage?, compression: CGFloat) -> Data? {
        guard let sourceImage else { return nil }
        let compression = max(min(compression, 1), 0.01)
        let sourceSize = sourceImage.size
        guard sourceSize.width.isFinite, sourceSize.height.isFinite,
              sourceSize.width > 0, sourceSize.height > 0 else {
            return sourceImage.tiffRepresentation
        }
        let targetSize = NSSize(
            width: max(sourceSize.width * compression, 1),
            height: max(sourceSize.height * compression, 1)
        )
        let targetFrame = NSRect(origin: .zero, size: targetSize)
        guard let sourceImageRep = sourceImage.bestRepresentation(for: targetFrame, context: nil, hints: nil) else {
            return sourceImage.tiffRepresentation
        }
        let resizedImage = NSImage(size: targetSize)
        resizedImage.lockFocus()
        sourceImageRep.draw(in: targetFrame)
        resizedImage.unlockFocus()
        guard let tiff = resizedImage.tiffRepresentation,
              let imageRep = NSBitmapImageRep(data: tiff) else {
            return sourceImage.tiffRepresentation
        }
        return imageRep.tiffRepresentation(using: .lzw, factor: 1) ?? sourceImage.tiffRepresentation
    }

    static func exportScreenshot(with displayItem: AppViewDisplayItem) {
        guard let image = displayItem.groupScreenshot else {
            AlertError(AVAppViewClientErrors.inner, CurrentKeyWindow)
            return
        }
        guard let imageData = compressedTIFFData(from: image, compression: 1) else {
            AlertError(AVAppViewClientErrors.inner, CurrentKeyWindow)
            return
        }
        let fileName = displayItem.title() ?? "AppViewImage"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        panel.allowsOtherFileTypes = false
        panel.allowedFileTypes = ["tiff"]
        panel.isExtensionHidden = true
        panel.canCreateDirectories = true
        guard let window = CurrentKeyWindow else { return }
        panel.beginSheetModal(for: window) { result in
            if result == .OK, let path = panel.url?.path {
                do {
                    try imageData.write(to: URL(fileURLWithPath: path))
                } catch {
                    AlertError(error as NSError, CurrentKeyWindow)
                    assertionFailure()
                }
            }
        }
    }
}
