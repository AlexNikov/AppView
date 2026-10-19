import Foundation
import AppViewShared
import RxSwift

extension AVDashboardAttributeView {
    @discardableResult
    func subscribeAttributeModification(
        newValue: AttributeValue?,
        onError: @escaping () -> Void = {},
        onSuccess: (() -> Void)? = nil
    ) -> Disposable? {
        guard let dashboardViewController, let attribute else { return nil }
        return AppViewRACSignalRx.observeMainThread(
            dashboardViewController.modifyAttribute(attribute, newValue: newValue)
        )
        .subscribe(
            onSuccess: {
                onSuccess?()
            },
            onFailure: { _ in
                onError()
            }
        )
    }
}
