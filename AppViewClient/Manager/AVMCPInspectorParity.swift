//
//  AVMCPInspectorParity.swift
//  AppViewClient
//
//  Unified MCP snapshot for ObjC vs Swift parity (hierarchy tree, preview, dashboard).
//

import AppKit
import AppViewShared

enum AVMCPInspectorParity {
    static let schemaVersion = 1

    static func rgbaArray(from color: AppViewColor?) -> Any {
        guard let color else { return NSNull() }
        let rgba = color.appview_rgbaComponents
        guard rgba.count >= 4 else { return NSNull() }
        return rgba.map(\.doubleValue)
    }

    static func ivarNames(from object: AppViewObject?) -> [String] {
        guard let traces = object?.ivarTraces, !traces.isEmpty else { return [] }
        var seen = Set<String>()
        return traces.compactMap(\.ivarName).filter { seen.insert($0).inserted }.sorted()
    }

    static func itemFields(_ item: AppViewDisplayItem, includeDashboard: Bool = false) -> [String: Any] {
        let represented = item.viewObject ?? item.layerObject
        var fields: [String: Any] = [
            "oid": item.viewObject?.oid ?? item.layerObject?.oid ?? 0,
            "title": item.title() ?? "",
            "subtitle": item.subtitle() ?? "",
            "specialTrace": represented?.specialTrace ?? "",
            "ivarNames": ivarNames(from: represented),
            "memoryAddress": represented?.memoryAddress ?? "",
            "backgroundColorRGBA": rgbaArray(from: item.backgroundColor),
            "indentLevel": item.indentLevel(),
            "displayingInHierarchy": item.displayingInHierarchy,
            "isExpandable": item.isExpandable,
            "isExpanded": item.isExpanded,
            "hasSoloScreenshot": item.soloScreenshot != nil,
            "hasGroupScreenshot": item.groupScreenshot != nil,
        ]
        if includeDashboard {
            fields["dashboardAttributes"] = dashboardAttributes(for: item)
        }
        return fields
    }

    static func valueSummary(for attr: AppViewAttribute) -> String {
        guard let value = attr.value else { return "nil" }
        var desc = "\(value)"
        if desc.count > 160 {
            desc = String(desc.prefix(160)) + "…"
        }
        return desc
    }

    static func dashboardAttributes(for item: AppViewDisplayItem) -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for group in item.queryAllAttrGroupList() {
            let groupTitle = group.identifier ?? ""
            for section in group.attrSections ?? [] {
                for attr in section.attributes ?? [] {
                    rows.append([
                        "group": groupTitle,
                        "section": section.identifier ?? "",
                        "identifier": attr.identifier ?? "",
                        "displayTitle": attr.displayTitle ?? "",
                        "attrType": attr.attrType.rawValue,
                        "value": valueSummary(for: attr),
                    ])
                }
            }
        }
        return rows
    }

    static func previewItems(from previewView: AVPreviewView?) -> [[String: Any]] {
        guard let previewView else { return [] }
        return previewView.mcpTextureSourcesInfo()["items"] as? [[String: Any]] ?? []
    }

    static func hierarchyMacRows(from hierarchyView: AVHierarchyView?) -> [[String: Any]] {
        hierarchyView?.mcpVisibleHierarchyRowStates() ?? []
    }

    static func buildSnapshot(
        dataSource: AVStaticHierarchyDataSource,
        hierarchyView: AVHierarchyView?,
        previewView: AVPreviewView?,
        uiMode: String
    ) -> [String: Any] {
        let flatItems = dataSource.displayingFlatItems ?? dataSource.flatItems ?? []
        let selected = dataSource.selectedItem
        let selectedOid = selected.map { $0.viewObject?.oid ?? $0.layerObject?.oid ?? 0 } ?? 0

        var hierarchyTree: [[String: Any]] = []
        hierarchyTree.reserveCapacity(flatItems.count)
        for item in flatItems {
            hierarchyTree.append(itemFields(item))
        }

        var selection: [String: Any] = [
            "oid": selectedOid,
            "title": "",
            "subtitle": "",
            "specialTrace": "",
            "ivarNames": [] as [String],
            "backgroundColorRGBA": NSNull(),
            "macRowIsSelected": false,
        ]
        if let selected {
            var sel = itemFields(selected, includeDashboard: true)
            sel["macRowIsSelected"] = hierarchyMacRows(from: hierarchyView).contains {
                ($0["oid"] as? UInt ?? 0) == selectedOid && ($0["macIsSelected"] as? Bool) == true
            }
            selection = sel
        }

        let macRows = hierarchyMacRows(from: hierarchyView)
        let selectedMacRows = macRows.filter { ($0["macIsSelected"] as? Bool) == true }

        let dashboardAttrs = selected.map { dashboardAttributes(for: $0) } ?? []

        return [
            "schemaVersion": schemaVersion,
            "uiMode": uiMode,
            "flatItemsCount": flatItems.count,
            "displayingFlatItemsCount": dataSource.displayingFlatItems?.count ?? 0,
            "selection": selection,
            "hierarchyTree": hierarchyTree,
            "hierarchyMacRows": macRows,
            "hierarchyMacSelectedRowCount": selectedMacRows.count,
            "preview": [
                "items": previewItems(from: previewView),
                "displayItemNodesCount": previewView?.mcpDebugInfo()["displayItemNodesCount"] as? Int ?? 0,
            ],
            "dashboard": [
                "selectedOid": selectedOid,
                "attributes": dashboardAttrs,
                "attributeCount": dashboardAttrs.count,
            ],
        ]
    }
}
