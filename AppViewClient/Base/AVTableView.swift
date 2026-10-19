//
//  AVTableView.swift
//  AppView
//

import AppKit

protocol AVTableViewDelegate: AnyObject {
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView?
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool

    func tableView(_ tableView: AVTableView, didSelectRow row: Int)
    func tableView(_ tableView: AVTableView, didHoverAtRow row: Int)
    func tableView(_ tableView: AVTableView, didDoubleClickAtRow row: Int)
    func tableViewDidClickBlankArea(_ tableView: AVTableView)
}

extension AVTableViewDelegate {
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }

    func tableView(_ tableView: AVTableView, didSelectRow row: Int) {}
    func tableView(_ tableView: AVTableView, didHoverAtRow row: Int) {}
    func tableView(_ tableView: AVTableView, didDoubleClickAtRow row: Int) {}
    func tableViewDidClickBlankArea(_ tableView: AVTableView) {}
}

protocol AVTableViewDataSource: AnyObject {
    func numberOfRows(in tableView: NSTableView) -> Int
}

private final class DisableKeyDownTableView: NSTableView {
    weak var responder: NSResponder?

    override func keyDown(with event: NSEvent) {
        responder?.keyDown(with: event)
    }
}

class AVTableView: NSScrollView {
    private(set) var tableView: NSTableView!
    var canScrollHorizontally = true {
        didSet {
            hasHorizontalScroller = canScrollHorizontally
            if !canScrollHorizontally {
                horizontalScrollWidthManager = nil
            }
        }
    }

    weak var delegate: AVTableViewDelegate?
    weak var dataSource: AVTableViewDataSource?

    var adjustsSelectionAutomatically = true
    var adjustsHoverAutomatically = true

    private var horizontalScrollWidthManager: AVTableViewHorizontalScrollWidthManager?
    private var selectionObserverToken: NSObjectProtocol?
    private var hoveredRow = -1 {
        didSet { applyHoveredRowChange(from: oldValue, to: hoveredRow) }
    }
    private var _selectedRow = -1
    private var selectedRow: Int {
        get { _selectedRow }
        set {
            guard adjustsSelectionAutomatically else { return }
            guard newValue != _selectedRow else { return }
            let previous = _selectedRow
            _selectedRow = newValue
            applySelectedRowChange(from: previous, to: newValue)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        adjustsSelectionAutomatically = true
        adjustsHoverAutomatically = true
        _selectedRow = -1
        hoveredRow = -1

        backgroundColor = .clear
        drawsBackground = false
        hasVerticalScroller = true
        autohidesScrollers = true

        let table = DisableKeyDownTableView()
        table.responder = self
        tableView = table
        if #available(macOS 11.0, *) {
            table.style = .plain
        }
        table.delegate = self
        table.dataSource = self
        table.wantsLayer = true
        table.backgroundColor = .clear
        table.headerView = nil
        table.focusRingType = .none
        table.selectionHighlightStyle = .none
        table.intercellSpacing = NSSize(width: 0, height: 0)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column"))
        column.isEditable = false
        table.addTableColumn(column)
        contentView.documentView = table
        table.target = self
        table.action = #selector(handleTableViewDefaultAction)
        table.doubleAction = #selector(handleDoubleClickTableView)

        selectionObserverToken = NotificationCenter.default.addObserver(
            forName: NSTableView.selectionDidChangeNotification,
            object: table,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let newSelectedRow = self.tableView.selectedRow
            if newSelectedRow < 0 { return }
            if self.adjustsSelectionAutomatically {
                self.selectedRow = newSelectedRow
            } else {
                self.delegate?.tableView(self, didSelectRow: newSelectedRow)
            }
            self.tableView.deselectRow(newSelectedRow)
        }

        canScrollHorizontally = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        if let token = selectionObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    override func layout() {
        super.layout()
        guard canScrollHorizontally, let horizontalScrollWidthManager else {
            lk(tableView).fullWidth()
            return
        }
        if horizontalScrollWidthManager.maxRowWidth <= frame.width {
            lk(tableView).fullWidth()
        } else {
            lk(tableView).width(horizontalScrollWidthManager.maxRowWidth + 20)
        }
    }

    func reloadData() {
        _selectedRow = -1
        hoveredRow = -1
        horizontalScrollWidthManager = nil
        if canScrollHorizontally {
            let manager = AVTableViewHorizontalScrollWidthManager()
            manager.didReachNewMaxWidth = { [weak self] in
                self?.handleRowViewMaxWidthChange()
            }
            horizontalScrollWidthManager = manager
        }
        tableView.reloadData()
    }

    func reloadDataWithOffset() {
        let offset = documentVisibleRect.origin
        reloadData()
        needsLayout = true
        layoutSubtreeIfNeeded()
        documentView?.scroll(offset)
    }

    func scrollRowToVisible(_ row: Int) {
        tableView.scrollRowToVisible(row)
    }

    func makeView(withIdentifier identifier: NSUserInterfaceItemIdentifier, owner: Any?) -> AVTableRowView? {
        tableView.makeView(withIdentifier: identifier, owner: self) as? AVTableRowView
    }

    func handleRowViewMaxWidthChange() {
        guard canScrollHorizontally, let horizontalScrollWidthManager else { return }
        if horizontalScrollWidthManager.maxRowWidth <= frame.width { return }
        lk(tableView).width(horizontalScrollWidthManager.maxRowWidth + 20)
    }

    @objc private func handleTableViewDefaultAction() {
        let clickedRow = tableView.clickedRow
        if clickedRow < 0 {
            delegate?.tableViewDidClickBlankArea(self)
        }
    }

    @objc private func handleDoubleClickTableView() {
        let clickedRow = tableView.clickedRow
        delegate?.tableView(self, didDoubleClickAtRow: clickedRow)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard adjustsHoverAutomatically else { return }
        updateHoveredRow(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard adjustsHoverAutomatically else { return }
        let rawPoint = event.locationInWindow
        let point = tableView.convert(rawPoint, from: nil)
        hoveredRow = tableView.row(at: point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeInKeyWindow,
            .inVisibleRect,
        ]
        let newArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(newArea)
    }

    private func updateHoveredRow(with event: NSEvent) {
        let rawPoint = event.locationInWindow
        let point = tableView.convert(rawPoint, from: nil)
        hoveredRow = tableView.row(at: point)
    }

    private func applyHoveredRowChange(from prevHoveredRow: Int, to hoveredRow: Int) {
        guard prevHoveredRow != hoveredRow else { return }

        self.tableView.enumerateAvailableRowViews { rowView, row in
            (rowView as? AVTableRowView)?.isHovered = row == hoveredRow
        }

        if hoveredRow >= 0, hoveredRow < self.tableView.numberOfRows {
            let canHover = delegate?.tableView(self.tableView, shouldSelectRow: hoveredRow) ?? true
            if !canHover,
               let rowView = self.tableView.rowView(atRow: hoveredRow, makeIfNecessary: false) as? AVTableRowView {
                rowView.isHovered = false
            }
        }
        delegate?.tableView(self, didHoverAtRow: hoveredRow)
    }

    private func applySelectedRowChange(from prevSelectedRow: Int, to selectedRow: Int) {
        guard adjustsSelectionAutomatically else { return }
        guard prevSelectedRow != selectedRow else { return }

        if prevSelectedRow >= 0, prevSelectedRow < tableView.numberOfRows {
            if let rowView = tableView.rowView(atRow: prevSelectedRow, makeIfNecessary: false) as? AVTableRowView {
                rowView.isSelected = false
            }
        }

        if selectedRow >= 0, selectedRow < tableView.numberOfRows {
            if let rowView = tableView.rowView(atRow: selectedRow, makeIfNecessary: false) as? AVTableRowView {
                rowView.isSelected = true
            }
            delegate?.tableView(self, didSelectRow: selectedRow)
        }
    }
}

extension AVTableView: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        dataSource?.numberOfRows(in: tableView) ?? 0
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        delegate?.tableView(tableView, heightOfRow: row) ?? 0
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard let rowView = delegate?.tableView(tableView, rowViewForRow: row) else { return nil }
        if let tableRowView = rowView as? AVTableRowView {
            tableRowView.isHovered = hoveredRow == row
            if adjustsSelectionAutomatically {
                tableRowView.isSelected = selectedRow == row
            }
            if canScrollHorizontally {
                tableRowView.horizontalScrollWidthManager = horizontalScrollWidthManager
            }
        }
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        nil
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        delegate?.tableView(tableView, shouldSelectRow: row) ?? true
    }
}
