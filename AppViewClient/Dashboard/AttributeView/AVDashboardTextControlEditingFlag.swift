import Foundation

final class AVDashboardTextControlEditingFlag: NSObject {
    static let sharedInstance = AVDashboardTextControlEditingFlag()

    var shouldIgnoreTextEditingChangeEvent = false

    private override init() {
        super.init()
    }
}
