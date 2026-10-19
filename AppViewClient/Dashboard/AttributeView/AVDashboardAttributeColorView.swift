import AppKit
import AppViewShared
import RxSwift

private final class AVDashboardAttributeColorContainerView: AVBaseView {
    weak var clickTarget: AnyObject?
    var clickAction: Selector?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if let clickTarget, let clickAction {
            _ = NSApp.sendAction(clickAction, to: clickTarget, from: event)
        }
    }
}

final class AVDashboardAttributeColorView: AVDashboardAttributeView, NSMenuDelegate {
    private var indicatorLayer: AVColorIndicatorLayer!
    private var descLabel: AVLabel!
    private var containerView: AVDashboardAttributeColorContainerView!
    private var iconImageView: NSImageView!
    private var aliasLabel: AVLabel?
    private let identifiersToHideAlias: Set<AppViewAttrIdentifier> = [
        AppViewAttr_ViewLayer_Border_Color,
        AppViewAttr_ViewLayer_Shadow_Color,
    ]
    private let mainContainerHeight: CGFloat = 30
    private let aliasLabelMarginTop: CGFloat = 1
    private let labelX: CGFloat = 28
    private var modifyDisposable: Disposable?
    private let disposeBag = DisposeBag()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        containerView = AVDashboardAttributeColorContainerView()
        containerView.layer?.cornerRadius = DashboardCardControlCornerRadius
        containerView.clickTarget = self
        containerView.clickAction = #selector(handleClick(_:))
        addSubview(containerView)

        indicatorLayer = AVColorIndicatorLayer()
        containerView.layer?.addSublayer(indicatorLayer)

        iconImageView = NSImageView()
        iconImageView.image = NSImageMake("Icon_ArrowUpDown")
        containerView.addSubview(iconImageView)

        descLabel = AVLabel()
        descLabel.textColor = NSColor(named: "DashboardCardValueColor")
        descLabel.font = NSFontMake(13)
        containerView.addSubview(descLabel)

        AVPreferenceMain().rgbaFormatObservable
            .skip(1)
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, _ in
                owner.renderWithAttribute()
            }
            .disposed(by: disposeBag)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layout() {
        super.layout()
        lk(containerView).fullWidth().height(mainContainerHeight).y(0)
        lk(indicatorLayer).width(16).height(16).x(8).verAlign()
        lk(descLabel).x(labelX).toRight(20).heightToFit().verAlign().offsetY(-1)
        lk(iconImageView).sizeToFit().verAlign().right(9)
        if aliasLabel?.isVisible == true, let aliasLabel {
            lk(aliasLabel).x(labelX).toRight(0).y(containerView.frame.maxY + aliasLabelMarginTop).heightToFit()
        }
    }

    override func renderWithAttribute() {
        iconImageView.isHidden = !canEdit()
        let color = NSColor.lk_colorFromAttributeValue(attribute?.value)
        indicatorLayer.color = color ?? AppViewColorMake(0, 0, 0)
        if let color {
            descLabel.stringValue = AVPreferenceMain().rgbaFormat ? color.rgbaString : color.hexString
        } else {
            descLabel.stringValue = "nil"
        }
        if let dataSource = dashboardViewController?.currentDataSource(),
           let alias = dataSource.alias(forColor: color),
           let identifier = attribute?.identifier,
           !identifiersToHideAlias.contains(identifier) {
            if aliasLabel == nil {
                let label = AVLabel()
                label.textColor = NSColor(named: "DashboardCardValueColor")
                addSubview(label)
                aliasLabel = label
            }
            aliasLabel?.isHidden = false
            aliasLabel?.attributedStringValue = AVAttrString(alias.joined(separator: "\n"), style: .dashboardAlias).build()
        } else {
            aliasLabel?.isHidden = true
        }
        needsLayout = true
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        var height = mainContainerHeight
        if aliasLabel?.isVisible == true, let aliasLabel {
            let width = limitedSize.width - labelX
            height += aliasLabelMarginTop + aliasLabel.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude)).height
        }
        return NSSize(width: limitedSize.width, height: height)
    }

    override var dashboardViewController: AVDashboardViewController? {
        didSet { containerView.backgroundColorName = "DashboardCardValueBGColor" }
    }

    @objc private func handleClick(_ event: NSEvent) {
        guard canEdit(), let dataSource = dashboardViewController?.currentDataSource() else { return }
        guard let menu = dataSource.selectColorMenu else { return }
        menu.delegate = self
        NSMenu.popUpContextMenu(menu, with: event, for: containerView)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            if let submenu = item.submenu {
                submenu.items.forEach { updateMenuItem($0) }
            } else {
                updateMenuItem(item)
            }
        }
    }

    private func updateMenuItem(_ menuItem: NSMenuItem) {
        guard let dataSource = dashboardViewController?.currentDataSource() else { return }
        if menuItem.tag == dataSource.customColorMenuItemTag {
            menuItem.state = .off
            menuItem.target = self
            menuItem.action = #selector(handleCustomColorMenuItem)
            return
        }
        if menuItem.tag == dataSource.toggleColorFormatMenuItemTag {
            menuItem.state = .off
            menuItem.target = self
            menuItem.action = #selector(handleToggleColorFormatMenuItem)
            return
        }
        menuItem.target = self
        menuItem.action = #selector(handlePresetMenuItem(_:))
        let color = menuItem.representedObject as? NSColor
        if attribute?.value == color?.lk_attributeColorValue() {
            menuItem.state = .on
        } else {
            menuItem.state = .off
        }
    }

    @objc private func handlePresetMenuItem(_ item: NSMenuItem) {
        modifyToColor(item.representedObject as? NSColor)
    }

    @objc private func handleCustomColorMenuItem() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = true
        panel.isContinuous = false
        panel.color = NSColor.lk_colorFromAttributeValue(attribute?.value) ?? .clear
        panel.setTarget(self)
        panel.setAction(#selector(handleSystemColorPanel(_:)))
        panel.orderFront(self)
    }

    @objc private func handleToggleColorFormatMenuItem() {
        let manager = AVPreferenceMain()
        manager.rgbaFormat = !manager.rgbaFormat
    }

    @objc private func handleSystemColorPanel(_ panel: NSColorPanel) {
        modifyToColor(panel.color)
    }

    private func modifyToColor(_ targetColor: NSColor?) {
        guard let targetColor else { return }
        let expectedValue = targetColor.lk_attributeColorValue()
        if expectedValue == attribute?.value { return }
        modifyDisposable = subscribeAttributeModification(newValue: expectedValue, onError: {}) { [weak self] in
            self?.renderWithAttribute()
        }
    }
}
