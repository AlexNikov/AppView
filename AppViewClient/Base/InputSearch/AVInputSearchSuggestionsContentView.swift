//
//  AVInputSearchSuggestionsContentView.swift
//  AppView
//

import AppKit

private let kInputSearchSuggestionsItemViewHeight: CGFloat = 28

class AVInputSearchSuggestionsContentView: AVBaseView, NSTableViewDelegate, NSTableViewDataSource {
    var items: [AVInputSearchSuggestionItem] = [] {
        didSet { tableView.reloadData() }
    }

    private(set) var tableView: NSTableView!
    private var backgroundEffectView: AVVisualEffectView!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.cornerRadius = 4

        backgroundEffectView = AVVisualEffectView()
        backgroundEffectView.blendingMode = .behindWindow
        backgroundEffectView.state = .active
        addSubview(backgroundEffectView)

        tableView = NSTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.wantsLayer = true
        tableView.headerView = nil
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column"))
        column.isEditable = false
        tableView.addTableColumn(column)
        addSubview(tableView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        lk(backgroundEffectView, tableView).fullFrame()
    }

    func currentSelectedItem() -> AVInputSearchSuggestionItem? {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, selectedRow < items.count else { return nil }
        return items[selectedRow]
    }

    func bestSize() -> NSSize {
        let rowView: AVInputSearchSuggestionsRowView
        if let cached = appview_getBindObject(forKey: "calculatingRowView") as? AVInputSearchSuggestionsRowView {
            rowView = cached
        } else {
            rowView = AVInputSearchSuggestionsRowView()
            appview_bindObject(rowView, forKey: "calculatingRowView")
        }

        let width = items.reduce(CGFloat(0)) { accumulator, obj in
            rowView.imageView.image = obj.image
            rowView.titleLabel.stringValue = obj.text ?? ""
            return max(rowView.bestWidth(), accumulator)
        }
        let height = kInputSearchSuggestionsItemViewHeight * CGFloat(items.count)
        return NSSize(width: width, height: height)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        kInputSearchSuggestionsItemViewHeight
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard let item = (items as NSArray).appview_safeObject(at: row) as? AVInputSearchSuggestionItem else {
            return AVInputSearchSuggestionsRowView()
        }
        var view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("cell"), owner: self) as? AVInputSearchSuggestionsRowView
        if view == nil {
            view = AVInputSearchSuggestionsRowView()
            view?.identifier = NSUserInterfaceItemIdentifier("cell")
        }
        view?.titleLabel.stringValue = item.text ?? ""
        view?.imageView.image = item.image
        view?.needsLayout = true
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        nil
    }
}
