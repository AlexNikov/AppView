//
//  AVLogsManager.swift
//  AppView
//

import Foundation
import AppViewShared
import RxRelay
import RxSwift

enum AVLogLevel {
    case error
    case info
}

struct AVLogEntry {
    let timestamp: Date
    let title: String
    let detail: String?
    let level: AVLogLevel
}

extension Notification.Name {
    static let AVShowErrorNotification = Notification.Name("AVShowErrorNotification")
}

let AVShowErrorNotificationTitleKey = "title"

final class AVLogsManager {
    static let shared = AVLogsManager()
    private init() {}

    private let entriesRelay = BehaviorRelay<[AVLogEntry]>(value: [])
    private let hasUnreadErrorsRelay = BehaviorRelay<Bool>(value: false)

    var entriesObservable: Observable<[AVLogEntry]> {
        entriesRelay.asObservable()
    }

    var hasUnreadErrorsObservable: Observable<Bool> {
        hasUnreadErrorsRelay.asObservable()
    }

    var entries: [AVLogEntry] {
        entriesRelay.value
    }

    func logError(_ error: NSError) {
        guard error.code != Int(AppViewErrCode_Discard) else { return }
        let detail = error.localizedRecoverySuggestion
        let entry = AVLogEntry(
            timestamp: Date(),
            title: error.localizedDescription,
            detail: (detail?.isEmpty == false) ? detail : nil,
            level: .error
        )
        entriesRelay.accept(entriesRelay.value + [entry])
        hasUnreadErrorsRelay.accept(true)
    }

    func markAllRead() {
        hasUnreadErrorsRelay.accept(false)
    }

    func clearEntries() {
        entriesRelay.accept([])
        hasUnreadErrorsRelay.accept(false)
    }
}
