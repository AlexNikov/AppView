//
//  AVVerifyCustomInfoLogger.swift
//  AppViewClient
//

import AppKit
import Foundation
import AppViewShared

enum AVVerifyCustomInfoLogger {
    private static let logFile: FileHandle? = {
        let path = ProcessInfo.processInfo.environment["APPVIEW_VERIFY_LOG"] ?? "/tmp/appview-verify-custominfo.log"
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    private static func logLine(_ line: String) {
        NSLog("%@", line)
        guard let data = (line + "\n").data(using: .utf8) else { return }
        logFile?.seekToEndOfFile()
        logFile?.write(data)
    }

    private static func valueSummary(for attr: AppViewAttribute) -> String {
        guard let value = attr.value else { return "nil" }
        let desc = verifyLogDescription(for: value)
        if desc.count > 120 {
            return String(desc.prefix(120)) + "…"
        }
        return desc
    }

    /// ObjC `description` parity for `verify_custom_info_client` golden diff.
    private static func verifyLogDescription(for value: AttributeValue) -> String {
        switch value {
        case .char(let v): return "\(v)"
        case .int(let v): return "\(v)"
        case .short(let v): return "\(v)"
        case .long(let v): return "\(v)"
        case .longLong(let v): return "\(v)"
        case .unsignedChar(let v): return "\(v)"
        case .unsignedInt(let v): return "\(v)"
        case .unsignedShort(let v): return "\(v)"
        case .unsignedLong(let v): return "\(v)"
        case .unsignedLongLong(let v): return "\(v)"
        case .float(let v): return "\(v)"
        case .double(let v): return "\(v)"
        case .bool(let v): return v ? "1" : "0"
        case .selector(let v): return NSStringFromSelector(v)
        case .classRef(let v): return v.map { NSStringFromClass($0) } ?? "nil"
        case .cgPoint(let p):
            return "NSPoint: {\(verifyFormatNumber(p.x)), \(verifyFormatNumber(p.y))}"
        case .cgVector(let v):
            return "NSPoint: {\(verifyFormatNumber(v.dx)), \(verifyFormatNumber(v.dy))}"
        case .cgSize(let s):
            return "NSSize: {\(verifyFormatNumber(s.width)), \(verifyFormatNumber(s.height))}"
        case .cgRect(let r):
            return "NSRect: {{\(verifyFormatNumber(r.origin.x)), \(verifyFormatNumber(r.origin.y))}, {\(verifyFormatNumber(r.size.width)), \(verifyFormatNumber(r.size.height))}}"
        case .cgAffineTransform(let t):
            return "\(t)"
        case .edgeInsets(let insets):
            return "UIEdgeInsets: {\(verifyFormatNumber(insets.top)), \(verifyFormatNumber(insets.left)), \(verifyFormatNumber(insets.bottom)), \(verifyFormatNumber(insets.right))}"
        case .offset(let x, let y):
            return "NSPoint: {\(verifyFormatNumber(x)), \(verifyFormatNumber(y))}"
        case .string(let s): return s
        case .color(let rgba):
            return "(\(rgba.map { verifyFormatNumber($0) }.joined(separator: ", ")))"
        case .shadow(let shadow):
            return "\(shadow)"
        case .json(let s): return s
        case .customObject(let obj):
            if let obj { return String(describing: obj) }
            return "nil"
        }
    }

    private static func verifyFormatNumber(_ value: CGFloat) -> String {
        if value.rounded() == value, abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        return String(describing: value)
    }

    private static func verifyFormatNumber(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }
        return String(describing: value)
    }

    private static func verifyFormatNumber(_ value: Float) -> String {
        verifyFormatNumber(Double(value))
    }

    static func logHierarchyReload(
        flatItems: [AppViewDisplayItem],
        displayingCount: Int,
        selectedItem: AppViewDisplayItem?
    ) {
        var customSubviewLines: [String] = []
        var customAttrLines: [String] = []
        var customSubviewCount = 0
        var customAttrItemCount = 0

        for obj in flatItems {
            if obj.isUserCustom() {
                customSubviewCount += 1
                let title = obj.customInfo?.title ?? ""
                let subtitle = obj.customInfo?.subtitle ?? ""
                let validFrame = obj.hasValidFrameToRoot()
                let frame = obj.calculateFrameToRoot()
                customSubviewLines.append(
                    "AppViewVerify - customSubview: title=\(title) subtitle=\(subtitle) validFrame=\(validFrame ? "1" : "0") frame=\(NSStringFromRect(frame))"
                )
            }

            for group in obj.customAttrGroupList ?? [] {
                let itemTitle = obj.title() ?? ""
                let groupTitle = (group.userCustomTitle?.isEmpty == false) ? (group.userCustomTitle ?? "") : (group.identifier ?? "")
                for section in group.attrSections ?? [] {
                    for attr in section.attributes ?? [] {
                        customAttrItemCount += 1
                        let attrTitle = (attr.displayTitle?.isEmpty == false) ? (attr.displayTitle ?? "") : (attr.identifier ?? "")
                        customAttrLines.append(
                            "AppViewVerify - customAttr: item=\(itemTitle) group=\(groupTitle) attr=\(attrTitle) type=\(attr.attrType.rawValue) value=\(valueSummary(for: attr))"
                        )
                    }
                }
            }
        }

        let selectedTitle = selectedItem?.title() ?? ""
        logLine(
            "AppViewVerify - hierarchy reload: flatCount=\(flatItems.count) customSubviewCount=\(customSubviewCount) customAttrCount=\(customAttrItemCount) displayingCount=\(displayingCount) selectedTitle=\(selectedTitle)"
        )

        for line in customSubviewLines.sorted() {
            logLine(line)
        }
        for line in customAttrLines.sorted() {
            logLine(line)
        }
    }

    static func logDetailModify(detail: AppViewDisplayItemDetail, displayItem: AppViewDisplayItem) {
        let itemTitle = displayItem.title() ?? ""
        let customGroupCount = detail.customAttrGroupList?.count ?? 0
        let builtinGroupCount = detail.attributesGroupList?.count ?? 0
        let subitemCount = detail.subitems?.count ?? 0

        logLine(
            "AppViewVerify - detail modify: item=\(itemTitle) oid=\(detail.displayItemOid) customGroups=\(customGroupCount) builtinGroups=\(builtinGroupCount) subitems=\(subitemCount)"
        )

        var customAttrLines: [String] = []
        for group in detail.customAttrGroupList ?? [] {
            let groupTitle = (group.userCustomTitle?.isEmpty == false) ? (group.userCustomTitle ?? "") : (group.identifier ?? "")
            for section in group.attrSections ?? [] {
                for attr in section.attributes ?? [] {
                    let attrTitle = (attr.displayTitle?.isEmpty == false) ? (attr.displayTitle ?? "") : (attr.identifier ?? "")
                    customAttrLines.append(
                        "AppViewVerify - customAttr: item=\(itemTitle) group=\(groupTitle) attr=\(attrTitle) type=\(attr.attrType.rawValue) value=\(valueSummary(for: attr))"
                    )
                }
            }
        }
        for line in customAttrLines.sorted() {
            logLine(line)
        }
    }

    static func logAsyncUpdate(_ message: String) {
        logLine("AppViewVerify - asyncUpdate: \(message)")
    }
}
