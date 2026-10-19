import AppKit
import AppViewShared
import RxSwift

final class AVDashboardAttributeSwitchView: AVDashboardAttributeView {
    private var button: NSButton!
    private var modifyDisposable: Disposable?
    private var isSubmittingModification = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        button = NSButton()
        button.setButtonType(.switch)
        button.target = self
        button.action = #selector(handleButton)
        button.font = NSFontMake(13)
        addSubview(button)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        lk(button).fullFrame()
    }

    override func renderWithAttribute() {
        guard let attribute else { return }
        let title: String
        if attribute.isUserCustom() {
            title = attribute.displayTitle ?? ""
        } else {
            title = AppViewDashboardBlueprint.briefTitle(withAttrID: attribute.identifier ?? "") ?? ""
        }
        button.attributedTitle = AVAttrString(title).textColor(NSColor(named: "DashboardCardValueColor")!).build()
        let boolValue = attribute.value.dashboardBoolValue
        button.state = boolValue ? .on : .off
        button.isEnabled = canEdit()
        needsLayout = true
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        let size = button.sizeThatFits(limitedSize)
        return NSSize(width: size.width + 3, height: size.height + 2)
    }

    override func numberOfColumnsOccupied() -> UInt {
        guard let attribute else { return 1 }
        if attribute.isUserCustom() { return 1 }
        if attribute.identifier == AppViewAttr_UIScrollView_Zoom_Bounce { return 1 }
        return 0
    }

    @objc private func handleButton() {
        guard !isSubmittingModification, canEdit(), attribute != nil else { return }

        let currentValue = attribute?.value.dashboardBoolValue ?? false
        let expectedValue = AttributeValue.bool(!currentValue)

        modifyDisposable?.dispose()
        AVAppsManager.sharedInstance.inspectingApp?.cancelInbuiltModification()
        isSubmittingModification = true
        button.isEnabled = false
        attribute?.value = expectedValue
        renderWithAttribute()

        modifyDisposable = subscribeAttributeModification(
            newValue: expectedValue,
            onError: { [weak self] in
                guard let self, let attribute = self.attribute else { return }
                attribute.value = .bool(currentValue)
                self.finishSubmittingModification()
                self.renderWithAttribute()
            },
            onSuccess: { [weak self] in
                self?.finishSubmittingModification()
                self?.renderWithAttribute()
            }
        )
        if modifyDisposable == nil {
            finishSubmittingModification()
            renderWithAttribute()
        }
    }

    private func finishSubmittingModification() {
        isSubmittingModification = false
        button.isEnabled = canEdit()
    }
}
