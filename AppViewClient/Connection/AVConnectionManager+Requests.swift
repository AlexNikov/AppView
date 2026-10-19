import Foundation
import AppViewShared
import RxSwift

extension AVConnectionManager {
    private static let requestTypesSkippingPreflightPing: Set<UInt32> = [
        UInt32(AppViewRequestTypeInbuiltAttrModification),
        UInt32(AppViewRequestTypeCustomAttrModification),
        UInt32(AppViewRequestTypeAttrModificationPatch),
        UInt32(AppViewRequestTypeAllAttrGroups),
        // Lightweight background fetch for console autocomplete; no blocking on ping.
        UInt32(AppViewRequestTypeAllSelectorNames),
    ]

    // MARK: - Request

    public func push(withType pushType: UInt32, data: NSObject?, channel: AVPeerChannel?) {
        guard let channel, channel.isConnected else { return }

        do {
            guard Self.isWirePushType(pushType) else {
                NSLog("AppViewWireV2 - unsupported push type:%u", pushType)
                return
            }
            let jsonData = try encodeWireV2PushPayload(pushType: pushType)
            let payload = (jsonData as NSData).createReferencingDispatchData()
            NSLog("AppViewClient - pushData, type:%@", NSNumber(value: pushType))
            channel.sendFrame(ofType: pushType, tag: 0, withPayload: payload, callback: nil)
        } catch {
            assertionFailure()
        }
    }

    public func request(
        withType requestType: UInt32,
        data requestData: NSObject?,
        channel: AVPeerChannel?,
        wirePayload: WireClientRequestPayload? = nil
    ) -> Observable<AppViewPair> {
        Observable.create { observer in
            let sendPayload: () -> Void = {
                self.request(
                    withType: requestType,
                    channel: channel,
                    data: requestData,
                    wirePayload: wirePayload,
                    timeoutInterval: AVWireClientRequestTimeout.interval(forRequestType: requestType),
                    succ: { responseData in
                        observer.onNext(AppViewPair(first: responseData, second: channel))
                    },
                    fail: { observer.onError($0) },
                    completion: { observer.onCompleted() }
                )
            }

            if Self.requestTypesSkippingPreflightPing.contains(requestType) {
                sendPayload()
                return Disposables.create()
            }

            self.request(
                withType: UInt32(AppViewRequestTypePing),
                channel: channel,
                data: nil,
                timeoutInterval: AVWireClientRequestTimeout.pingInterval(beforeRequestType: requestType),
                succ: { pingResponse in
                    guard let pingResponse = pingResponse as? AppViewConnectionResponseAttachment else {
                        observer.onError(AVAppViewClientErrors.inner)
                        return
                    }
                    if let versionErr = self.checkServerVersion(with: pingResponse) {
                        observer.onError(versionErr)
                        return
                    }
                    sendPayload()
                },
                fail: { observer.onError($0) },
                completion: nil
            )
            return Disposables.create()
        }
    }

    public func cancelRequest(withType requestType: UInt32, channel: AVPeerChannel?) {
        cancelRequest(withType: requestType, channel: channel, notifyDiscard: false)
    }

    public func cancelRequest(withType requestType: UInt32, channel: AVPeerChannel?, notifyDiscard: Bool) {
        guard let channel else { return }
        guard
            let activeRequest = activeRequestSet(for: channel)?.appview_firstFiltered({ obj in
                guard let request = obj as? AVConnectionRequest else { return false }
                return request.type == requestType
            }) as? AVConnectionRequest
        else {
            return
        }

        activeRequest.endTimeoutCount()
        removeActiveRequest(activeRequest, from: channel)
        if notifyDiscard, let failBlock = activeRequest.failBlock {
            failBlock(AVAppViewClientErrors.discard())
        }
        activeRequest.completionBlock?()
        NSLog("AppView - 用户手动取消 request, type:%@", NSNumber(value: requestType))
    }

    private func checkServerVersion(with pingResponse: AppViewConnectionResponseAttachment) -> NSError? {
        let serverVersion = pingResponse.appviewServerVersion
        if serverVersion == -1 || serverVersion == 100 {
            return AVAppViewClientErrors.serverVersionTooLow()
        }
        if serverVersion > APPVIEW_SUPPORTED_SERVER_MAX {
            return AVAppViewClientErrors.serverVersionTooHigh()
        }
        if serverVersion < APPVIEW_SUPPORTED_SERVER_MIN {
            return AVAppViewClientErrors.serverVersionTooLow()
        }
        return nil
    }

    private func request(
        withType requestType: UInt32,
        channel: AVPeerChannel?,
        data: NSObject?,
        wirePayload: WireClientRequestPayload? = nil,
        timeoutInterval: TimeInterval,
        succ succBlock: ((Any?) -> Void)?,
        fail failBlock: ((NSError) -> Void)?,
        completion completionBlock: (() -> Void)?
    ) {
        guard let channel else {
            assertionFailure()
            failBlock?(AVAppViewClientErrors.inner)
            return
        }
        guard channel.isConnected else {
            failBlock?(AVAppViewClientErrors.noConnect)
            return
        }

        if let activeRequests = activeRequestSet(for: channel), activeRequests.count > 0, requestType != UInt32(AppViewRequestTypePing) {
            let requestsToDiscard = activeRequests.appview_filter { obj in
                guard let request = obj as? AVConnectionRequest else { return false }
                return request.type == requestType
            }
            for case let request as AVConnectionRequest in requestsToDiscard {
                request.endTimeoutCount()
                removeActiveRequest(request, from: channel)
                request.failBlock?(AVAppViewClientErrors.discard())
                NSLog("AppViewClient - will discard request, type:%@, tag:%@", NSNumber(value: request.type), NSNumber(value: request.tag))
            }
        }

        let request = AVConnectionRequest()
        request.type = requestType
        request.tag = allocateRequestTag()
        request.succBlock = succBlock
        request.failBlock = { error in
            if let error = error as NSError? {
                failBlock?(error)
            }
        }
        request.completionBlock = completionBlock
        request.timeoutInterval = timeoutInterval
        request.timeoutBlock = { [weak channel] selfRequest in
            guard let channel else { return }
            if let failBlock = selfRequest.failBlock {
                failBlock(AVAppViewClientErrors.timeout())
            }
            self.removeActiveRequest(selfRequest, from: channel)
        }

        do {
            let jsonData = try encodeWireV2RequestPayload(
                requestType: requestType,
                tag: request.tag,
                data: data,
                wirePayload: wirePayload
            )
            // Peertalk frame type = AppViewRequestType*; payload is JSON.
            let frameType = requestType
            let payload = (jsonData as NSData).createReferencingDispatchData()
            // Register before send — loopback wire v2 responses can arrive before sendFrame's callback.
            let activeRequests = ensureActiveRequestSet(for: channel)
            activeRequests.add(request)
            channel.sendFrame(ofType: frameType, tag: request.tag, withPayload: payload) { error in
                if let error {
                    self.removeActiveRequest(request, from: channel)
                    failBlock?(AVAppViewClientErrors.peerTalk())
                    _ = error
                } else {
                    request.resetTimeoutCount()
                }
            }
        } catch {
            assertionFailure()
        }
    }
}
