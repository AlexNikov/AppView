import AppKit
import AppViewShared
import RxSwift

final class AVDashboardAttributeEnumsView: AVDashboardAttributeView {
    private var iconImageView: NSImageView!
    private var textLabel: AVLabel!
    private let labelX: CGFloat = 5
    private let labelRight: CGFloat = 20
    private var modifyDisposable: Disposable?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = DashboardCardControlCornerRadius

        textLabel = AVLabel()
        textLabel.textColor = NSColor(named: "DashboardCardValueColor")
        textLabel.maximumNumberOfLines = 0
        textLabel.font = NSFontMake(12)
        addSubview(textLabel)

        iconImageView = NSImageView()
        iconImageView.image = NSImageMake("Icon_ArrowUpDown")
        addSubview(iconImageView)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layout() {
        super.layout()
        lk(iconImageView).sizeToFit().verAlign().right(9)
        lk(textLabel).x(labelX).toRight(labelRight).heightToFit().verAlign()
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        let height = textLabel.sizeThatFits(NSSize(width: limitedSize.width - labelRight - labelX, height: .greatestFiniteMagnitude)).height + 10
        return NSSize(width: limitedSize.width, height: height)
    }

    override func renderWithAttribute() {
        guard let attribute else { return }
        if attribute.attrType == .enumString {
            textLabel.stringValue = attribute.value.dashboardStringValue ?? ""
        } else {
            let enumValue = attribute.value.dashboardIntValue
            let enumListName = AppViewDashboardBlueprint.enumListName(withAttrID: attribute.identifier ?? "") ?? ""
            textLabel.stringValue = AVEnumListRegistry.sharedInstance.desc(forEnumName: enumListName, value: enumValue) ?? ""
        }
    }

    override var dashboardViewController: AVDashboardViewController? {
        didSet { backgroundColorName = "DashboardCardValueBGColor" }
    }

    override func mouseDown(with event: NSEvent) {
        let menu = attribute?.isUserCustom() == true ? createMenuForUserCustom() : createMenuForPreset()
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func createMenuForPreset() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let currentOSVersion = dashboardViewController?.currentDataSource()?.rawHierarchyInfo?.appInfo?.osMainVersion ?? 0
        let enumListName = AppViewDashboardBlueprint.enumListName(withAttrID: attribute?.identifier ?? "") ?? ""
        let rawItems = AVEnumListRegistry.sharedInstance.items(forEnumName: enumListName) ?? []
        let currentEnumValue = attribute?.value.dashboardIntValue ?? 0
        for obj in rawItems {
            let validOSVersion = currentOSVersion >= obj.availableOSVersion
            let item = NSMenuItem()
            item.image = NSImage(size: NSSize(width: 1, height: 22))
            item.title = validOSVersion ? obj.desc : "\(obj.desc) (iOS \(obj.availableOSVersion))"
            item.representedObject = NSNumber(value: obj.value)
            item.isEnabled = canEdit() && validOSVersion
            item.target = self
            item.action = #selector(handleMenuItem(_:))
            item.state = obj.value == currentEnumValue ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func createMenuForUserCustom() -> NSMenu {
        let menu = NSMenu()
        guard case .customObject(let rawValue)? = attribute?.extraValue,
              let cases = rawValue as? [String],
              !cases.isEmpty else { return menu }
        let currentValue = attribute?.value.dashboardStringValue
        for text in cases {
            let item = NSMenuItem()
            item.image = NSImage(size: NSSize(width: 1, height: 22))
            item.title = text
            item.representedObject = text
            item.isEnabled = canEdit()
            item.target = self
            item.action = #selector(handleMenuItem(_:))
            item.state = text == currentValue ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func handleMenuItem(_ item: NSMenuItem) {
        let expectedValue: AttributeValue?
        if let number = item.representedObject as? NSNumber {
            expectedValue = AttributeValue.enumValue(from: number, attrType: attribute?.attrType ?? .enumInt)
        } else if let text = item.representedObject as? String {
            expectedValue = .string(text)
        } else {
            return
        }
        if expectedValue == attribute?.value { return }
        modifyDisposable = subscribeAttributeModification(newValue: expectedValue, onError: {}) { [weak self] in
            self?.renderWithAttribute()
        }
    }
}
