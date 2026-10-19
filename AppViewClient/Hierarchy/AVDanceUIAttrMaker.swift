//
//  AVDanceUIAttrMaker.swift
//  AppViewClient
//

import Foundation
import AppViewShared

class AVDanceUIAttrMaker: NSObject {
    /// 给 item 的属性列表里填充上“跳转 DanceUI 文件”相关的信息
    class func makeDanceUIJumpAttribute(_ item: AppViewDisplayItem, danceSource source: String) {
        guard let className = getClass(fromSource: source) else { return }

        let alreadyHas = item.attributesGroupList?.contains(where: { group in
            group.identifier == AppViewAttrGroup_Class
        }) ?? false
        if alreadyHas { return }

        let attr = AppViewAttribute()
        attr.identifier = AppViewAttr_Class_Class_Class
        attr.attrType = .customObj
        attr.value = .customObject([[className]])

        var sec = AppViewAttributesSection()
        sec.identifier = AppViewAttrSec_Class_Class
        sec.attributes = [attr]

        var group = AppViewAttributesGroup()
        group.identifier = AppViewAttrGroup_Class
        group.attrSections = [sec]

        if let existing = item.attributesGroupList {
            item.attributesGroupList = existing + [group]
        } else {
            item.attributesGroupList = [group]
        }
    }

    private class func getClass(fromSource json: String) -> String? {
        guard let jsonData = json.data(using: .utf8) else { return nil }
        do {
            guard let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                assertionFailure()
                return nil
            }
            guard let type = dict["type"] as? String else {
                assertionFailure()
                return nil
            }
            return type
        } catch {
            assertionFailure()
            return nil
        }
    }
}
