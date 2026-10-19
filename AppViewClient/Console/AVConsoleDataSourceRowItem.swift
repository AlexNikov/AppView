//
//  AVConsoleDataSourceRowItem.swift
//  AppView
//

import Foundation

enum AVConsoleDataSourceRowItemType: Int {
    case input
    case submit
    case `return`
}

class AVConsoleDataSourceRowItem: NSObject {
    var type: AVConsoleDataSourceRowItemType = .input
    var normalText: String?
    var highlightText: String?
}
