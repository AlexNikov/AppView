import Foundation
import AppViewShared

enum AVAppViewClientErrors {
    static let domain = AppViewErrorDomain

    static var inner: NSError {
        NSError(
            domain: domain,
            code: Int(AppViewErrCode_Inner),
            userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString(
                    "The operation failed due to an inner error.",
                    comment: ""
                ),
            ]
        )
    }

    static func wireResponseFailed(_ reason: String) -> NSError {
        NSError(
            domain: domain,
            code: Int(AppViewErrCode_Inner),
            userInfo: [
                NSLocalizedDescriptionKey: reason,
                NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(
                    "Rebuild AppView.app and the iOS demo (pod install in AppView/ and AppViewCustomInfoDemo), then reconnect.",
                    comment: ""
                ),
            ]
        )
    }

    static var noConnect: NSError {
        NSError(
            domain: domain,
            code: Int(AppViewErrCode_NoConnect),
            userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString(
                    "The operation failed due to disconnection with the iOS app.",
                    comment: ""
                ),
            ]
        )
    }

    static var objectNotFound: NSError {
        NSError(
            domain: domain,
            code: Int(AppViewErrCode_ObjectNotFound),
            userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString(
                    "Failed to get target object in iOS app",
                    comment: ""
                ),
                NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(
                    "Perhaps the related object was deallocated. You can reload AppView to get newest data.",
                    comment: ""
                ),
            ]
        )
    }

    static func timeout() -> NSError {
        NSError(
            domain: domain,
            code: Int(AppViewErrCode_Timeout),
            userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("Request timeout", comment: ""),
                NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(
                    "Perhaps your iOS app is paused with breakpoint in Xcode, blocked by other tasks in main thread, or moved to background state.",
                    comment: ""
                ),
            ]
        )
    }

    static func discard() -> NSError {
        NSError(
            domain: domain,
            code: Int(AppViewErrCode_Discard),
            userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString(
                    "The request is discarded due to a newer same request.",
                    comment: ""
                ),
            ]
        )
    }

    static func peerTalk() -> NSError {
        NSError(
            domain: domain,
            code: Int(AppViewErrCode_PeerTalk),
            userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString(
                    "The operation failed due to an inner error.",
                    comment: ""
                ),
            ]
        )
    }

    static func pingFailForBackgroundState() -> NSError {
        NSError(
            domain: domain,
            code: Int(AppViewErrCode_PingFailForBackgroundState),
            userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString(
                    "The operation failed because target iOS app has entered to the background state.",
                    comment: ""
                ),
            ]
        )
    }

    static func serverVersionTooLow() -> NSError {
        NSError(
            domain: domain,
            code: Int(AppViewErrCode_ServerVersionTooLow),
            userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString(
                    "Fail to inspect this iOS app due to a version problem.",
                    comment: ""
                ),
                NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(
                    "Please update AppViewServer.framework linked with target iOS App to a newer version.",
                    comment: ""
                ),
            ]
        )
    }

    static func serverVersionTooHigh() -> NSError {
        NSError(
            domain: domain,
            code: Int(AppViewErrCode_ServerVersionTooHigh),
            userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("AppView app version is too low.", comment: ""),
                NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(
                    "Target iOS app is linked with a higher version AppViewServer.framework. Please install a newer AppView build.",
                    comment: ""
                ),
            ]
        )
    }
}
