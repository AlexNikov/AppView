//
//  AppViewAutoLayoutConstraint+AppViewClient.swift
//  AppViewClient
//

import AppKit
import AppViewShared

extension AppViewAutoLayoutConstraint {
    static func descriptionWithItemObject(
        _ object: AppViewObject?,
        type: AppViewConstraintItemType,
        detailed: Bool
    ) -> String {
        switch type {
        case .unknown:
            return detailed ? "Unknown" : "unknown"
        case .nil:
            return detailed ? "Nil" : "nil"
        case .self:
            return detailed ? "Self" : "self"
        case .super:
            return detailed ? "Superview" : "super"
        case .view, .layoutGuide:
            guard let object else { return detailed ? "Nil" : "nil" }
            if detailed {
                return "<\(object.rawClassName() ?? ""): \(object.memoryAddress ?? "")>"
            }
            return "(\(object.lk_simpleDemangledClassName)*)"
        @unknown default:
            assertionFailure()
            guard let object else { return detailed ? "Nil" : "nil" }
            if detailed {
                return "<\(object.rawClassName() ?? ""): \(object.memoryAddress ?? "")>"
            }
            return "(\(object.rawClassName() ?? "")*)"
        }
    }

    static func description(withAttributeInt attribute: Int) -> String {
        switch attribute {
        case 0: return "notAnAttribute"
        case 1: return "left"
        case 2: return "right"
        case 3: return "top"
        case 4: return "bottom"
        case 5: return "leading"
        case 6: return "trailing"
        case 7: return "width"
        case 8: return "height"
        case 9: return "centerX"
        case 10: return "centerY"
        case 11: return "lastBaseline"
        case 12: return "firstBaseline"
        case 13: return "leftMargin"
        case 14: return "rightMargin"
        case 15: return "topMargin"
        case 16: return "bottomMargin"
        case 17: return "leadingMargin"
        case 18: return "trailingMargin"
        case 19: return "centerXWithinMargins"
        case 20: return "centerYWithinMargins"
        case 32: return "minX"
        case 33: return "minY"
        case 34: return "midX"
        case 35: return "midY"
        case 36: return "maxX"
        case 37: return "maxY"
        default:
            assertionFailure()
            return "unknownAttr(\(attribute))"
        }
    }

    static func symbol(with relation: NSLayoutConstraint.Relation) -> String {
        switch Int(relation.rawValue) {
        case -1: return "<="
        case 0: return "="
        case 1: return ">="
        default:
            assertionFailure()
            return "?"
        }
    }

    static func description(with relation: NSLayoutConstraint.Relation) -> String {
        switch Int(relation.rawValue) {
        case -1: return "LessThanOrEqual"
        case 0: return "Equal"
        case 1: return "GreaterThanOrEqual"
        default:
            assertionFailure()
            return "?"
        }
    }
}
