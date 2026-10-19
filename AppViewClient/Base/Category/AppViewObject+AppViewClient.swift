//
//  AppViewObject+AppViewClient.swift
//  AppViewClient
//

import Foundation
import AppViewShared

extension AppViewObject {
    var lk_completedDemangledClassName: String {
        AVSwiftDemangler.completedParse(input: rawClassName() ?? "")
    }

    var lk_simpleDemangledClassName: String {
        let name = AVSwiftDemangler.simpleParse(input: rawClassName() ?? "")
        let components = (name as NSString).components(separatedBy: ".")
        return components.last ?? name
    }
}
