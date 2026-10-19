//
//  AppViewPreviewStructureExporter.swift
//  AppView
//

import Foundation

enum AppViewPreviewStructureExporter {
    static func normalizedLines(from state: [String: Any]) -> [String] {
        let rotationX = formatNumber(state["rotationX"])
        let rotationY = formatNumber(state["rotationY"])
        let translationX = formatNumber(state["translationX"])
        let translationY = formatNumber(state["translationY"])
        let sceneLayout = state["sceneLayout"] as? String ?? "flat"
        let dimension = state["dimension"] as? Int ?? 0
        var lines: [String] = [
            "sceneLayout=\(sceneLayout)",
            "dimension=\(dimension)",
            "rotation=(\(rotationX),\(rotationY))",
            "translation=(\(translationX),\(translationY))",
            "scale=\(formatNumber(state["scale"]))",
            "zInterspace=\(formatNumber(state["zInterspace"]))",
            "nodes=\(state["displayItemNodesCount"] as? Int ?? 0)",
            "treeNodes=\(state["treeDisplayItemNodesCount"] as? Int ?? 0)",
            "flat=\(state["flatDisplayItemsCount"] as? Int ?? 0)",
        ]

        if let structure = state["structure"] as? [[String: Any]], !structure.isEmpty {
            let sorted = structure.sorted {
                intValue($0["oid"]) < intValue($1["oid"])
            }
            for node in sorted {
                lines.append(normalizeStructureNode(node))
            }
        } else if let planes = state["planes"] as? [[String: Any]] {
            let sorted = planes.sorted {
                intValue($0["oid"]) < intValue($1["oid"])
            }
            for plane in sorted {
                lines.append(normalizePlane(plane))
            }
        }
        return lines
    }

    static func structureTreeLines(from lines: [String]) -> [String] {
        lines.filter { $0.hasPrefix("oid=") }
    }

    static func containsTitle(_ title: String, in lines: [String]) -> Bool {
        let needle = "title=\"\(title)\""
        return lines.contains { $0.contains(needle) }
    }

    private static func normalizeStructureNode(_ node: [String: Any]) -> String {
        let pos = node["positionRoot"] as? [String: Any] ?? [:]
        let wire = intValue(node["wireOid"])
        let oid = intValue(node["oid"])
        let title = (node["title"] as? String ?? "").replacingOccurrences(of: " ", with: "_")
        let clippedTitle = String(title.prefix(40))
        let extra = wire == 0 ? " wire=\(wire)" : ""
        let titlePart = wire == 0 && !clippedTitle.isEmpty ? " title=\"\(clippedTitle)\"" : ""
        return [
            "oid=\(oid)",
            "super=\(intValue(node["superOid"]))",
            "indent=\(intValue(node["indentLevel"]))",
            "zIdx=\(intValue(node["previewZIndex"]))",
            "tex=\(node["textureKind"] as? String ?? "none")",
            "disp=\(boolValue(node["displayingInHierarchy"]) ? 1 : 0)",
            "flat=\(intValue(node["flatIndex"], fallback: -1))\(extra)\(titlePart)",
            "root=(\(formatNumber(pos["x"])),\(formatNumber(pos["y"])),\(formatNumber(pos["width"])),\(formatNumber(pos["height"])))",
        ].joined(separator: " ")
    }

    private static func normalizePlane(_ plane: [String: Any]) -> String {
        let pos = plane["position"] as? [String: Any] ?? [:]
        return [
            "oid=\(intValue(plane["oid"]))",
            "super=\(intValue(plane["superOid"]))",
            "scnParent=\(intValue(plane["scnParentOid"]))",
            "indent=\(intValue(plane["indentLevel"]))",
            "zIdx=\(intValue(plane["previewZIndex"]))",
            "tex=\(plane["textureKind"] as? String ?? "none")",
            "disp=\(boolValue(plane["displayingInHierarchy"]) ? 1 : 0)",
            "op=\(formatNumber(plane["opacity"], digits: 3))",
            "pos=(\(formatNumber(pos["x"], digits: 4)),\(formatNumber(pos["y"], digits: 4)),\(formatNumber(pos["z"], digits: 4)))",
        ].joined(separator: " ")
    }

    private static func intValue(_ value: Any?, fallback: Int = 0) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let value = value as? Int { return value }
        if let value = value as? UInt { return Int(value) }
        return fallback
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let value = value as? Bool { return value }
        return false
    }

    private static func formatNumber(_ value: Any?, digits: Int = 2) -> String {
        let number: Double
        if let value = value as? NSNumber {
            number = value.doubleValue
        } else if let value = value as? Double {
            number = value
        } else if let value = value as? CGFloat {
            number = Double(value)
        } else {
            number = 0
        }
        return String(format: "%.\(digits)f", number)
    }
}
