//
//  AVMeasureController.swift
//  AppView
//

import AppCenterAnalytics
import AppKit
import AppViewShared
import RxSwift

class AVMeasureController: AVBaseViewController {
    private var tutorialView: AVMeasureTutorialView!
    private var resultView: AVMeasureResultView!
    private var dataSource: AVHierarchyDataSource!
    private var shortcutLabel: AVLabel?
    private var lockSwitchButton: NSButton?

    private let disposeBag = DisposeBag()

    init(dataSource: AVHierarchyDataSource) {
        self.dataSource = dataSource
        super.init(containerView: nil)

        tutorialView = AVMeasureTutorialView()
        view.addSubview(tutorialView)

        resultView = AVMeasureResultView()
        view.addSubview(resultView)

        dataSource.preferenceManager().measureStateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, state in
                owner.applyMeasureStateChange(state)
            }
            .disposed(by: disposeBag)

        Observable.combineLatest(
            dataSource.selectedItemObservable,
            dataSource.hoveredItemObservable
        )
        .observe(on: MainScheduler.instance)
        .subscribe(with: self) { owner, _ in
            owner.reRender()
        }
        .disposed(by: disposeBag)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        let titleHeight = AVNavigationManager.sharedInstance.windowTitleBarHeight
        var contentView: NSView?

        if !tutorialView.isHidden && tutorialView.alphaValue >= 0.01 {
            lk(tutorialView).fullWidth().heightToFit().verAlign().offsetY(titleHeight / 2.0)
            contentView = tutorialView
        }
        if !resultView.isHidden && resultView.alphaValue >= 0.01 {
            lk(resultView).fullWidth().heightToFit().verAlign().offsetY(titleHeight / 2.0)
            contentView = resultView
        }
        if let shortcutLabel, let contentView {
            lk(shortcutLabel).sizeToFit().horAlign().y(contentView.frame.maxY + 5)
        }
        if let lockSwitchButton, let contentView {
            lk(lockSwitchButton).sizeToFit().horAlign().y(contentView.frame.maxY + 5)
        }
    }

    private func applyMeasureStateChange(_ state: AppViewMeasureState) {
        shortcutLabel?.isHidden = true

        switch state {
        case .no:
            lockSwitchButton?.isHidden = true
            lockSwitchButton?.state = .off

        case .unlocked:
            Analytics.trackEvent("Start Measure", withProperties: ["shortcut": "YES"])

            if lockSwitchButton == nil {
                let button = NSButton()
                button.setButtonType(.switch)
                button.font = NSFontMake(15)
                button.title = NSLocalizedString("Cancel measure after key up.", comment: "")
                button.target = self
                button.action = #selector(handleLockSwitchButton(_:))
                view.addSubview(button)
                lockSwitchButton = button
            }
            lockSwitchButton?.state = .on
            lockSwitchButton?.isHidden = false

        case .locked:
            Analytics.trackEvent("Start Measure", withProperties: ["shortcut": "NO"])

            if shortcutLabel == nil {
                let label = AVLabel()
                label.stringValue = NSLocalizedString("shortcut: holding \"option\" key", comment: "")
                label.textColor = .secondaryLabelColor
                view.addSubview(label)
                shortcutLabel = label
            }
            shortcutLabel?.isHidden = false

        @unknown default:
            break
        }
        reRender()
    }

    private func reRender() {
        if dataSource.preferenceManager().measureState == .no {
            return
        }
        guard let selectedItem = dataSource.selectedItem else { return }

        if dataSource.hoveredItem == nil || dataSource.selectedItem === dataSource.hoveredItem {
            let format = NSLocalizedString("to measure between it and selected %@.", comment: "")
            let subtitle = String(format: format, selectedItem.title() ?? "")

            resultView.isHidden = true
            tutorialView.isHidden = false
            tutorialView.render(
                image: NSImageMake("measure_hover"),
                title: NSLocalizedString("Hover on a layer", comment: ""),
                subtitle: subtitle
            )
            view.needsLayout = true
            return
        }

        guard let hoveredItem = dataSource.hoveredItem else { return }

        let selectedItemFrame = selectedItem.calculateFrameToRoot()
        let hoveredItemFrame = hoveredItem.calculateFrameToRoot()

        var sizeInvalidClass: String?
        var sizeInvalidProperty: String?

        if selectedItemFrame.width <= 0 {
            sizeInvalidClass = selectedItem.title() ?? ""
            sizeInvalidProperty = "width"
        } else if selectedItemFrame.height <= 0 {
            sizeInvalidClass = selectedItem.title() ?? ""
            sizeInvalidProperty = "height"
        } else if hoveredItemFrame.width <= 0 {
            sizeInvalidClass = hoveredItem.title() ?? ""
            sizeInvalidProperty = "width"
        } else if hoveredItemFrame.height <= 0 {
            sizeInvalidClass = hoveredItem.title() ?? ""
            sizeInvalidProperty = "height"
        }

        if let sizeInvalidClass, let sizeInvalidProperty {
            let subtitleFormat = NSLocalizedString("Selected %@'s %@ is less than or equal to 0.", comment: "")
            let subtitle = String(format: subtitleFormat, sizeInvalidClass, sizeInvalidProperty)

            resultView.isHidden = true
            tutorialView.isHidden = false
            tutorialView.render(
                image: NSImageMake("measure_info"),
                title: NSLocalizedString("Invalid Size", comment: ""),
                subtitle: subtitle
            )
            view.needsLayout = true
            return
        }

        tutorialView.isHidden = true
        resultView.isHidden = false
        resultView.render(
            mainRect: selectedItemFrame,
            mainImage: selectedItem.groupScreenshot,
            referRect: hoveredItemFrame,
            referImage: hoveredItem.groupScreenshot
        )
        view.needsLayout = true
    }

    @objc
    private func handleLockSwitchButton(_ sender: NSButton) {
        if sender.state == .on {
            dataSource.preferenceManager().measureState = .unlocked
        } else {
            dataSource.preferenceManager().measureState = .locked
        }
    }
}
