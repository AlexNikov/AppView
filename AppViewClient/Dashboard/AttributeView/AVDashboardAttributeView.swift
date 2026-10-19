import AppKit
import AppViewShared

class AVDashboardAttributeView: AVBaseView {
    var attribute: AppViewAttribute? {
        didSet { renderWithAttribute() }
    }

    var valueView: Any?

    weak var dashboardViewController: AVDashboardViewController?

    func canEdit() -> Bool {
        guard let attribute else { return false }
        if attribute.isUserCustom() {
            return !(attribute.customSetterID ?? "").isEmpty
        }
        let setter = AppViewDashboardBlueprint.setter(withAttrID: attribute.identifier ?? "")
        return setter != nil && (dashboardViewController?.isStaticMode ?? false)
    }

    func renderWithAttribute() {}

    func numberOfColumnsOccupied() -> UInt {
        1
    }
}
