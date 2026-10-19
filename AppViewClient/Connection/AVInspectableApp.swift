import Foundation
import AppViewShared
import RxSwift

public final class AVInspectableApp: NSObject {
    public var serverVersionError: NSError?
    public var appInfo: AppViewAppInfo?
    public weak var channel: AVPeerChannel?
    /// Launch screen placeholder while a USB iPhone is plugged in but no demo is listening yet.
    public var isLaunchUSBPendingPlaceholder = false
    public var pendingUSBDeviceID: NSNumber?

    /// `scanLayoutIssues` asks the server to run the ambiguous-layout scan; only first connect and Reload set it.
    public func fetchHierarchyData(scanLayoutIssues: Bool = false) -> Single<AppViewHierarchyInfo> {
        let params = WireHierarchyRequestParams(
            clientVersion: AVHelper.appviewReadableVersion(),
            minWireVersion: AppViewWireFormat.version,
            scanLayoutIssues: scanLayoutIssues ? true : nil
        )
        return requestTyped(
            withType: UInt32(AppViewRequestTypeHierarchy),
            wirePayload: .hierarchy(params)
        ) { data in
            guard let info = data as? AppViewHierarchyInfo else {
                throw AVAppViewClientErrors.inner
            }
            return info
        }
    }

    public func submitInbuiltModification(_ modification: AppViewAttributeModification) -> Single<AppViewDisplayItemDetail> {
        requestTyped(
            withType: UInt32(AppViewRequestTypeInbuiltAttrModification),
            wirePayload: .inbuilt(modification)
        ) { data in
            guard let detail = data as? AppViewDisplayItemDetail else {
                throw AVAppViewClientErrors.inner
            }
            return detail
        }
    }

    public func cancelInbuiltModification() {
        guard let channel else { return }
        AVConnectionManager.sharedInstance.cancelRequest(
            withType: UInt32(AppViewRequestTypeInbuiltAttrModification),
            channel: channel,
            notifyDiscard: true
        )
    }

    public func submitCustomModification(_ modification: AppViewCustomAttrModification) -> Completable {
        requestTyped(
            withType: UInt32(AppViewRequestTypeCustomAttrModification),
            wirePayload: .custom(modification)
        ) { _ in () }
            .asCompletable()
    }

    public func fetchHierarchyDetail(
        withTaskPackages packages: [AppViewStaticAsyncUpdateTasksPackage]
    ) -> Observable<[AppViewDisplayItemDetail]> {
        let wirePackages = packages.map { WireAsyncTaskMapper.wirePackage(from: $0) }
        return requestObservable(
            withType: UInt32(AppViewRequestTypeHierarchyDetails),
            wirePayload: .detailPackages(wirePackages)
        )
        .map { value in
            let details = AppViewCastDisplayItemDetails(value as Any)
            if details.isEmpty, !(value is NSNull) {
                NSLog(
                    "AppViewClient - hierarchy details chunk empty after cast, data type: %@",
                    String(describing: type(of: value))
                )
            }
            return details
        }
    }

    private static func unwrapConnectionResponseAttachment(_ value: Any?) -> AppViewConnectionResponseAttachment? {
        AppViewCastConnectionResponseAttachment(value)
    }

    public func cancelHierarchyDetailFetching() {
        cancelRequest(withType: UInt32(AppViewRequestTypeHierarchyDetails))
        push(withType: UInt32(AppViewPush_CanceHierarchyDetails), data: nil)
    }

    public func fetchModificationPatch(withTasks tasks: [AppViewStaticAsyncUpdateTask]) -> Observable<AppViewDisplayItemDetail> {
        let wireTasks = tasks.map { WireAsyncTaskMapper.wireTask(from: $0) }
        return requestObservable(
            withType: UInt32(AppViewRequestTypeAttrModificationPatch),
            wirePayload: .patchTasks(wireTasks)
        )
        .compactMap { $0 as? AppViewDisplayItemDetail }
    }

    public func fetchObject(withOid oid: UInt) -> Single<AppViewDisplayItem> {
        guard oid != 0 else {
            return .error(AVAppViewClientErrors.inner)
        }
        return requestTyped(
            withType: UInt32(AppViewRequestTypeFetchObject),
            wirePayload: .oid(oid)
        ) { data in
            guard let item = data as? AppViewDisplayItem else {
                throw AVAppViewClientErrors.inner
            }
            return item
        }
    }

    /// Lightweight attr fetch for dashboard selection — does not cancel bulk HierarchyDetails sync.
    public func fetchAttrGroupList(withOid oid: UInt) -> Single<[AppViewAttributesGroup]> {
        guard oid != 0 else {
            return .error(AVAppViewClientErrors.inner)
        }
        return requestTyped(
            withType: UInt32(AppViewRequestTypeAllAttrGroups),
            wirePayload: .oid(oid)
        ) { data in
            if let list = data as? [AppViewAttributesGroup] {
                return list
            }
            if let list = data as? NSArray as? [AppViewAttributesGroup] {
                return list
            }
            throw AVAppViewClientErrors.inner
        }
    }

    public func fetchSelectorNames(withClass className: String, hasArg: Bool) -> Single<[String]> {
        let query = WireSelectorQueryParams(className: className, hasArg: hasArg)
        return requestTyped(
            withType: UInt32(AppViewRequestTypeAllSelectorNames),
            wirePayload: .selector(query)
        ) { data in
            if let list = data as? [String] {
                return list
            }
            if let list = data as? NSArray as? [String] {
                return list
            }
            throw AVAppViewClientErrors.inner
        }
    }

    public func invokeMethod(withOid oid: UInt, text: String) -> Single<[String: Any]> {
        guard oid != 0, !text.isEmpty else {
            return .error(AVAppViewClientErrors.inner)
        }
        let invoke = WireInvokeParams(oid: oid, text: text)
        return requestTyped(
            withType: UInt32(AppViewRequestTypeInvokeMethod),
            wirePayload: .invoke(invoke)
        ) { data in
            guard let dict = data as? [String: Any] else {
                throw AVAppViewClientErrors.inner
            }
            if (dict["description"] as? String) == AppViewStringFlag_VoidReturn {
                var newValue = dict
                newValue["description"] = NSLocalizedString(
                    "The method was invoked successfully and no value was returned.",
                    comment: ""
                )
                return newValue
            }
            return dict
        }
    }

    public func fetchImage(withImageViewOid oid: UInt) -> Single<Data> {
        guard oid != 0 else {
            return .error(AVAppViewClientErrors.inner)
        }
        return requestTyped(
            withType: UInt32(AppViewRequestTypeFetchImageViewImage),
            wirePayload: .oid(oid)
        ) { data in
            if let imageData = data as? Data {
                return imageData
            }
            if let nsData = data as? NSData {
                return nsData as Data
            }
            throw AVAppViewClientErrors.inner
        }
    }

    public func modifyGestureRecognizer(_ oid: UInt, toBeEnabled shouldBeEnabled: Bool) -> Completable {
        guard oid != 0 else {
            return .error(AVAppViewClientErrors.inner)
        }
        let params = WireRecognizerParams(oid: oid, enable: shouldBeEnabled)
        return requestTyped(
            withType: UInt32(AppViewRequestTypeModifyRecognizerEnable),
            wirePayload: .recognizer(params)
        ) { _ in () }
            .asCompletable()
    }

    // MARK: - Private

    private func push(withType pushType: UInt32, data: NSObject?) {
        guard let channel else { return }
        AVConnectionManager.sharedInstance.push(withType: pushType, data: data, channel: channel)
    }

    private func requestObservable(
        withType requestType: UInt32,
        wirePayload: WireClientRequestPayload
    ) -> Observable<Any?> {
        guard let channel else {
            return .error(AVAppViewClientErrors.noConnect)
        }

        return AVConnectionManager.sharedInstance.request(
            withType: requestType,
            data: nil,
            channel: channel,
            wirePayload: wirePayload
        )
        .flatMap { pair -> Observable<Any?> in
            guard let attachment = Self.unwrapConnectionResponseAttachment(pair.first) else {
                NSLog(
                    "AppViewClient - connection response unwrap failed, type: %@",
                    String(describing: type(of: pair.first as Any))
                )
                return .error(AVAppViewClientErrors.inner)
            }
            if let error = attachment.error as NSError? {
                if error.code == AppViewErrCode_ObjectNotFound {
                    return .error(AVAppViewClientErrors.objectNotFound)
                }
                if error.code == AppViewErrCode_Inner {
                    return .error(AVAppViewClientErrors.inner)
                }
                return .error(error)
            }
            if requestType == UInt32(AppViewRequestTypeInbuiltAttrModification),
               attachment.data as? AppViewDisplayItemDetail == nil {
                AppViewDiagLog.log("client wire inbuilt missing AppViewDisplayItemDetail")
                return .error(AVAppViewClientErrors.inner)
            }
            if requestType == UInt32(AppViewRequestTypeInbuiltAttrModification),
               let detail = attachment.data as? AppViewDisplayItemDetail {
                AppViewDiagLog.log("client wire inbuilt detailOid=\(detail.displayItemOid)")
            }
            if requestType == UInt32(AppViewRequestTypeCustomAttrModification) {
                AppViewDiagLog.log("client wire custom ACK hasError=\(attachment.error != nil)")
            }
            return .just(attachment.data)
        }
    }

    private func requestTyped<T>(
        withType requestType: UInt32,
        wirePayload: WireClientRequestPayload,
        map: @escaping (Any?) throws -> T
    ) -> Single<T> {
        requestObservable(withType: requestType, wirePayload: wirePayload)
            .take(1)
            .asSingle()
            .map { try map($0) }
    }

    private func cancelRequest(withType requestType: UInt32) {
        guard let channel else { return }
        AVConnectionManager.sharedInstance.cancelRequest(withType: requestType, channel: channel)
    }
}
