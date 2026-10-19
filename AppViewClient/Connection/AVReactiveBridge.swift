import Foundation
import RxSwift

enum AVReactiveBridge {
    static func singleSignal<T>(
        _ work: @escaping (
            _ sendSuccess: @escaping (T) -> Void,
            _ sendError: @escaping (Error) -> Void
        ) -> (() -> Void)?
    ) -> Single<T> {
        Single.create { single in
            let cancel = work(
                { single(.success($0)) },
                { single(.failure($0)) }
            )
            return Disposables.create { cancel?() }
        }
    }

    static func interval(seconds: TimeInterval, until: Observable<Void>) -> Observable<Int> {
        Observable<Int>
            .interval(.milliseconds(Int(seconds * 1000)), scheduler: MainScheduler.instance)
            .take(until: until)
    }
}
