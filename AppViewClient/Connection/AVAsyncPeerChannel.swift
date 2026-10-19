import Foundation
import AppViewShared

final class AVAsyncPeerChannel: NSObject, AVPeerChannel {
    private(set) var targetPort: Int = 0
    private(set) var isConnected = false

    private let ptChannel: PTChannel
    private weak var manager: AVConnectionManager?
    private var frameTask: Task<Void, Never>?

    init(manager: AVConnectionManager) {
        self.manager = manager
        self.ptChannel = PTChannel()
        super.init()
    }

    deinit {
        frameTask?.cancel()
    }

    func connect(toPort port: UInt16) async throws {
        try await prepareAndConnect {
            try await ptChannel.connect(toPort: port)
        }
        await refreshConnectionState(fallbackPort: Int(port))
    }

    func connect(
        toPort port: Int32,
        over hub: AppViewPTUSBHub,
        deviceID: NSNumber
    ) async throws {
        try await prepareAndConnect {
            try await ptChannel.connect(toPort: port, over: hub, deviceID: deviceID)
        }
        await refreshConnectionState(fallbackPort: Int(port))
    }

    private func prepareAndConnect(_ connect: () async throws -> Void) async throws {
        frameTask?.cancel()
        frameTask = nil
        await ptChannel.restartFrameConsumer()
        try await connect()
        let frames = await ptChannel.frames()
        frameTask = Task { [weak self] in
            await self?.consumeFrames(frames)
        }
    }

    private func refreshConnectionState(fallbackPort: Int) async {
        let port = await ptChannel.targetPort
        targetPort = port > 0 ? port : fallbackPort
        isConnected = await ptChannel.isConnected
    }

    /// Refresh cached transport after iOS relisten or a dead frame consumer (discovery reuse path).
    func reconcileTransportState() async {
        await refreshConnectionState(fallbackPort: targetPort)
        guard await ptChannel.hasActiveTransport, isConnected else {
            isConnected = false
            return
        }
        guard frameTask == nil || frameTask?.isCancelled == true else { return }
        await ptChannel.restartFrameConsumer()
        let frames = await ptChannel.frames()
        frameTask = Task { [weak self] in
            await self?.consumeFrames(frames)
        }
    }

    func sendFrame(
        ofType type: UInt32,
        tag: UInt32,
        withPayload payload: dispatch_data_t?,
        callback: ((NSError?) -> Void)?
    ) {
        let data: Data
        if let payload, let nsData = NSData.data(withContentsOf: payload) {
            data = nsData as Data
        } else {
            data = Data()
        }
        Task {
            await refreshConnectionState(fallbackPort: targetPort)
            guard isConnected else {
                DispatchQueue.main.async {
                    callback?(AVAppViewClientErrors.noConnect as NSError)
                }
                return
            }
            do {
                try await ptChannel.send(type: type, tag: tag, payload: data)
                await refreshConnectionState(fallbackPort: targetPort)
                DispatchQueue.main.async {
                    callback?(nil)
                }
            } catch {
                isConnected = false
                DispatchQueue.main.async {
                    callback?(error as NSError)
                }
            }
        }
    }

    func close() {
        frameTask?.cancel()
        frameTask = nil
        Task {
            await ptChannel.restartFrameConsumer()
            await ptChannel.close()
        }
        isConnected = false
    }

    func cancel() {
        frameTask?.cancel()
        frameTask = nil
        Task {
            await ptChannel.restartFrameConsumer()
            await ptChannel.cancel()
        }
        isConnected = false
    }

    private func consumeFrames(_ stream: AsyncThrowingStream<PTFrame, Error>) async {
        do {
            for try await frame in stream {
                DispatchQueue.main.async { [weak self] in
                    guard let self, let manager = self.manager else { return }
                    guard manager.shouldAcceptPeerFrame(
                        channel: self,
                        type: frame.type,
                        tag: frame.tag,
                        payloadSize: UInt32(frame.payload.count)
                    ) else {
                        return
                    }
                    manager.deliverIncomingPeerFrame(
                        channel: self,
                        type: frame.type,
                        tag: frame.tag,
                        payload: frame.payload
                    )
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isConnected = false
                self.manager?.peerChannelDidEnd(self, error: nil)
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isConnected = false
                self.manager?.peerChannelDidEnd(self, error: error as NSError)
            }
        }
    }
}
