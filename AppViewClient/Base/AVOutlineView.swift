//
//  AVOutlineView.swift
//  AppView
//

import AppKit

protocol AVOutlineViewDelegate: AnyObject {
    func outlineView(_ view: AVOutlineView, configureRowView rowView: AVOutlineRowView, withItem item: AVOutlineItem)
}

class AVOutlineView: AVBaseView {
    private(set) var tableView: AVTableView!
    private(set) var displayingItems: [AVOutlineItem] = []

    var items: [AVOutlineItem] = [] {
        didSet { updateDisplayingItems() }
    }

    weak var delegate: AVOutlineViewDelegate?
    var itemHeight: CGFloat = 24

    private var rowViewClass: AVOutlineRowView.Type = AVOutlineRowView.self

    init(rowViewClass: AnyClass) {
        itemHeight = 24
        guard let rowClass = rowViewClass as? AVOutlineRowView.Type else {
            fatalError("rowViewClass must be AVOutlineRowView or subclass")
        }
        self.rowViewClass = rowClass
        displayingItems = []
        super.init(frame: .zero)

        tableView = AVTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.adjustsSelectionAutomatically = false
        addSubview(tableView)
    }

    override convenience init(frame frameRect: NSRect) {
        self.init(rowViewClass: AVOutlineRowView.self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        lk(tableView).fullFrame()
    }

    @objc private func handleDisclosureButton(_ button: NSButton) {
        let row = button.tag
        guard row >= 0, row < displayingItems.count else { return }
        let item = displayingItems[row]
        if item.status == .notExpandable { return }
        if item.status == .expanded {
            item.status = .collapsed
        } else {
            item.status = .expanded
        }
        updateDisplayingItems()
    }

    private func updateDisplayingItems() {
        displayingItems = AVOutlineItem.flatItems(fromRootItems: items)
        tableView.reloadData()
    }
}

extension AVOutlineView: AVTableViewDelegate, AVTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        displayingItems.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        itemHeight
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard row >= 0, row < displayingItems.count else {
            return rowViewClass.init()
        }
        let item = displayingItems[row]

        let identifier = NSUserInterfaceItemIdentifier("cell")
        var view = tableView.makeView(withIdentifier: identifier, owner: self) as? AVOutlineRowView
        if view == nil {
            view = rowViewClass.init()
            view?.identifier = identifier
        }
        guard let view else { return nil }

        view.disclosureButton.tag = row
        view.disclosureButton.target = self
        view.disclosureButton.action = #selector(handleDisclosureButton(_:))

        switch item.status {
        case .notExpandable:
            view.status = .notExpandable
        case .expanded:
            view.status = .expanded
        case .collapsed:
            view.status = .collapsed
        }

        view.indentLevel = item.indentation
        view.titleLabel.stringValue = item.titleText ?? ""
        view.image = item.image

        delegate?.outlineView(self, configureRowView: view, withItem: item)
        view.needsLayout = true
        return view
    }
}
