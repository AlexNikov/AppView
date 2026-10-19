//
//  AVHierarchyView.swift
//  AppView
//

import AppKit
import RxRelay
import RxSwift
import AppViewShared

private let menuBindKeyRowView = "view"
private let disclosureBindKeyDisplayItem = "disclosureDisplayItem"
private let rowHeight: CGFloat = 28

private enum HierarchyMenuAction: Int {
    case focus = 1
    case printItem
    case reloadSelf
    case reloadSelfAndChildren
    case expandRecursively
    case collapseChildren
    case showPreview
    case cancelPreview
    case hideScreenshotForever
    case exportScreenshot
    case copyText
    case searchClose
    case disclosureToggle
}

protocol AVHierarchyViewDelegate: AnyObject {
    func hierarchyView(_ view: AVHierarchyView, needToCancelPreviewOfItem item: AppViewDisplayItem)
    func hierarchyView(_ view: AVHierarchyView, needToShowPreviewOfItem item: AppViewDisplayItem)
}

class AVHierarchyView: AVBaseView, AVTableViewDelegate, AVTableViewDataSource, NSMenuDelegate, NSTextFieldDelegate {
    private(set) var tableView: AVTableView!
    var dataSource: AVHierarchyDataSource!
    weak var delegate: AVHierarchyViewDelegate?

    private var backgroundEffectView: AVVisualEffectView!
    private var guidesShapeLayer: CAShapeLayer!
    private var searchTextFieldView: AVTextFieldView!
    private var emptyDataLabel: AVLabel?
    private var displayItems: [AppViewDisplayItem] = []
    private var minIndentLevel = 0

    private let disposeBag = DisposeBag()

    let printItemRelay = PublishRelay<AppViewDisplayItem>()
    private let didSelectItemRelay = PublishRelay<AppViewDisplayItem>()
    var didSelectItemFromUser: Observable<AppViewDisplayItem> {
        didSelectItemRelay.asObservable()
    }

    private let didDoubleClickItemRelay = PublishRelay<AppViewDisplayItem>()
    var didDoubleClickItemFromUser: Observable<AppViewDisplayItem> {
        didDoubleClickItemRelay.asObservable()
    }

    private let didHoverItemRelay = PublishRelay<AppViewDisplayItem?>()
    var didHoverItemFromUser: Observable<AppViewDisplayItem?> {
        didHoverItemRelay.asObservable()
    }

    private let needExpandItemRelay = PublishRelay<(AppViewDisplayItem, Bool)>()
    var needExpandItemFromUser: Observable<(AppViewDisplayItem, Bool)> {
        needExpandItemRelay.asObservable()
    }

    private let needCollapseItemRelay = PublishRelay<AppViewDisplayItem>()
    var needCollapseItemFromUser: Observable<AppViewDisplayItem> {
        needCollapseItemRelay.asObservable()
    }

    private let needCollapseChildrenRelay = PublishRelay<AppViewDisplayItem>()
    var needCollapseChildrenFromUser: Observable<AppViewDisplayItem> {
        needCollapseChildrenRelay.asObservable()
    }

    private let searchTextRelay = PublishRelay<String?>()
    var searchTextFromUser: Observable<String?> {
        searchTextRelay.asObservable()
    }

    init(dataSource: AVHierarchyDataSource) {
        super.init(frame: .zero)
        self.dataSource = dataSource
        commonInit()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func commonInit() {
        backgroundEffectView = AVVisualEffectView()
        backgroundEffectView.material = .sidebar
        backgroundEffectView.blendingMode = .behindWindow
        backgroundEffectView.state = .active
        addSubview(backgroundEffectView)

        tableView = AVTableView()
        tableView.adjustsSelectionAutomatically = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.tableView.setAccessibilityIdentifier("appview.hierarchy.outline")
        tableView.tableView.setAccessibilityLabel("Hierarchy")
        addSubview(tableView)
        tableView.reloadData()

        guidesShapeLayer = CAShapeLayer()
        guidesShapeLayer.lineWidth = 1
        guidesShapeLayer.isHidden = true
        guidesShapeLayer.appview_removeImplicitAnimations()
        guidesShapeLayer.lineDashPattern = [2, 2]
        tableView.contentView.documentView?.layer?.addSublayer(guidesShapeLayer)

        searchTextFieldView = AVTextFieldView()
        searchTextFieldView.textField.placeholderString = NSLocalizedString("Filter", comment: "")
        searchTextFieldView.initCloseButton()
        searchTextFieldView.insets = NSEdgeInsets(top: 0, left: 7, bottom: 0, right: 1)
        searchTextFieldView.textField.font = NSFontMake(13)
        searchTextFieldView.textField.usesSingleLineMode = true
        searchTextFieldView.textField.lineBreakMode = .byTruncatingTail
        searchTextFieldView.textField.drawsBackground = false
        searchTextFieldView.textField.isBordered = false
        searchTextFieldView.textField.focusRingType = .none
        searchTextFieldView.borderPosition = .top
        searchTextFieldView.borderColors = AVColorsCombine(AppViewColorMake(200, 201, 202), AppViewColorMake(67, 68, 69))
        searchTextFieldView.image = NSImageMake("icon_hierarchy_search")
        searchTextFieldView.textField.delegate = self
        addSubview(searchTextFieldView)

        searchTextFieldView.textField.lk_textOrEmpty
            .throttle(.milliseconds(500), latest: false, scheduler: MainScheduler.instance)
            .skip(1)
            .subscribe(onNext: { [weak self] text in
                guard let self else { return }
                var text = text
                text = (text as NSString).replacingOccurrences(
                    of: "\\s",
                    with: "",
                    options: .regularExpression,
                    range: NSRange(location: 0, length: text.count)
                )
                self.searchTextRelay.accept(text)
            })
            .disposed(by: disposeBag)

        searchTextFieldView.closeButton?.target = self
        searchTextFieldView.closeButton?.action = #selector(routeControlAction(_:))
        searchTextFieldView.closeButton?.tag = HierarchyMenuAction.searchClose.rawValue

        dataSource.selectedItemObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, item in
                owner.refreshVisibleRowAppearance()
                owner.scrollToMakeItemVisible(item)
            }
            .disposed(by: disposeBag)

        dataSource.hoveredItemObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, item in
                owner.refreshVisibleRowAppearance()
                owner.updateGuides(withHoveredItem: item)
            }
            .disposed(by: disposeBag)

        dataSource.itemDidChangeHiddenAlphaValue
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { owner, _ in
                owner.refreshVisibleRowAppearance()
            })
            .disposed(by: disposeBag)

        dataSource.itemDidChangeNoPreview
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { owner, _ in
                owner.refreshVisibleRowAppearance()
            })
            .disposed(by: disposeBag)

        dataSource.preferenceManager().showHiddenItemsObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, _ in
                owner.tableView.reloadDataWithOffset()
            }
            .disposed(by: disposeBag)

        dataSource.displayingFlatItemsObservable
            .map { $0 ?? [] }
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, items in
                owner.render(withDisplayItems: items)
                DispatchQueue.main.async {
                    owner.updateGuides(withHoveredItem: owner.dataSource.hoveredItem)
                }
            }
            .disposed(by: disposeBag)

        dataSource.didReloadFlatItemsWithSearchOrFocus
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onNext: { owner, _ in
                let items = owner.dataSource.displayingFlatItems ?? []
                owner.render(withDisplayItems: items)
            })
            .disposed(by: disposeBag)

        dataSource.displayingFlatItemsObservable
            .map { _ in () }
            .throttle(.milliseconds(750), latest: false, scheduler: MainScheduler.instance)
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, _ in
                owner.bringGuidesLayerToFront()
            }
            .disposed(by: disposeBag)

        dataSource.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, state in
                let isFocus = state == .focus
                owner.searchTextFieldView.isHidden = isFocus
                if isFocus, !owner.searchTextFieldView.textField.stringValue.isEmpty {
                    owner.searchTextFieldView.textField.stringValue = ""
                    owner.window?.makeFirstResponder(nil)
                }
            }
            .disposed(by: disposeBag)

        updateColors()
    }

    override func layout() {
        super.layout()
        lk(backgroundEffectView).fullFrame()
        lk(searchTextFieldView).fullWidth().height(25).bottom(0)
        lk(tableView).fullFrame().y(searchTextFieldView.frame.minY)
        lk(tableView).fullFrame().toMaxY(searchTextFieldView.frame.minY)
        lk(guidesShapeLayer).frame(.zero)

        if emptyDataLabel?.isHidden == false, let emptyDataLabel {
            lk(emptyDataLabel).sizeToFit().centerAlign()
        }
        AVNavigationManager.sharedInstance.windowTitleBarHeight = tableView.contentInsets.top
    }

    private func refreshVisibleRowAppearance() {
        let rowCount = displayItems.count
        guard rowCount > 0 else { return }
        for row in 0..<rowCount {
            guard let rowView = tableView.tableView.rowView(atRow: row, makeIfNecessary: false) as? AVHierarchyRowView else {
                continue
            }
            rowView.refreshFromDataSource()
        }
    }

    /// Visible mac hierarchy rows for MCP parity (selection highlight, subtitles).
    func mcpVisibleHierarchyRowStates() -> [[String: Any]] {
        let rowCount = displayItems.count
        guard rowCount > 0 else { return [] }
        var rows: [[String: Any]] = []
        rows.reserveCapacity(rowCount)
        for row in 0..<rowCount {
            guard let rowView = tableView.tableView.rowView(atRow: row, makeIfNecessary: false) as? AVHierarchyRowView,
                  let item = rowView.displayItem else {
                continue
            }
            let oid = item.viewObject?.oid ?? item.layerObject?.oid ?? 0
            let represented = item.viewObject ?? item.layerObject
            rows.append([
                "row": row,
                "oid": oid,
                "title": item.title() ?? "",
                "subtitle": item.subtitle() ?? "",
                "specialTrace": represented?.specialTrace ?? "",
                "ivarNames": AVMCPInspectorParity.ivarNames(from: represented),
                "macIsSelected": rowView.isSelected,
                "macIsHovered": rowView.isHovered,
                "subtitleLabelHidden": rowView.subtitleLabel.isHidden,
                "backgroundColorRGBA": AVMCPInspectorParity.rgbaArray(from: item.backgroundColor),
            ])
        }
        return rows
    }

    private func render(withDisplayItems displayItems: [AppViewDisplayItem]) {
        self.displayItems = displayItems

        minIndentLevel = displayItems.reduce(Int.max) { partial, obj in
            min(partial, obj.indentLevel())
        }
        if minIndentLevel == Int.max { minIndentLevel = 0 }

        tableView.reloadDataWithOffset()

        if displayItems.isEmpty {
            if emptyDataLabel == nil {
                let label = AVLabel()
                label.font = NSFontMake(15)
                label.stringValue = NSLocalizedString("No Filter Results", comment: "")
                addSubview(label)
                emptyDataLabel = label
            }
            emptyDataLabel?.isHidden = false
            needsLayout = true
        } else {
            emptyDataLabel?.isHidden = true
        }
    }

    func scrollToMakeItemVisible(_ item: AppViewDisplayItem?) {
        guard let item else { return }
        let row = displayItems.firstIndex(of: item)
        guard let row, row != NSNotFound else { return }
        tableView.scrollRowToVisible(row)
    }

    override func updateColors() {
        super.updateColors()
        guidesShapeLayer.strokeColor = isDarkMode()
            ? AppViewColorRGBAMake(255, 255, 255, 0.3).cgColor
            : AppViewColorRGBAMake(0, 0, 0, 0.3).cgColor
    }

    func activateSearchBar() {
        searchTextFieldView.textField.becomeFirstResponder()
    }

    func updateGuides(withHoveredItem item: AppViewDisplayItem?) {
        guard let item else {
            guidesShapeLayer.isHidden = true
            return
        }

        guard let rootItem = item.superItem else {
            guidesShapeLayer.isHidden = true
            return
        }

        let rootRow = displayItems.firstIndex(of: rootItem)
        let childrenItems = rootItem.subitems?.filter { displayItems.contains($0) } ?? []

        guard let rootRow, rootRow != NSNotFound, !childrenItems.isEmpty else {
            guidesShapeLayer.isHidden = true
            return
        }

        let rootX = AVHierarchyRowView.dislosureMidX(withIndentLevel: UInt(rootItem.indentLevel() - minIndentLevel))
        let rootY = rowHeight * CGFloat(rootRow) + rowHeight / 2.0
        let lastChildRow = displayItems.firstIndex(of: childrenItems.last!) ?? rootRow
        let rootMaxY = rowHeight * CGFloat(lastChildRow) + rowHeight / 2.0

        let path = CGMutablePath()
        path.move(to: CGPoint(x: rootX, y: rootY))
        path.addLine(to: CGPoint(x: rootX, y: rootMaxY))

        for child in childrenItems {
            guard let childRow = displayItems.firstIndex(of: child) else { continue }
            let childrenY = rowHeight * CGFloat(childRow) + rowHeight / 2.0
            path.move(to: CGPoint(x: rootX, y: childrenY))
            let maxX = child.isExpandable ? rootX + 10 : rootX + 28
            path.addLine(to: CGPoint(x: maxX, y: childrenY))
        }

        guidesShapeLayer.path = path
        guidesShapeLayer.isHidden = false
    }

    // MARK: - AVTableView

    func tableView(_ tableView: AVTableView, didHoverAtRow row: Int) {
        let item = safeItem(atRow: row)
        didHoverItemRelay.accept(item)
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        rowHeight
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        displayItems.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard let item = safeItem(atRow: row) else {
            assertionFailure()
            return AVTableBlankRowView()
        }

        var view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("cell"), owner: self) as? AVHierarchyRowView
        if view == nil {
            view = AVHierarchyRowView(dataSource: dataSource)
            view?.disclosureButton.target = self
            view?.disclosureButton.action = #selector(routeControlAction(_:))
            view?.disclosureButton.tag = HierarchyMenuAction.disclosureToggle.rawValue
            view?.identifier = NSUserInterfaceItemIdentifier("cell")

            let menu = NSMenu()
            menu.autoenablesItems = true
            menu.appview_bindObjectWeakly(view, forKey: menuBindKeyRowView)
            menu.delegate = self
            view?.menu = menu
        }

        view?.minIndentLevel = minIndentLevel
        view?.displayItem = item
        view?.refreshFromDataSource()
        view?.disclosureButton.appview_bindObjectWeakly(item, forKey: disclosureBindKeyDisplayItem)
        return view!
    }

    func tableView(_ tableView: AVTableView, didSelectRow row: Int) {
        guard let item = safeItem(atRow: row) else { return }
        didSelectItemRelay.accept(item)
        DispatchQueue.main.async { [weak self] in
            self?.bringGuidesLayerToFront()
        }
    }

    func tableView(_ tableView: AVTableView, didDoubleClickAtRow row: Int) {
        guard let item = safeItem(atRow: row) else { return }
        didDoubleClickItemRelay.accept(item)
    }

    private func addHierarchyMenuItem(
        to menu: NSMenu,
        title: String,
        action: HierarchyMenuAction,
        enabled: Bool = true
    ) {
        let item = NSMenuItem()
        item.title = title
        item.isEnabled = enabled
        item.target = self
        item.action = #selector(routeHierarchyMenuItem(_:))
        item.tag = action.rawValue
        menu.addItem(item)
    }

    private func hierarchyRowView(from menu: NSMenu?) -> AVHierarchyRowView? {
        menu?.appview_getBindObject(forKey: menuBindKeyRowView) as? AVHierarchyRowView
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let rowView = menu.appview_getBindObject(forKey: menuBindKeyRowView) as? AVHierarchyRowView,
              let displayItem = rowView.displayItem else { return }

        menu.removeAllItems()

        if !displayItem.isUserCustom() {
            addHierarchyMenuItem(
                to: menu,
                title: NSLocalizedString("Focus", comment: ""),
                action: .focus
            )

            if !dataSource.isReadOnly() {
                addHierarchyMenuItem(
                    to: menu,
                    title: NSLocalizedString("Print", comment: ""),
                    action: .printItem
                )
            }

            menu.addItem(.separator())

            if !dataSource.isReadOnly() {
                let isUpdating = AVStaticAsyncUpdateManager.sharedInstance.isUpdating
                addHierarchyMenuItem(
                    to: menu,
                    title: NSLocalizedString("Reload layer", comment: ""),
                    action: .reloadSelf,
                    enabled: !isUpdating
                )
                addHierarchyMenuItem(
                    to: menu,
                    title: NSLocalizedString("Reload layer and its children", comment: ""),
                    action: .reloadSelfAndChildren,
                    enabled: !isUpdating
                )
            }
        }

        var stringsToCopy: [String] = []
        var doNotCopyTitle = false
        if displayItem.title()?.hasPrefix("UI") == true || displayItem.title()?.hasPrefix("CA") == true,
           (displayItem.title()?.count ?? 0) < 10 {
            doNotCopyTitle = true
        }
        if !doNotCopyTitle, let title = displayItem.title() {
            stringsToCopy.append(title)
        }

        if let hostViewControllerName = displayItem.hostViewControllerObject?.lk_simpleDemangledClassName,
           !hostViewControllerName.isEmpty {
            stringsToCopy.append(hostViewControllerName)
        }

        if let ivarTraces = displayItem.displayingObject()?.ivarTraces {
            let ivarNames = ivarTraces.compactMap { trace -> String? in
                var name = trace.ivarName
                if (name ?? "").hasPrefix("_") {
                    name = String((name ?? "").dropFirst())
                }
                return name
            }
            stringsToCopy.append(contentsOf: Array(Set(ivarNames)))
        }

        for (idx, string) in stringsToCopy.enumerated() {
            if idx == 0 {
                menu.addItem(.separator())
            }
            guard !string.isEmpty else {
                assertionFailure("AVHierarchyView, menuNeedsUpdate, stringsToCopy length is zero.")
                continue
            }
            let item = NSMenuItem()
            item.target = self
            item.action = #selector(routeHierarchyMenuItem(_:))
            item.tag = HierarchyMenuAction.copyText.rawValue
            item.representedObject = string
            item.title = String(format: NSLocalizedString("Copy text \"%@\"", comment: ""), string)
            menu.addItem(item)
        }

        menu.addItem(.separator())

        if displayItem.isExpandable {
            addHierarchyMenuItem(
                to: menu,
                title: NSLocalizedString("Expand recursively", comment: ""),
                action: .expandRecursively
            )
            addHierarchyMenuItem(
                to: menu,
                title: NSLocalizedString("Collapse children", comment: ""),
                action: .collapseChildren
            )
        }

        menu.addItem(.separator())

        if displayItem.hasPreviewBoxAbility() {
            if displayItem.inNoPreviewHierarchy {
                addHierarchyMenuItem(
                    to: menu,
                    title: displayItem.doNotFetchScreenshotReason == .permitted
                        ? NSLocalizedString("Show screenshot", comment: "")
                        : NSLocalizedString("Show layer border", comment: ""),
                    action: .showPreview
                )
            } else {
                addHierarchyMenuItem(
                    to: menu,
                    title: NSLocalizedString("Hide screenshot this time", comment: ""),
                    action: .cancelPreview
                )
            }
        }

        menu.addItem(.separator())

        if displayItem.groupScreenshot != nil {
            addHierarchyMenuItem(
                to: menu,
                title: NSLocalizedString("Export screenshot…", comment: ""),
                action: .exportScreenshot
            )
        }
    }

    // MARK: - NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            exitAndClearSearch()
            return true
        }
        return false
    }

    // MARK: - Event Handlers

    @objc private func routeHierarchyMenuItem(_ menuItem: NSMenuItem) {
        guard let action = HierarchyMenuAction(rawValue: menuItem.tag) else { return }
        let rowView = hierarchyRowView(from: menuItem.menu)

        switch action {
        case .focus:
            guard let item = rowView?.displayItem else {
                assertionFailure()
                return
            }
            dataSource.focusDisplayItem(item)
        case .printItem:
            guard let item = rowView?.displayItem else { return }
            printItemRelay.accept(item)
        case .reloadSelf:
            guard let item = rowView?.displayItem else { return }
            AVStaticAsyncUpdateManager.sharedInstance.reloadSingleDisplayItem(item)
        case .reloadSelfAndChildren:
            guard let item = rowView?.displayItem else { return }
            AVStaticAsyncUpdateManager.sharedInstance.reloadDisplayItemAndChildren(item)
        case .showPreview:
            AVTutorialManager.sharedInstance().togglePreview = true
            guard let item = rowView?.displayItem else { return }
            delegate?.hierarchyView(self, needToShowPreviewOfItem: item)
        case .cancelPreview:
            AVTutorialManager.sharedInstance().togglePreview = true
            guard let item = rowView?.displayItem else { return }
            delegate?.hierarchyView(self, needToCancelPreviewOfItem: item)
        case .exportScreenshot:
            guard let displayItem = rowView?.displayItem else { return }
            AVExportManager.exportScreenshot(with: displayItem)
        case .copyText:
            guard let stringToCopy = menuItem.representedObject as? String else { return }
            let paste = NSPasteboard.general
            paste.clearContents()
            paste.writeObjects([stringToCopy as NSString])
        case .expandRecursively:
            guard let item = rowView?.displayItem else {
                assertionFailure()
                return
            }
            needExpandItemRelay.accept((item, true))
        case .collapseChildren:
            guard let item = rowView?.displayItem else {
                assertionFailure()
                return
            }
            needCollapseChildrenRelay.accept(item)
        case .hideScreenshotForever, .searchClose, .disclosureToggle:
            break
        }
    }

    @objc private func routeControlAction(_ sender: NSControl) {
        guard let action = HierarchyMenuAction(rawValue: sender.tag) else { return }
        switch action {
        case .searchClose:
            exitAndClearSearch()
        case .disclosureToggle:
            guard let button = sender as? NSButton,
                  let item = button.appview_getBindObject(forKey: disclosureBindKeyDisplayItem) as? AppViewDisplayItem,
                  item.isExpandable else {
                assertionFailure()
                return
            }
            if item.isExpanded {
                needCollapseItemRelay.accept(item)
            } else {
                needExpandItemRelay.accept((item, false))
            }
        default:
            break
        }
    }

    private func exitAndClearSearch() {
        searchTextFieldView.textField.stringValue = ""
        window?.makeFirstResponder(nil)
        searchTextRelay.accept(nil)
    }

    private func bringGuidesLayerToFront() {
        guidesShapeLayer.removeFromSuperlayer()
        tableView.contentView.documentView?.layer?.addSublayer(guidesShapeLayer)
    }

    private func safeItem(atRow row: Int) -> AppViewDisplayItem? {
        guard displayItems.appview_hasIndex(row) else { return nil }
        return displayItems[row]
    }
}
