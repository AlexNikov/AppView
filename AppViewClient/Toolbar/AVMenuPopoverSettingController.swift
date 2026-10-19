//
//  AVMenuPopoverSettingController.swift
//  AppView
//

import AppKit
import AppViewShared
import RxSwift

class AVMenuPopoverSettingController: AVBaseViewController {
    private var manager: AVPreferenceManager!
    private var enableOutlineButton: NSButton!
    private var showInvisiblesButton: NSButton!
    private var spaceSlider: NSSlider!
    private var spaceSliderLabel: AVLabel!
    private var preferenceButton: NSButton!
    private let disposeBag = DisposeBag()

    init(preferenceManager manager: AVPreferenceManager) {
        super.init(containerView: nil)
        self.manager = manager

        enableOutlineButton = NSButton()
        enableOutlineButton.setButtonType(.switch)
        enableOutlineButton.font = NSFontMake(14)
        enableOutlineButton.title = NSLocalizedString("Show layer outline", comment: "")
        enableOutlineButton.target = self
        enableOutlineButton.action = #selector(handleOutlineControl)
        view.addSubview(enableOutlineButton)
        enableOutlineButton.state = manager.showOutline ? .on : .off

        showInvisiblesButton = NSButton()
        showInvisiblesButton.font = NSFontMake(14)
        showInvisiblesButton.title = NSLocalizedString("Show hidden UIView and CALayer", comment: "")
        showInvisiblesButton.setButtonType(.switch)
        showInvisiblesButton.target = self
        showInvisiblesButton.action = #selector(handleShowInvisiblesControl)
        view.addSubview(showInvisiblesButton)
        showInvisiblesButton.state = manager.showHiddenItems ? .on : .off

        spaceSlider = NSSlider()
        spaceSlider.minValue = AppViewPreviewMinZInterspace
        spaceSlider.maxValue = AppViewPreviewMaxZInterspace
        spaceSlider.target = self
        spaceSlider.action = #selector(handleSpaceSlider(_:))
        view.addSubview(spaceSlider)

        spaceSliderLabel = AVLabel()
        spaceSliderLabel.font = NSFontMake(14)
        spaceSliderLabel.stringValue = NSLocalizedString("Item separation", comment: "")
        view.addSubview(spaceSliderLabel)

        preferenceButton = NSButton.lk_normalButton(
            withTitle: NSLocalizedString("More…", comment: ""),
            target: self,
            action: #selector(handlePreferenceButton)
        )
        view.addSubview(preferenceButton)

        manager.zInterspaceObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, value in
                owner.spaceSlider.doubleValue = value
            }
            .disposed(by: disposeBag)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        lk(enableOutlineButton).x(15).toRight(0).height(24).y(15)
        lk(showInvisiblesButton).x(15).toRight(0).height(24).y(enableOutlineButton.frame.maxY + 6)
        lk(spaceSlider).x(15).toRight(15).height(26).y(showInvisiblesButton.frame.maxY + 22)
        lk(spaceSliderLabel).sizeToFit().x(spaceSlider.frame.origin.x + 3).y(spaceSlider.frame.maxY)
        lk(preferenceButton).width(130).horAlign().bottom(4)
    }

    @objc private func handleOutlineControl() {
        manager.showOutline = enableOutlineButton.state == .on
    }

    @objc private func handleShowInvisiblesControl() {
        manager.showHiddenItems = showInvisiblesButton.state == .on
    }

    @objc private func handleSpaceSlider(_ slider: NSSlider) {
        manager.zInterspace = slider.doubleValue
    }

    @objc private func handlePreferenceButton() {
        AVNavigationManager.sharedInstance.showPreference()
    }
}
