//
//  AVMessageManager.swift
//  AppViewClient
//

import Foundation
import AppViewShared

class AVMessageConstants: NSObject {
    static let newServerVersion = "AVMessage_NewServerVersion"
    static let swiftSubspec = "AVMessage_SwiftSubspec"
}

let AVMessage_NewServerVersion = AVMessageConstants.newServerVersion
let AVMessage_SwiftSubspec = AVMessageConstants.swiftSubspec

final class AVMessageManager: NSObject {
    static let sharedInstance = AVMessageManager()

    private var messages = Set<String>()

    private override init() {
        super.init()
    }

    func addMessage(_ message: String) {
        messages.insert(message)
    }

    func removeMessage(_ message: String) {
        messages.remove(message)
    }

    func queryMessages() -> [String] {
        messages.sorted { $0.count > $1.count }
    }

    func reset() {
        messages.removeAll()
    }
}
