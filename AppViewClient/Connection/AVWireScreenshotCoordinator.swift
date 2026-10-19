//
//  AVWireScreenshotCoordinator.swift
//  AppView
//

import Foundation
import AppViewShared

/// Buffers wire v2 screenshots and pending detail JSON until hierarchy oids exist.
final class AVWireScreenshotCoordinator {
    struct BufferedScreenshot {
        var solo: AppViewImage?
        var group: AppViewImage?
    }

    private var pendingByRequest: [ObjectIdentifier: [UInt: AppViewDisplayItemDetail]] = [:]
    private var pendingByChannelTag: [ObjectIdentifier: [UInt32: [UInt: AppViewDisplayItemDetail]]] = [:]
    private var bufferedByChannel: [ObjectIdentifier: [UInt32: [UInt: BufferedScreenshot]]] = [:]

    func storePendingDetail(
        _ detail: AppViewDisplayItemDetail,
        request: AVConnectionRequest,
        channel: AVPeerChannel
    ) {
        let requestKey = ObjectIdentifier(request)
        var map = pendingByRequest[requestKey] ?? [:]
        map[detail.displayItemOid] = detail
        pendingByRequest[requestKey] = map

        let channelKey = ObjectIdentifier(channel)
        var byTag = pendingByChannelTag[channelKey] ?? [:]
        var tagMap = byTag[request.tag] ?? [:]
        tagMap[detail.displayItemOid] = detail
        byTag[request.tag] = tagMap
        pendingByChannelTag[channelKey] = byTag
    }

    func pendingDetail(
        for request: AVConnectionRequest?,
        channel: AVPeerChannel,
        tag: UInt32,
        oid: UInt
    ) -> AppViewDisplayItemDetail? {
        if let request {
            let map = pendingByRequest[ObjectIdentifier(request)]
            if let detail = map?[oid] { return detail }
        }
        return pendingByChannelTag[ObjectIdentifier(channel)]?[tag]?[oid]
    }

    func updatePendingDetail(
        _ detail: AppViewDisplayItemDetail,
        request: AVConnectionRequest?,
        channel: AVPeerChannel,
        tag: UInt32
    ) {
        if let request {
            let requestKey = ObjectIdentifier(request)
            var map = pendingByRequest[requestKey] ?? [:]
            map[detail.displayItemOid] = detail
            pendingByRequest[requestKey] = map
        }
        let channelKey = ObjectIdentifier(channel)
        var byTag = pendingByChannelTag[channelKey] ?? [:]
        var tagMap = byTag[tag] ?? [:]
        tagMap[detail.displayItemOid] = detail
        byTag[tag] = tagMap
        pendingByChannelTag[channelKey] = byTag
    }

    func bufferScreenshot(
        oid: UInt,
        kind: WireScreenshotKind,
        image: AppViewImage,
        tag: UInt32,
        channel: AVPeerChannel
    ) {
        let channelKey = ObjectIdentifier(channel)
        var byTag = bufferedByChannel[channelKey] ?? [:]
        var tagMap = byTag[tag] ?? [:]
        var slot = tagMap[oid] ?? BufferedScreenshot()
        switch kind {
        case .solo:
            slot.solo = image
        case .group:
            slot.group = image
        }
        tagMap[oid] = slot
        byTag[tag] = tagMap
        bufferedByChannel[channelKey] = byTag
    }

    func flushBufferedScreenshots(
        for oid: UInt,
        tag: UInt32,
        channel: AVPeerChannel,
        apply: (_ oid: UInt, _ kind: WireScreenshotKind, _ image: AppViewImage) -> Void
    ) {
        let channelKey = ObjectIdentifier(channel)
        guard var byTag = bufferedByChannel[channelKey],
              var tagMap = byTag[tag],
              let slot = tagMap.removeValue(forKey: oid) else {
            return
        }
        if tagMap.isEmpty {
            byTag.removeValue(forKey: tag)
        } else {
            byTag[tag] = tagMap
        }
        if byTag.isEmpty {
            bufferedByChannel.removeValue(forKey: channelKey)
        } else {
            bufferedByChannel[channelKey] = byTag
        }

        if let solo = slot.solo {
            apply(oid, .solo, solo)
        }
        if let group = slot.group {
            apply(oid, .group, group)
        }
    }

    func flushAllBufferedScreenshots(
        for tag: UInt32,
        channel: AVPeerChannel,
        apply: (_ oid: UInt, _ kind: WireScreenshotKind, _ image: AppViewImage) -> Void
    ) {
        guard let tagMap = bufferedByChannel[ObjectIdentifier(channel)]?[tag] else { return }
        for oid in tagMap.keys {
            flushBufferedScreenshots(for: oid, tag: tag, channel: channel, apply: apply)
        }
    }

    func flushAllBufferedOnChannel(
        _ channel: AVPeerChannel,
        apply: (_ oid: UInt, _ tag: UInt32, _ kind: WireScreenshotKind, _ image: AppViewImage) -> Void
    ) {
        guard let byTag = bufferedByChannel[ObjectIdentifier(channel)] else { return }
        for tag in byTag.keys {
            flushAllBufferedScreenshots(for: tag, channel: channel) { oid, kind, image in
                apply(oid, tag, kind, image)
            }
        }
    }

    func clearPendingState(
        for tag: UInt32,
        channel: AVPeerChannel,
        request: AVConnectionRequest
    ) {
        pendingByRequest.removeValue(forKey: ObjectIdentifier(request))
        let channelKey = ObjectIdentifier(channel)
        if var byTag = pendingByChannelTag[channelKey] {
            byTag.removeValue(forKey: tag)
            if byTag.isEmpty {
                pendingByChannelTag.removeValue(forKey: channelKey)
            } else {
                pendingByChannelTag[channelKey] = byTag
            }
        }
    }
}
