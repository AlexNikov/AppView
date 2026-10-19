import Foundation
import AppViewShared

/// Peertalk transport surface for the mac AppView client (`AVAsyncPeerChannel` over `actor PTChannel`).
public protocol AVPeerChannel: AnyObject {
    var targetPort: Int { get }
    var isConnected: Bool { get }
    func sendFrame(
        ofType type: UInt32,
        tag: UInt32,
        withPayload payload: dispatch_data_t?,
        callback: ((NSError?) -> Void)?
    )
    func close()
    func cancel()
}
