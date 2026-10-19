//
//  AVHierarchyRowView.swift
//  AppView
//

import AppKit
import AppViewShared

class AVHierarchyRowView: AVOutlineRowView, AppViewDisplayItemDelegate {
    /// 注意这里是 weak，因为 tableView 会缓存很多 rowView
    private weak var _displayItem: AppViewDisplayItem?
    var displayItem: AppViewDisplayItem? {
        get { _displayItem }
        set {
            if newValue?.rowViewDelegate !== self {
                newValue?.rowViewDelegate = self
            }
            if newValue !== _displayItem {
                _displayItem = newValue
                reRender()
            }
        }
    }

    var minIndentLevel: Int = 0

    private var strikethroughLayer: CALayer?
    /// Small warning mark right of the title when the server reports `layoutIssueCount > 0`.
    private var layoutIssueMarkLabel: AVLabel?
    private var eventHandlerButtonColorLayer: CALayer?
    private var isFocusingHandlerButton = false {
        didSet {
            if isFocusingHandlerButton == oldValue { return }
            updateEventHandlerButtonLayout()
            updateEventHandlerButtonColors()
        }
    }

    private var dataSource: AVHierarchyDataSource
    private var _eventHandlerButton: NSButton?

    var eventHandlerButton: NSButton? { _eventHandlerButton }

    init(dataSource: AVHierarchyDataSource) {
        self.dataSource = dataSource
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        if let eventHandlerButton = _eventHandlerButton {
            lk(eventHandlerButton).y(3).toBottom(3).width(10).x(3)
            updateEventHandlerButtonLayout()
        }

        if let layoutIssueMarkLabel, !layoutIssueMarkLabel.isHidden {
            let anchor = subtitleLabel.isHidden ? titleLabel : subtitleLabel
            lk(layoutIssueMarkLabel).sizeToFit().x((anchor?.frame.maxX ?? titleLabel.frame.maxX) + 4).midY(anchor?.frame.midY ?? bounds.midY)
        }

        if let strikethroughLayer, !strikethroughLayer.isHidden {
            let maxX = subtitleLabel.isHidden
                ? titleLabel.frame.maxX + 2
                : subtitleLabel.frame.maxX + 2
            lk(strikethroughLayer).height(1).x(titleLabel.frame.minX - 1).toMaxX(maxX).midY(titleLabel.frame.midY + 1)
        }
    }

    func refreshFromDataSource() {
        reRender()
    }

    private func reRender() {
        guard let displayItem else { return }

        isSelected = dataSource.selectedItem === displayItem
        isHovered = dataSource.hoveredItem === displayItem
        image = resolveIconImage()
        indentLevel = UInt(displayItem.indentLevel() - minIndentLevel)
        updateEventsButton()
        updateExpandStatus()
        updateStrikethroughLayer()
        updateLabelStringsAndImageViewAlpha()
        updateLabelsFonts()
        updateLayoutIssueMark()
        needsLayout = true
    }

    private func updateLayoutIssueMark() {
        let count = displayItem?.layoutIssueCount ?? 0
        guard count > 0 else {
            layoutIssueMarkLabel?.isHidden = true
            return
        }
        let label: AVLabel
        if let existing = layoutIssueMarkLabel {
            label = existing
        } else {
            label = AVLabel()
            label.font = NSFontMake(12)
            label.drawsBackground = false
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byClipping
            addSubview(label)
            layoutIssueMarkLabel = label
        }
        label.isHidden = false
        label.font = titleLabel.font
        label.stringValue = "⚠︎"
        label.textColor = isSelected ? .white : .systemOrange
        label.toolTip = count == 1 ? "1 layout issue" : "\(count) layout issues"
    }

    override var isHovered: Bool {
        didSet { updateEventHandlerButtonColors() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateEventHandlerButtonColors()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        isFocusingHandlerButton = point.x < 16
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isFocusingHandlerButton = false
    }

    @objc
    private func handleClickEventHandlerButton(_ button: NSButton) {
        TutorialMng.eventsHandler = true

        let popover = NSPopover()
        let editable = window == AVNavigationManager.sharedInstance.staticWindowController?.window
        let vc = AVHierarchyHandlersPopoverController(displayItem: displayItem!, editable: editable)
        popover.animates = false
        popover.behavior = .transient
        popover.contentSize = vc.neededSize
        popover.contentViewController = vc
        popover.show(
            relativeTo: NSRect(x: 0, y: 0, width: button.bounds.width, height: button.bounds.height),
            of: button,
            preferredEdge: .maxY
        )
    }

    private func updateLabelStringsAndImageViewAlpha() {
        guard let displayItem else { return }

        let titleColor: NSColor
        let subtitleColor: NSColor

        if isSelected {
            titleColor = .white
            subtitleColor = .white
            imageView.alphaValue = 1
        } else if resolveIfShouldFadeContent() {
            titleColor = .tertiaryLabelColor
            subtitleColor = .tertiaryLabelColor
            imageView.alphaValue = 0.6
        } else {
            titleColor = .labelColor
            subtitleColor = .secondaryLabelColor
            imageView.alphaValue = 1
        }

        let highlightAttrs: [NSAttributedString.Key: Any] = [
            .backgroundColor: isDarkMode ? AppViewColorMake(190, 120, 0) : AppViewColorMake(255, 240, 100),
            .foregroundColor: NSColor.labelColor,
        ]
        let subtitleText = displayItem.subtitle() ?? ""
        subtitleLabel.isHidden = subtitleText.isEmpty

        var titleString = AVAttrString(displayItem.title() ?? "").textColor(titleColor).build()
        var subtitleString = AVAttrString(subtitleText).textColor(subtitleColor).build()
        if displayItem.isInSearch, let searchString = displayItem.highlightedSearchString, !searchString.isEmpty {
            titleString = AVAttrString(titleString).highlight(searchString, attributes: highlightAttrs).build()
            subtitleString = AVAttrString(subtitleString).highlight(searchString, attributes: highlightAttrs).build()
        }

        titleLabel.attributedStringValue = titleString
        subtitleLabel.attributedStringValue = subtitleString

        setAccessibilityElement(true)
        setAccessibilityEnabled(true)
        setAccessibilityRole(.cell)
        setAccessibilityLabel(displayItem.title() ?? "")
        if let subtitle = displayItem.subtitle(), !subtitle.isEmpty {
            setAccessibilityHelp(subtitle)
        } else {
            setAccessibilityHelp(nil)
        }
    }

    private func updateEventsButton() {
        guard let displayItem, !(displayItem.eventHandlers ?? []).isEmpty else {
            _eventHandlerButton?.isHidden = true
            return
        }

        if _eventHandlerButton == nil {
            let button = NSButton()
            button.title = ""
            button.setAccessibilityLabel("")
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleClickEventHandlerButton(_:))
            button.wantsLayer = true
            button.isBordered = false
            button.bezelStyle = .roundRect
            button.layer?.backgroundColor = NSColor.clear.cgColor
            addSubview(button)

            let colorLayer = CALayer()
            colorLayer.actions = ["contents": NSNull()]
            button.layer?.addSublayer(colorLayer)
            eventHandlerButtonColorLayer = colorLayer
            _eventHandlerButton = button
        }

        _eventHandlerButton?.isHidden = false
        updateEventHandlerButtonColors()
    }

    func displayItem(_ displayItem: AppViewDisplayItem, propertyDidChange property: AppViewDisplayItemProperty) {
        if property == .isHovered {
            isHovered = self.dataSource.hoveredItem === self.displayItem
            updateLabelStringsAndImageViewAlpha()
        } else if property == .isSelected {
            isSelected = self.dataSource.selectedItem === self.displayItem
            updateLabelStringsAndImageViewAlpha()
            updateLayoutIssueMark()
            updateExpandStatus()
            image = resolveIconImage()
        } else {
            reRender()
        }
    }

    private func updateStrikethroughLayer() {
        let shouldShow = resolveIfShouldShowStrikethrough()
        if shouldShow {
            if strikethroughLayer == nil {
                let layer = CALayer()
                layer.appview_removeImplicitAnimations()
                self.layer?.addSublayer(layer)
                strikethroughLayer = layer
            }
            if isSelected {
                strikethroughLayer?.backgroundColor = NSColor.white.withAlphaComponent(0.75).cgColor
            } else {
                strikethroughLayer?.backgroundColor = isDarkMode
                    ? AppViewColorRGBAMake(255, 255, 255, 0.2).cgColor
                    : AppViewColorRGBAMake(0, 0, 0, 0.2).cgColor
            }
            strikethroughLayer?.isHidden = false
            needsLayout = true
        } else {
            strikethroughLayer?.isHidden = true
        }
    }

    private func resolveIfShouldShowStrikethrough() -> Bool {
        guard let item = displayItem else { return false }
        guard item.hasPreviewBoxAbility() else { return false }
        return item.inNoPreviewHierarchy
    }

    override func setIsDarkMode(_ isDarkMode: Bool) {
        super.setIsDarkMode(isDarkMode)
        updateStrikethroughLayer()
    }

    private func updateEventHandlerButtonColors() {
        guard let eventHandlerButton = _eventHandlerButton, !eventHandlerButton.isHidden else { return }

        let color: NSColor
        if isSelected {
            color = .white
        } else {
            let alpha: CGFloat = isFocusingHandlerButton ? 1 : 0.5
            color = AppViewColorRGBAMake(74, 144, 226, alpha)
        }
        eventHandlerButtonColorLayer?.backgroundColor = color.cgColor
    }

    private func updateEventHandlerButtonLayout() {
        let width: CGFloat = isFocusingHandlerButton ? 8 : 5
        if let eventHandlerButtonColorLayer {
            lk(eventHandlerButtonColorLayer).fullHeight().width(width).horAlign()
            eventHandlerButtonColorLayer.cornerRadius = width / 2.0
        }
    }

    private func updateLabelsFonts() {
        guard let displayItem else { return }
        let noImage = displayItem.inNoPreviewHierarchy || displayItem.inHiddenHierarchy
        if !displayItem.isUserCustom(), noImage {
            titleLabel.font = AVHelper.italicFont(ofSize: 13)
            subtitleLabel.font = AVHelper.italicFont(ofSize: 12)
        } else {
            titleLabel.font = NSFontMake(13)
            subtitleLabel.font = NSFontMake(12)
        }
        needsLayout = true
    }

    private func updateExpandStatus() {
        guard let displayItem else {
            status = .notExpandable
            return
        }
        if !displayItem.isExpandable {
            status = .notExpandable
        } else if displayItem.isExpanded {
            status = .expanded
        } else {
            status = .collapsed
        }
    }

    private static var iconLogCount = 0

    private func resolveIconImage() -> NSImage? {
        guard let item = displayItem else { return nil }
        let imageName = Self.resolveIconName(for: item)
        let img = NSImageMake(imageName)

        if Self.iconLogCount < 20 {
            Self.iconLogCount += 1
            NSLog("[Icon] viewObj=%@ layerObj=%@ chain=%@ name=%@ found=%d",
                  item.viewObject?.rawClassName() ?? "nil",
                  item.layerObject?.rawClassName() ?? "nil",
                  item.viewObject?.classChainList?.first ?? item.layerObject?.classChainList?.first ?? "nil",
                  imageName,
                  img != nil ? 1 : 0)
        }

        if dataSource.selectedItem === item {
            let selectedImageName = imageName + "_selected"
            if let selectedImage = NSImageMake(selectedImageName) {
                return selectedImage
            }
        }
        return img
    }

    private static func resolveIconName(for item: AppViewDisplayItem) -> String {
        if item.isUserCustom() {
            return "hierarchy_custom"
        }
        if item.hostViewControllerObject != nil {
            return "hierarchy_controller"
        }
        if let viewObject = item.viewObject,
           let viewIconName = viewIconName(from: viewObject.classChainList) {
            return viewIconName
        }
        if let layerObject = item.layerObject,
           let layerIconName = layerIconName(from: layerObject.classChainList) {
            return layerIconName
        }
        return item.viewObject != nil ? "hierarchy_view" : "hierarchy_layer"
    }

    private static func simpleClassName(_ rawClassName: String) -> String {
        (rawClassName as NSString).components(separatedBy: ".").last ?? rawClassName
    }

    private static func viewIconName(from classChainList: [String]?) -> String? {
        guard let classChainList else { return nil }
        for rawClassName in classChainList {
            let className = simpleClassName(rawClassName)
            if let imageName = viewsIconMap[className] {
                return imageName
            }
        }
        return nil
    }

    private static func layerIconName(from classChainList: [String]?) -> String? {
        guard let classChainList else { return nil }
        for rawClassName in classChainList {
            switch simpleClassName(rawClassName) {
            case "CAShapeLayer":
                return "hierarchy_shapelayer"
            case "CAGradientLayer":
                return "hierarchy_gradientlayer"
            default:
                continue
            }
        }
        return nil
    }

    private func resolveIfShouldFadeContent() -> Bool {
        guard let item = displayItem else { return false }
        if item.isInSearch, (item.highlightedSearchString?.count ?? 0) == 0 { return true }
        if !item.hasPreviewBoxAbility() { return false }
        return item.inHiddenHierarchy || item.inNoPreviewHierarchy
    }

    override class func insetLeft() -> CGFloat { 13 }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for oldArea in trackingAreas {
            removeTrackingArea(oldArea)
        }
        let newArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newArea)
    }

    private static let viewsIconMap: [String: String] = [
        "UIWindow": "hierarchy_window",
        "UINavigationBar": "hierarchy_navigationbar",
        "UITabBar": "hierarchy_tabbar",
        "UITextView": "hierarchy_textview",
        "UIStackView": "hierarchy_stackview",
        "UITextField": "hierarchy_textfield",
        "UITableView": "hierarchy_tableview",
        "UICollectionView": "hierarchy_collectionview",
        "UICollectionViewCell": "hierarchy_collectioncell",
        "UICollectionReusableView": "hierarchy_collectionreuseview",
        "UITableViewCell": "hierarchy_tablecell",
        "UISlider": "hierarchy_slider",
        "WKWebView": "hierarchy_webview",
        "UIWebView": "hierarchy_webview",
        "_UITableViewCellSeparatorView": "hierarchy_tablecellseparator",
        "UITableViewCellContentView": "hierarchy_cellcontent",
        "_UITableViewHeaderFooterContentView": "hierarchy_cellcontent",
        "UITableViewHeaderFooterView": "hierarchy_tableheaderfooter",
        "UIScrollView": "hierarchy_scrollview",
        "UILabel": "hierarchy_label",
        "UIButton": "hierarchy_button",
        "UIImageView": "hierarchy_imageview",
        "UIControl": "hierarchy_control",
        "UIVisualEffectView": "hierarchy_effectview",
    ]
}
