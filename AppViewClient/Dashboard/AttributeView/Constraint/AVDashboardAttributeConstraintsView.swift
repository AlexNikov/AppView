import AppKit
import AppViewShared

final class AVDashboardAttributeConstraintsView: AVDashboardAttributeRowsView {
    override func makeRow() -> AVDashboardAttributeRowControl {
        let row = AVDashboardAttributeConstraintsItemControl()
        row.onClick = { [weak self, weak row] in
            guard let row else { return }
            self?.showPopover(for: row)
        }
        row.onHoverChange = { [weak self, weak row] isHovering in
            guard let row else { return }
            self?.updateHoveredParticipant(for: row, isHovering: isHovering)
        }
        return row
    }

    /// Hovering a row hovers the other view in the constraint, so it lights up in the tree and the preview.
    private func updateHoveredParticipant(for row: AVDashboardAttributeConstraintsItemControl, isHovering: Bool) {
        guard let dataSource = dashboardViewController?.currentDataSource(),
              let constraint = row.constraint,
              let target = Self.otherParticipant(of: constraint, in: dataSource) else { return }
        if isHovering {
            dataSource.hoveredItem = target
        } else if dataSource.hoveredItem === target {
            dataSource.hoveredItem = nil
        }
    }

    /// Ivar the view is stored in, as the tree shows it: `_label` → `label`, Swift lazy storage → property name.
    private static func variableName(for object: AppViewObject, in dataSource: AVHierarchyDataSource?) -> String? {
        let traces = dataSource?.displayItem(withOid: object.oid)?.viewObject?.ivarTraces ?? object.ivarTraces ?? []
        let names = Set(traces.compactMap(\.ivarName).filter { !$0.isEmpty }).sorted()
        guard var name = names.first else { return nil }
        if let range = name.range(of: "$__lazy_storage_$_") {
            name = String(name[range.upperBound...])
        } else if name.hasPrefix("_"), name.count > 1 {
            name.removeFirst()
        }
        return name.isEmpty ? nil : name
    }

    /// The second item, or the first one when the second is this view, nil or a layout guide (not in the tree).
    private static func otherParticipant(
        of constraint: AppViewAutoLayoutConstraint,
        in dataSource: AVHierarchyDataSource
    ) -> AppViewDisplayItem? {
        let candidates = [
            (constraint.secondItem, constraint.secondItemType),
            (constraint.firstItem, constraint.firstItemType),
        ]
        for (object, type) in candidates where type != .self && type != .nil {
            if let oid = object?.oid, let item = dataSource.displayItem(withOid: oid) {
                return item
            }
        }
        return nil
    }

    override func renderWithAttribute() {
        super.renderWithAttribute()
        var rawData: [AppViewAutoLayoutConstraint] = []
        if case .customObject(let rawValue)? = attribute?.value,
           let constraints = rawValue as? [AppViewAutoLayoutConstraint] {
            rawData = constraints
        }
        let sorted = sortedRawData(from: rawData)
        let highlight = dashboardViewController?.layoutHighlight ?? AppViewLayoutIssueHighlight()
        let dataSource = dashboardViewController?.currentDataSource()
        renderRows(count: sorted.count) { row, index in
            guard let row = row as? AVDashboardAttributeConstraintsItemControl else { return }
            row.variableName = { [weak dataSource] object in Self.variableName(for: object, in: dataSource) }
            row.constraint = sorted[index]
            row.isWarningHighlighted = highlight.highlights(snapshotID: sorted[index].snapshotID)
        }
    }

    /// Paints the rows the highlight names; an empty highlight clears them.
    func applyWarningHighlight(_ highlight: AppViewLayoutIssueHighlight) {
        for case let row as AVDashboardAttributeConstraintsItemControl in visibleRows {
            row.isWarningHighlighted = highlight.highlights(snapshotID: row.constraint?.snapshotID)
        }
    }

    func firstHighlightedControl() -> AVDashboardAttributeConstraintsItemControl? {
        for case let row as AVDashboardAttributeConstraintsItemControl in visibleRows where row.isWarningHighlighted {
            return row
        }
        return nil
    }

    private func showPopover(for control: AVDashboardAttributeConstraintsItemControl) {
        guard let constraint = control.constraint else { return }
        let vc = AVConstraintPopoverController(constraint: constraint)
        let popover = NSPopover()
        popover.animates = false
        popover.behavior = .transient
        popover.contentSize = vc.contentSize()
        popover.contentViewController = vc
        vc.requestJumpingToObject = { [weak popover, weak self] appviewObj in
            popover?.close()
            guard let self, let dataSource = self.dashboardViewController?.currentDataSource(),
                  let item = dataSource.displayItem(withOid: appviewObj.oid) else { return }
            if !item.displayingInHierarchy {
                dataSource.expandToShowItem(item)
            }
            dataSource.selectedItem = item
        }
        popover.show(relativeTo: NSRect(x: 0, y: 0, width: control.bounds.width, height: control.bounds.height), of: control, preferredEdge: .maxX)
    }

    private func sortedRawData(from rawData: [AppViewAutoLayoutConstraint]) -> [AppViewAutoLayoutConstraint] {
        rawData.sorted { obj1, obj2 in
            if obj1.effective != obj2.effective { return obj1.effective }
            if obj1.firstItemType != obj2.firstItemType { return obj1.firstItemType.rawValue < obj2.firstItemType.rawValue }
            return obj1.firstAttribute < obj2.firstAttribute
        }
    }
}
