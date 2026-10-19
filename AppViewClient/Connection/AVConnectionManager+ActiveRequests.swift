import Foundation
import AppViewShared

extension AVConnectionManager {
    func activeRequestSet(for channel: AVPeerChannel) -> NSMutableSet? {
        peerActiveRequests[ObjectIdentifier(channel)]
    }

    func ensureActiveRequestSet(for channel: AVPeerChannel) -> NSMutableSet {
        let key = ObjectIdentifier(channel)
        if let existing = peerActiveRequests[key] {
            return existing
        }
        let created = NSMutableSet()
        peerActiveRequests[key] = created
        return created
    }

    func removeActiveRequest(_ request: AVConnectionRequest, from channel: AVPeerChannel) {
        activeRequestSet(for: channel)?.remove(request)
    }

    func clearActiveRequests(for channel: AVPeerChannel) {
        peerActiveRequests.removeValue(forKey: ObjectIdentifier(channel))
    }

    /// Fail and drop in-flight Peertalk requests (inspector teardown / MCP reconnect).
    func cancelAllActivePeerRequests() {
        var channels: [AVPeerChannel] = []
        for port in allSimulatorPorts {
            if let channel = port.connectedChannel {
                channels.append(channel)
            }
        }
        for port in allUSBPorts {
            if let channel = port.connectedChannel {
                channels.append(channel)
            }
        }
        for channel in channels {
            cancelActivePeerRequests(on: channel)
        }
    }

    private func cancelActivePeerRequests(on channel: AVPeerChannel) {
        guard let set = activeRequestSet(for: channel) else { return }
        let requests = set.allObjects.compactMap { $0 as? AVConnectionRequest }
        for request in requests {
            request.endTimeoutCount()
            removeActiveRequest(request, from: channel)
            request.failBlock?(AVAppViewClientErrors.discard())
            request.completionBlock?()
        }
    }
}
