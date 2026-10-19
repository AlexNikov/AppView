//
//  AVUserActionManager.swift
//  AppView
//

import Foundation

final class AVUserActionManager {
    static let sharedInstance = AVUserActionManager()

    private struct WeakDelegate {
        weak var value: AVUserActionManagerDelegate?
    }

    private var delegates: [WeakDelegate] = []

    private init() {}

    func addDelegate(_ delegate: AVUserActionManagerDelegate) {
        guard !delegates.contains(where: { $0.value as AnyObject? === delegate as AnyObject }) else {
            return
        }
        delegates.append(WeakDelegate(value: delegate))
        compactDelegates()
    }

    func send(_ type: AVUserActionType) {
        sendAction(type)
    }

    func sendAction(_ type: AVUserActionType) {
        guard type != .none else {
            assertionFailure()
            return
        }
        compactDelegates()
        for entry in delegates {
            entry.value?.lkUserActionManager(self, didAct: type)
        }
    }

    private func compactDelegates() {
        delegates.removeAll { $0.value == nil }
    }
}
