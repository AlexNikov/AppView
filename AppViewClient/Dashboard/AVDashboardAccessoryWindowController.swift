import AppKit
import AppViewShared

final class AVDashboardAccessoryWindowController: AVWindowController, NSWindowDelegate {
    weak var delegate: AVDashboardAccessoryWindowControllerDelegate?

    private var groupID: AppViewAttrGroupIdentifier = ""
    private weak var dashboardController: AVDashboardViewController?
    private var sectionViews: [AppViewAttrSectionIdentifier: AVDashboardSectionView] = [:]

    init(dashboardController: AVDashboardViewController, attrGroupID: AppViewAttrGroupIdentifier) {
        self.groupID = attrGroupID
        self.dashboardController = dashboardController
        let panel = AVPopPanel(size: NSSize(width: 400, height: 100))
        super.init(window: panel)
        panel.delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func render(withAttrSections sections: [AppViewAttributesSection]) -> NSSize {
        var needlessViews = Array(sectionViews.values)
        for (idx, attrSec) in sections.enumerated() {
            let view: AVDashboardSectionView
            if let existing = sectionViews[attrSec.identifier ?? ""] {
                view = existing
                needlessViews.removeAll { $0 === existing }
                view.isHidden = false
            } else {
                view = AVDashboardSectionView()
                sectionViews[attrSec.identifier ?? ""] = view
            }
            view.dashboardViewController = dashboardController
            view.manageState = .canAdd
            view.attrSection = attrSec
            view.showTopSeparator = idx != 0
            window?.contentView?.addSubview(view)
        }
        needlessViews.forEach { $0.isHidden = true }

        let normalSecWidth = DashboardViewWidth - DashboardHorInset * 2
        var y: CGFloat = 8
        for secID in AppViewDashboardBlueprint.sectionIDs(forGroupID: groupID) {
            guard let view = sectionViews[secID], !view.isHidden else { continue }
            lk(view).x(DashboardHorInset).width(normalSecWidth - DashboardHorInset * 2).heightToFit().y(y)
            y = view.frame.maxY + DashboardSectionMarginTop
        }
        return NSSize(width: normalSecWidth + 23, height: y)
    }

    func windowWillClose(_ notification: Notification) {
        delegate?.dashboardAccessoryWindowControllerWillClose(self)
    }
}

protocol AVDashboardAccessoryWindowControllerDelegate: AnyObject {
    func dashboardAccessoryWindowControllerWillClose(_ controller: AVDashboardAccessoryWindowController)
}
