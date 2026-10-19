import Foundation
import AppViewShared
import RxRelay
import RxSwift

public final class AVConnectionManager: NSObject {
    public static let sharedInstance = AVConnectionManager()

    private let channelWillEndRelay = PublishRelay<AVPeerChannel>()
    public var channelWillEnd: Observable<AVPeerChannel> {
        channelWillEndRelay.asObservable()
    }

    var peerActiveRequests: [ObjectIdentifier: NSMutableSet] = [:]

    private let didReceivePushRelay = PublishRelay<AppViewTriple>()
    public var didReceivePush: Observable<AppViewTriple> {
        didReceivePushRelay.asObservable()
    }

    var allSimulatorPorts: [AVSimulatorConnectionPort] = []
    var allUSBPorts: [AVUSBConnectionPort] = []
    /// usbmux `Properties.DeviceName` keyed by DeviceID (for launch tiles before Peertalk connects).
    var attachedUSBDeviceLabels: [UInt32: String] = [:]

    /// True when usbmux reported at least one attached iOS device (may still be waiting for demo listen).
    public var hasAttachedUSBDevices: Bool { !allUSBPorts.isEmpty }

    func uniqueAttachedUSBDeviceIDs() -> [NSNumber] {
        var seen = Set<UInt32>()
        var ids: [NSNumber] = []
        for port in allUSBPorts {
            guard let deviceID = port.deviceID else { continue }
            let raw = deviceID.uint32Value
            if seen.insert(raw).inserted {
                ids.append(deviceID)
            }
        }
        return ids
    }

    func usbDeviceLabel(for deviceID: NSNumber) -> String? {
        attachedUSBDeviceLabels[deviceID.uint32Value]
    }

    public func isUSBPeertalkPort(_ port: Int) -> Bool {
        port >= Int(AppViewUSBDeviceIPv4PortNumberStart) && port <= Int(AppViewUSBDeviceIPv4PortNumberEnd)
    }

    public func isSimulatorPeertalkPort(_ port: Int) -> Bool {
        port >= Int(AppViewSimulatorIPv4PortNumberStart) && port <= Int(AppViewSimulatorIPv4PortNumberEnd)
    }

    public func channelUsesUSB(_ channel: AVPeerChannel?) -> Bool {
        guard let channel else { return false }
        return isUSBPeertalkPort(channel.targetPort)
    }

    /// Simulator app may appear before the USB demo starts listening — keep polling instead of auto-enter.
    public func shouldDeferLaunchAutoEnterForPendingUSB(usableApps: [AVInspectableApp]) -> Bool {
        guard hasAttachedUSBDevices else { return false }
        return !usableApps.contains { channelUsesUSB($0.channel) }
    }

    public internal(set) var mcpLastConnectSnapshot: AVMCPConnectSnapshot?

    /// MCP verify: one-shot `forceFreshDiscovery` on the next `discover-apps` (set via `APPVIEW_FORCE_DISCOVER_ONCE=1` on launch).
    var mcpForceFreshDiscoverOnNextFetch = ProcessInfo.processInfo.environment["APPVIEW_FORCE_DISCOVER_ONCE"] == "1"

    func consumeMCPForceFreshDiscover() -> Bool {
        guard mcpForceFreshDiscoverOnNextFetch else { return false }
        mcpForceFreshDiscoverOnNextFetch = false
        return true
    }

    public func clearMCPSessionSnapshots() {
        mcpLastConnectSnapshot = nil
    }

    private static let pushFrameTypes: IndexSet = {
        IndexSet(AppViewWirePushTypes.all.map { Int($0) })
    }()

    private static let requestTagLock = NSLock()
    private static var nextRequestTag: UInt32 = 1

    func allocateRequestTag() -> UInt32 {
        Self.requestTagLock.lock()
        defer { Self.requestTagLock.unlock() }
        let tag = Self.nextRequestTag
        Self.nextRequestTag &+= 1
        if Self.nextRequestTag == 0 {
            Self.nextRequestTag = 1
        }
        return tag
    }

    private override init() {
        super.init()

        allSimulatorPorts = (Int32(AppViewSimulatorIPv4PortNumberStart) ... Int32(AppViewSimulatorIPv4PortNumberEnd)).map { number in
            let port = AVSimulatorConnectionPort()
            port.portNumber = number
            return port
        }

        startListeningForUSBDevices()
        AVServerVersionRequestor.shared.preload()
    }

    func shouldAcceptPeerFrame(
        channel: AVPeerChannel,
        type: UInt32,
        tag: UInt32,
        payloadSize: UInt32
    ) -> Bool {
        _ = payloadSize
        if Self.pushFrameTypes.contains(Int(type)) {
            return true
        }

        if Self.wireV2FrameTypes.contains(Int(type)) {
            return true
        }

        if Self.lk_activeRequest(on: channel, frameType: type, tag: tag) != nil {
            return true
        }

        NSLog("AppViewClient - will refuse, type:%@, tag:%@", NSNumber(value: type), NSNumber(value: tag))
        return false
    }

    func deliverIncomingPeerFrame(
        channel: AVPeerChannel,
        type: UInt32,
        tag: UInt32,
        payload: Data?
    ) {
        if Self.pushFrameTypes.contains(Int(type)) {
            let data = payload ?? Data()
            guard !data.isEmpty else { return }
            guard let pushEnvelope = try? AVWireCodecV2.decodeJSON(WirePushEnvelope.self, from: data) else {
                NSLog("AppViewWireV2 - push JSON decode failed type:%u", type)
                return
            }
            guard AppViewWireFormat.validateWireVersion(pushEnvelope.wireVersion, context: "push") else {
                return
            }
            didReceivePushRelay.accept(
                AppViewTriple(
                    first: channel,
                    second: NSNumber(value: pushEnvelope.pushType),
                    third: NSNull()
                )
            )
            return
        }

        let data = payload ?? Data()
        guard !data.isEmpty else {
            return
        }

        let activeRequest = AVConnectionManager.lk_activeRequest(on: channel, frameType: type, tag: tag)

        if handleWireV2FrameIfNeeded(
            type: type,
            tag: tag,
            data: data,
            channel: channel,
            activeRequest: activeRequest
        ) {
            return
        }

        if Self.wireV2FrameTypes.contains(Int(type)) {
            if let activeRequest {
                NSLog("AppViewWireV2 - wire v2 frame decode failed type:%u tag:%u", type, tag)
                activeRequest.endTimeoutCount()
                removeActiveRequest(activeRequest, from: channel)
                activeRequest.failBlock?(AVAppViewClientErrors.inner)
            }
            return
        }

        if let activeRequest {
            NSLog("AppViewWireV2 - legacy NSCoding response rejected type:%u tag:%u", type, tag)
            activeRequest.endTimeoutCount()
            removeActiveRequest(activeRequest, from: channel)
            activeRequest.failBlock?(AVAppViewClientErrors.inner)
        }
    }

    func peerChannelDidEnd(_ channel: AVPeerChannel?, error: NSError?) {
        guard let channel else { return }
        for port in allSimulatorPorts where port.connectedChannel === channel {
            port.connectedChannel = nil
        }
        for port in allUSBPorts where port.connectedChannel === channel {
            port.connectedChannel = nil
        }
        clearActiveRequests(for: channel)
        channelWillEndRelay.accept(channel)
        channel.close()
        _ = error
    }
}
