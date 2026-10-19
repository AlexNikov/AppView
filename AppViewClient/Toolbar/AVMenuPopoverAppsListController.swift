//
//  AVMenuPopoverAppsListController.swift
//  AppView
//

import AppKit
import AppViewShared

public enum MenuPopoverAppsListControllerEventSource: Int {
    case reloadButton = 0
    case noConnectionTips = 1
    case appButton = 2
}

class AVMenuPopoverAppsListController: AVBaseViewController {
    var didSelectApp: ((AVInspectableApp) -> Void)?

    private var appViews: [AVLaunchAppView] = []
    private var titleLabel: AVLabel?
    private var subtitleLabel: AVLabel?

    private let insets = NSEdgeInsets(top: 9, left: 18, bottom: 14, right: 14)
    private let titleMarginBottom: CGFloat = 3
    private let subtitleMarginBottom: CGFloat = 5
    private let appViewInterSpace: CGFloat = 1

    init(apps: [AVInspectableApp], source: MenuPopoverAppsListControllerEventSource) {
        super.init(containerView: nil)

        var title: String?
        var subtitle: String?
        switch source {
        case .reloadButton, .noConnectionTips:
            title = NSLocalizedString("Connection lost", comment: "")
            if apps.isEmpty {
                subtitle = NSLocalizedString("And no inspectable app was found", comment: "")
            } else if apps.count == 1 {
                subtitle = NSLocalizedString("Click the screenshot below to Change App", comment: "")
            } else {
                subtitle = String(
                    format: NSLocalizedString("Other %@ apps were found", comment: ""),
                    NSNumber(value: apps.count)
                )
            }
        case .appButton:
            if apps.isEmpty {
                title = NSLocalizedString("No inspectable app was found", comment: "")
            } else {
                if apps.count == 1 {
                    title = NSLocalizedString("1 active app was found", comment: "")
                } else {
                    title = String(
                        format: NSLocalizedString("%@ active apps were found", comment: ""),
                        NSNumber(value: apps.count)
                    )
                }
                subtitle = NSLocalizedString("Click the screenshot below to inspect", comment: "")
            }
        }

        if !apps.isEmpty {
            appViews = apps.map { app in
                let view = AVLaunchAppView()
                view.compactLayout = true
                view.app = app
                view.addTarget(self, clickAction: #selector(handleClickAppView(_:)))
                self.view.addSubview(view)
                return view
            }
        }

        if let title, !title.isEmpty {
            let label = AVLabel()
            label.alignment = .center
            label.font = NSFontMake(14)
            label.textColor = .labelColor
            label.stringValue = title
            view.addSubview(label)
            titleLabel = label
        }

        if let subtitle, !subtitle.isEmpty {
            let label = AVLabel()
            label.alignment = .center
            label.font = NSFontMake(12)
            label.textColor = .labelColor
            label.stringValue = subtitle
            view.addSubview(label)
            subtitleLabel = label
        }

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        var y = insets.top
        if let titleLabel {
            lk(titleLabel).fullWidth().heightToFit().y(y)
            y = titleLabel.frame.maxY + titleMarginBottom
        }
        if let subtitleLabel {
            lk(subtitleLabel).fullWidth().heightToFit().y(y)
            y = subtitleLabel.frame.maxY + subtitleMarginBottom
        }

        if !appViews.isEmpty {
            var posX: CGFloat = 0
            for view in appViews {
                lk(view).sizeToFit().x(posX).y(y)
                posX = view.frame.maxX + appViewInterSpace
            }
            lk(appViews).groupHorAlign()
        } else if let titleLabel, let subtitleLabel {
            lk(titleLabel, subtitleLabel).visibles().groupVerAlign()
        }
    }

    /// Fills in screenshots for tiles that were shown without one, matching apps by `appInfoIdentifier`.
    func applyScreenshots(from apps: [AVInspectableApp]) {
        var freshInfos: [UInt: AppViewAppInfo] = [:]
        for case let info? in apps.map(\.appInfo) where info.screenshot != nil {
            freshInfos[info.appInfoIdentifier] = info
        }
        for view in appViews {
            guard let app = view.app, let info = app.appInfo, info.screenshot == nil,
                  let fresh = freshInfos[info.appInfoIdentifier] else { continue }
            info.screenshot = fresh.screenshot
            view.app = app
        }
    }

    @objc func handleClickAppView(_ view: AVLaunchAppView) {
        guard let app = view.app else { return }
        didSelectApp?(app)
    }

    func bestSize() -> NSSize {
        if appViews.isEmpty {
            return NSSize(width: 245, height: 80)
        }

        var width = insets.left + insets.right + CGFloat(appViews.count - 1) * appViewInterSpace
        var appViewMaxHeight: CGFloat = 0
        let maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        for view in appViews {
            let size = view.sizeThatFits(maxSize)
            width += size.width
            appViewMaxHeight = max(appViewMaxHeight, size.height)
        }

        var height = insets.top + insets.bottom + appViewMaxHeight
        if let titleLabel {
            let titleSize = titleLabel.sizeThatFits(maxSize)
            height += titleSize.height + titleMarginBottom
            width = max(width, titleSize.width + insets.left + insets.right)
        }
        if let subtitleLabel {
            let subtitleSize = subtitleLabel.sizeThatFits(maxSize)
            height += subtitleSize.height + subtitleMarginBottom
            width = max(width, subtitleSize.width + insets.left + insets.right)
        }

        return NSSize(width: width, height: height)
    }
}
