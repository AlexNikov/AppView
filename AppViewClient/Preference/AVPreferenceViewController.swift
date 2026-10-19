//
//  AVPreferenceViewController.swift
//  AppView
//

import AppKit
import AppViewShared

class AVPreferenceViewController: AVBaseViewController {
    private var viewDoubleClick: AVPreferencePopupView!
    private var viewAppearance: AVPreferencePopupView!
    private var viewColorFormat: AVPreferencePopupView!
    private var viewContrast: AVPreferencePopupView!
    private var resetButton: NSButton!

    convenience init() {
        self.init(containerView: nil)
    }

    override init(containerView view: NSView?) {
        super.init(containerView: view)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func appview_didSetView(_ view: NSView) {
        super.appview_didSetView(view)

        let controlX: CGFloat = IsEnglish ? 94 : 84

        viewColorFormat = AVPreferencePopupView(
            title: NSLocalizedString("Color Format", comment: ""),
            messages: [
                NSLocalizedString("Color will be displayed in format like (255, 12, 34, 0.5). Alpha value is between 0 and 1.", comment: ""),
                NSLocalizedString("Color will be displayed in format like #7e7e7eff. The components are #RRGGBBAA.", comment: ""),
            ],
            options: ["RGBA", "HEX"]
        )
        viewColorFormat.buttonX = controlX
        viewColorFormat.didChange = { selectedIndex in
            AVPreferenceMain().rgbaFormat = selectedIndex == 0
        }
        view.addSubview(viewColorFormat)

        let contrastTips = NSLocalizedString("Adjust this option to use a deeper layer selection color.", comment: "")
        viewContrast = AVPreferencePopupView(
            title: NSLocalizedString("Image contrast", comment: ""),
            messages: [contrastTips, contrastTips, contrastTips],
            options: [
                NSLocalizedString("Normal", comment: ""),
                NSLocalizedString("Medium", comment: ""),
                NSLocalizedString("High", comment: ""),
            ]
        )
        viewContrast.buttonX = controlX
        viewContrast.didChange = { selectedIndex in
            AVPreferenceMain().imageContrastLevel = Int(selectedIndex)
        }
        view.addSubview(viewContrast)

        viewAppearance = AVPreferencePopupView(
            title: NSLocalizedString("Appearance", comment: ""),
            message: "",
            options: [
                NSLocalizedString("Dark Mode", comment: ""),
                NSLocalizedString("Light Mode", comment: ""),
                NSLocalizedString("System Default", comment: ""),
            ]
        )
        viewAppearance.buttonX = controlX
        viewAppearance.didChange = { selectedIndex in
            AVPreferenceMain().appearanceType = AppViewPreferredAppeanranceType(rawValue: Int(selectedIndex))
                ?? .system
        }
        view.addSubview(viewAppearance)

        viewDoubleClick = AVPreferencePopupView(
            title: NSLocalizedString("Double click", comment: ""),
            message: "",
            options: [
                NSLocalizedString("Expand or collapse layer", comment: ""),
                NSLocalizedString("Focus on layer", comment: ""),
            ]
        )
        viewDoubleClick.buttonX = controlX
        viewDoubleClick.didChange = { selectedIndex in
            AVPreferenceMain().doubleClickBehavior = AppViewDoubleClickBehavior(rawValue: Int(selectedIndex))
                ?? .collapse
        }
        view.addSubview(viewDoubleClick)

        resetButton = NSButton.lk_normalButton(
            withTitle: NSLocalizedString("Reset", comment: ""),
            target: self,
            action: #selector(handleResetButton)
        )
        view.addSubview(resetButton)

        renderFromPreferenceManager()
    }

    private func renderFromPreferenceManager() {
        let manager = AVPreferenceMain()
        viewColorFormat.selectedIndex = manager.rgbaFormat ? 0 : 1
        viewContrast.selectedIndex = UInt(manager.imageContrastLevel)
        viewAppearance.selectedIndex = UInt(manager.appearanceType.rawValue)
        viewDoubleClick.selectedIndex = UInt(manager.doubleClickBehavior.rawValue)
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        let insets = NSEdgeInsets(top: 20, left: 30, bottom: 10, right: 30)

        lk(viewAppearance).x(insets.left).toRight(insets.right).y(insets.top).height(50)
        lk(viewColorFormat).x(insets.left).toRight(insets.right).y(viewAppearance.frame.maxY).height(80)
        lk(viewContrast).x(insets.left).toRight(insets.right).y(viewColorFormat.frame.maxY).height(65)
        lk(viewDoubleClick).x(insets.left).toRight(insets.right).y(viewContrast.frame.maxY).height(50)

        lk(resetButton).width(120).bottom(insets.bottom).right(insets.right)
    }

    @objc private func handleResetButton() {
        let manager = AVPreferenceMain()
        manager.appearanceType = .system
        manager.rgbaFormat = true
        manager.doubleClickBehavior = .collapse
        manager.imageContrastLevel = 0
        renderFromPreferenceManager()

        #if DEBUG
        AVMessageManager.sharedInstance.reset()
        manager.reset()
        UserDefaults.standard.removeObject(forKey: "IgnoreFastModeTips")
        #endif
    }
}
