import Foundation
import AppViewShared

extension AVConnectionManager {
    private static let wireScreenshotCoordinator = AVWireScreenshotCoordinator()

    /// Wire v2 multiplexes `AVJS` / `AVPG` frame types; Peertalk requests keep `AppViewRequestType*` as `type`.
    static func lk_activeRequest(
        on channel: AVPeerChannel,
        frameType type: UInt32,
        tag: UInt32
    ) -> AVConnectionRequest? {
        let requests = AVConnectionManager.sharedInstance.activeRequestSet(for: channel)
        if wireV2FrameTypes.contains(Int(type)) {
            return requests?.appview_firstFiltered { obj in
                (obj as? AVConnectionRequest)?.tag == tag
            } as? AVConnectionRequest
        }
        return requests?.appview_firstFiltered { obj in
            guard let request = obj as? AVConnectionRequest else { return false }
            return request.type == type && request.tag == tag
        } as? AVConnectionRequest
    }

    static var wireV2FrameTypes: IndexSet {
        IndexSet([Int(AppViewWireFormat.frameTypeJSON), Int(AppViewWireFormat.frameTypeScreenshot)])
    }

    func handleWireV2FrameIfNeeded(
        type: UInt32,
        tag: UInt32,
        data: Data,
        channel: AVPeerChannel,
        activeRequest: AVConnectionRequest?
    ) -> Bool {
        switch type {
        case AppViewWireFormat.frameTypeJSON:
            guard let activeRequest else { return false }
            return handleWireJSONFrame(data: data, tag: tag, activeRequest: activeRequest, channel: channel)
        case AppViewWireFormat.frameTypeScreenshot:
            handleWireScreenshotFrame(data: data, tag: tag, channel: channel, activeRequest: activeRequest)
            return true
        default:
            guard let activeRequest,
                  type == activeRequest.type,
                  data.first == UInt8(ascii: "{") else {
                return false
            }
            return handleWireJSONFrame(data: data, tag: tag, activeRequest: activeRequest, channel: channel)
        }
    }

    private func handleWireJSONFrame(
        data: Data,
        tag: UInt32,
        activeRequest: AVConnectionRequest,
        channel: AVPeerChannel
    ) -> Bool {
        guard let envelope = try? AVWireCodecV2.decodeJSON(WireResponseEnvelope.self, from: data) else {
            AppViewDiagLog.log("client wire JSON decode FAIL type=\(activeRequest.type) tag=\(tag)")
            failWireResponse(
                activeRequest: activeRequest,
                channel: channel,
                reason: "JSON decode failed tag=\(tag)"
            )
            return true
        }
        guard AppViewWireFormat.validateWireVersion(envelope.wireVersion, context: "response") else {
            AppViewDiagLog.log("client wire version FAIL got=\(envelope.wireVersion) tag=\(tag)")
            failWireResponse(
                activeRequest: activeRequest,
                channel: channel,
                reason: "wireVersion=\(envelope.wireVersion) tag=\(tag)"
            )
            return true
        }

        var attachment = AppViewConnectionResponseAttachment()
        if WireRequestResponseMapper.applyResponseEnvelope(envelope, to: &attachment) {
            if let wireDetail = envelope.detail {
                let detail = attachment.data as? AppViewDisplayItemDetail ?? WireHierarchyMapper.appviewDetail(from: wireDetail)
                Self.wireScreenshotCoordinator.storePendingDetail(detail, request: activeRequest, channel: channel)
                flushBufferedWireScreenshots(for: detail.displayItemOid, tag: tag, channel: channel)
            }
            AppViewDiagLog.log(
                "client wire resp OK type=\(activeRequest.type) tag=\(tag) hasDetail=\(envelope.detail != nil) hasError=\(envelope.error != nil)"
            )
            deliverWireAttachment(attachment, activeRequest: activeRequest, channel: channel, envelope: envelope)
            return true
        }

        NSLog(
            "AppViewWireV2 - unexpected response shape type=%u tag=%u hasDetail=%d hasError=%d",
            envelope.requestType,
            tag,
            envelope.detail != nil ? 1 : 0,
            envelope.error != nil ? 1 : 0
        )
        failWireResponse(
            activeRequest: activeRequest,
            channel: channel,
            reason: "Unexpected wire response (type \(envelope.requestType))"
        )
        return true
    }

    private func failWireResponse(
        activeRequest: AVConnectionRequest,
        channel: AVPeerChannel,
        reason: String
    ) {
        NSLog("AppViewWireV2 - %@", reason)
        activeRequest.endTimeoutCount()
        removeActiveRequest(activeRequest, from: channel)
        activeRequest.failBlock?(AVAppViewClientErrors.wireResponseFailed(reason))
    }

    private func handleWireScreenshotFrame(
        data: Data,
        tag: UInt32,
        channel: AVPeerChannel,
        activeRequest: AVConnectionRequest?
    ) {
        guard let parsed = AVWireCodecV2.parseScreenshotPayload(data) else { return }
        guard let image = WireScreenshotImageCoding.appviewImage(from: parsed.imageData, format: parsed.format) else {
            NSLog("AppViewWireV2 - screenshot decode failed oid=%u", parsed.oid)
            return
        }
        if var detail = Self.wireScreenshotCoordinator.pendingDetail(
            for: activeRequest,
            channel: channel,
            tag: tag,
            oid: parsed.oid
        ) {
            switch parsed.kind {
            case .solo:
                detail.soloScreenshot = image
            case .group:
                detail.groupScreenshot = image
            }
            Self.wireScreenshotCoordinator.updatePendingDetail(
                detail,
                request: activeRequest,
                channel: channel,
                tag: tag
            )
        }
        applyWireV2Screenshot(oid: parsed.oid, kind: parsed.kind, image: image, tag: tag, channel: channel)
    }

    /// Applies a wire v2 screenshot directly onto `AppViewDisplayItem` by oid (does not require pending JSON detail).
    private func applyWireV2Screenshot(
        oid: UInt,
        kind: WireScreenshotKind,
        image: AppViewImage,
        tag: UInt32,
        channel: AVPeerChannel
    ) {
        guard AVStaticHierarchyDataSource.sharedInstance.displayItem(withOid: oid) != nil else {
            Self.wireScreenshotCoordinator.bufferScreenshot(
                oid: oid,
                kind: kind,
                image: image,
                tag: tag,
                channel: channel
            )
            return
        }
        var patch = AppViewDisplayItemDetail()
        patch.displayItemOid = oid
        switch kind {
        case .solo:
            patch.soloScreenshot = image
        case .group:
            patch.groupScreenshot = image
        }
        applyWireV2ScreenshotToHierarchy(patch)
    }

    private func applyWireV2ScreenshotToHierarchy(_ detail: AppViewDisplayItemDetail) {
        let apply = {
            AVStaticHierarchyDataSource.sharedInstance.modify(with: detail)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func deliverWireAttachment(
        _ attachment: AppViewConnectionResponseAttachment,
        activeRequest: AVConnectionRequest,
        channel: AVPeerChannel,
        envelope: WireResponseEnvelope
    ) {
        let deliver = { [self] in
            if attachment.appIsInBackground {
                activeRequest.endTimeoutCount()
                removeActiveRequest(activeRequest, from: channel)
                activeRequest.failBlock?(AVAppViewClientErrors.pingFailForBackgroundState())
                return
            }

            activeRequest.succBlock?(attachment)

            var hasReceivedAllResponses = false
            if attachment.dataTotalCount > 0 {
                activeRequest.receivedDataCount += attachment.currentDataCount
                if activeRequest.receivedDataCount >= attachment.dataTotalCount {
                    hasReceivedAllResponses = true
                }
            } else {
                hasReceivedAllResponses = true
            }

            if hasReceivedAllResponses {
                activeRequest.endTimeoutCount()
                removeActiveRequest(activeRequest, from: channel)
                flushAllBufferedWireScreenshots(for: activeRequest.tag, channel: channel)
                Self.wireScreenshotCoordinator.clearPendingState(
                    for: activeRequest.tag,
                    channel: channel,
                    request: activeRequest
                )
                activeRequest.completionBlock?()
            } else {
                activeRequest.resetTimeoutCount()
            }
            _ = envelope
        }
        if Thread.isMainThread {
            deliver()
        } else {
            DispatchQueue.main.async(execute: deliver)
        }
    }

    private func flushBufferedWireScreenshots(for oid: UInt, tag: UInt32, channel: AVPeerChannel) {
        Self.wireScreenshotCoordinator.flushBufferedScreenshots(for: oid, tag: tag, channel: channel) {
            [self] oid, kind, image in
            applyWireV2Screenshot(oid: oid, kind: kind, image: image, tag: tag, channel: channel)
        }
    }

    private func flushAllBufferedWireScreenshots(for tag: UInt32, channel: AVPeerChannel) {
        Self.wireScreenshotCoordinator.flushAllBufferedScreenshots(for: tag, channel: channel) {
            [self] oid, kind, image in
            applyWireV2Screenshot(oid: oid, kind: kind, image: image, tag: tag, channel: channel)
        }
    }

    /// Apply screenshots that arrived before `displayItem(withOid:)` was ready.
    func flushWireScreenshotBuffers(on channel: AVPeerChannel?) {
        guard let channel else { return }
        Self.wireScreenshotCoordinator.flushAllBufferedOnChannel(channel) {
            [self] oid, tag, kind, image in
            applyWireV2Screenshot(oid: oid, kind: kind, image: image, tag: tag, channel: channel)
        }
    }

    func encodeWireV2RequestPayload(
        requestType: UInt32,
        tag: UInt32,
        data: NSObject? = nil,
        wirePayload: WireClientRequestPayload? = nil
    ) throws -> Data {
        let envelope: WireRequestEnvelope
        if let wirePayload {
            envelope = wirePayload.envelope(requestType: requestType, tag: tag)
        } else {
            envelope = WireRequestResponseMapper.requestEnvelope(
                requestType: requestType,
                tag: tag,
                data: data
            )
        }
        return try AVWireCodecV2.encodeJSON(envelope)
    }

    static func isWirePushType(_ pushType: UInt32) -> Bool {
        AppViewWirePushTypes.all.contains(pushType)
    }

    func encodeWireV2PushPayload(pushType: UInt32) throws -> Data {
        try AVWireCodecV2.encodeJSON(WirePushEnvelope(pushType: pushType))
    }

}
