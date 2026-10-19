//
//  AppViewRACSignalRx.swift
//  AppView
//

import Foundation
import RxSwift

enum AppViewRACSignalRx {
    static func observeMainThread<T>(_ observable: Observable<T>) -> Observable<T> {
        observable.observe(on: MainScheduler.instance)
    }

    static func observeMainThread<T>(_ single: PrimitiveSequence<SingleTrait, T>) -> PrimitiveSequence<SingleTrait, T> {
        single.observe(on: MainScheduler.instance)
    }
}

extension Observable {
    @discardableResult
    func subscribeNext(
        _ onNext: @escaping (Element) -> Void,
        error: ((Swift.Error) -> Void)? = nil,
        completed: (() -> Void)? = nil
    ) -> Disposable {
        subscribe(
            onNext: onNext,
            onError: error ?? { _ in },
            onCompleted: completed ?? {}
        )
    }
}

extension PrimitiveSequence where Trait == SingleTrait {
    @discardableResult
    func subscribeNext(
        _ onSuccess: @escaping (Element) -> Void,
        error: ((Swift.Error) -> Void)? = nil
    ) -> Disposable {
        subscribe(
            onSuccess: onSuccess,
            onFailure: error ?? { _ in }
        )
    }
}
