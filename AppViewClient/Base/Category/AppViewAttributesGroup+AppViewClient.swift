//
//  AppViewAttributesGroup+AppViewClient.swift
//  AppViewClient
//
//  Created by LikaiMacStudioWork on 2023/10/31.
//

import Foundation
import AppViewShared

extension AppViewAttributesGroup {
    func queryDisplayTitle() -> String {
        if let userCustomTitle, userCustomTitle.count > 0 {
            return userCustomTitle
        }
        return AppViewDashboardBlueprint.groupTitle(withGroupID: identifier ?? "")
    }
}
