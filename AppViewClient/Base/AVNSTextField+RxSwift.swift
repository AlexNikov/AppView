//
//  AVNSTextField+RxSwift.swift
//  AppView
//

import AppKit
import RxSwift

extension NSTextField {
    /// Current `stringValue` on subscribe, then each `NSControl.textDidChangeNotification` (RxCocoa `rx.text.orEmpty` equivalent).
    var lk_textOrEmpty: Observable<String> {
        Observable.create { [weak self] observer in
            guard let self else {
                observer.onCompleted()
                return Disposables.create()
            }
            observer.onNext(self.stringValue)
            let token = NotificationCenter.default.addObserver(
                forName: NSControl.textDidChangeNotification,
                object: self,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                observer.onNext(self.stringValue)
            }
            return Disposables.create {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }
}
