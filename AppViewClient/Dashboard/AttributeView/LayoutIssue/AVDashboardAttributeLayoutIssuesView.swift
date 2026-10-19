import AppKit
import AppViewShared

/// One clickable Layout Issues row.
final class AVDashboardAttributeLayoutIssueItemControl: AVDashboardAttributeRowControl {
    var issue: AppViewLayoutIssue? {
        didSet { updateAppearance() }
    }

    /// True while this issue's constraints are highlighted in the Constraints list.
    var isActiveIssue = false {
        didSet {
            guard isActiveIssue != oldValue else { return }
            updateAppearance()
        }
    }

    private func updateAppearance() {
        guard let issue else { return }
        let countText = issue.constraintIDs.isEmpty ? "" : " (\(issue.constraintIDs.count))"
        label.stringValue = "⚠︎ \(issue.title)\(countText)"
        label.textColor = .systemOrange
        label.font = isActiveIssue ? NSFont.boldSystemFont(ofSize: 12) : NSFontMake(12)
        needsLayout = true
    }
}

/// `al_l`: ambiguous / conflict rows. Clicking one highlights its constraints in the Constraints section.
final class AVDashboardAttributeLayoutIssuesView: AVDashboardAttributeRowsView {
    override var rowSpacing: CGFloat { 6 }

    override func makeRow() -> AVDashboardAttributeRowControl {
        let row = AVDashboardAttributeLayoutIssueItemControl()
        row.onClick = { [weak self, weak row] in
            guard let issue = row?.issue else { return }
            self?.dashboardViewController?.handleLayoutIssueClick(issue)
        }
        return row
    }

    override func renderWithAttribute() {
        super.renderWithAttribute()
        var issues: [AppViewLayoutIssue] = []
        if case .customObject(let rawValue)? = attribute?.value, let rows = rawValue as? [AppViewLayoutIssue] {
            issues = rows
        }
        renderRows(count: issues.count) { row, index in
            (row as? AVDashboardAttributeLayoutIssueItemControl)?.issue = issues[index]
        }
        refreshActiveState()
    }

    /// Bold the row whose issue is currently highlighted.
    func refreshActiveState() {
        let activeKey = dashboardViewController?.highlightedIssueKey
        for case let row as AVDashboardAttributeLayoutIssueItemControl in visibleRows {
            row.isActiveIssue = activeKey != nil && row.issue.map(AppViewLayoutIssueHighlight.key(for:)) == activeKey
        }
    }
}
