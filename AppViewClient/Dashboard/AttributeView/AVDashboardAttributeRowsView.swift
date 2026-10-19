import AppKit

/// Left-aligned text row that dims while the pointer is over it.
class AVDashboardAttributeRowControl: AVTextControl {
    /// Called with `true` when the pointer enters the row and `false` when it leaves.
    var onHoverChange: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.alignment = .left
        label.font = NSFontMake(12)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func shouldTrackMouseEnteredAndExited() -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        alphaValue = 0.5
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        alphaValue = 1
        onHoverChange?(false)
    }
}

/// Vertical list of reusable rows for one dashboard attribute. Subclasses create and fill the rows.
class AVDashboardAttributeRowsView: AVDashboardAttributeView {
    private var rows: [AVDashboardAttributeRowControl] = []

    var rowSpacing: CGFloat { 8 }

    var visibleRows: [AVDashboardAttributeRowControl] {
        rows.filter { !$0.isHidden }
    }

    func makeRow() -> AVDashboardAttributeRowControl {
        AVDashboardAttributeRowControl()
    }

    /// Shows `count` rows, reusing existing ones, and hides the rest.
    func renderRows(count: Int, configure: (AVDashboardAttributeRowControl, Int) -> Void) {
        while rows.count < count {
            let row = makeRow()
            addSubview(row)
            rows.append(row)
        }
        for (index, row) in rows.enumerated() {
            row.isHidden = index >= count
            guard index < count else { continue }
            configure(row, index)
            row.needsLayout = true
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 0
        for row in visibleRows {
            lk(row).fullFrame().heightToFit().y(y)
            y = row.frame.maxY + rowSpacing
        }
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        let visible = visibleRows
        var height = visible.reduce(0) { $0 + $1.sizeThatFits(limitedSize).height }
        height += rowSpacing * CGFloat(max(0, visible.count - 1))
        return NSSize(width: limitedSize.width, height: height)
    }
}
