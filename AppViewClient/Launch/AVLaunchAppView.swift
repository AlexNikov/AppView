//
//  AVLaunchAppView.swift
//  AppView
//

import AppKit
import AppViewShared

class AVLaunchAppView: AVBaseControl {
    var compactLayout = false {
        didSet { applyCompactLayout() }
    }

    var app: AVInspectableApp? {
        didSet { renderApp() }
    }

    private var hoverBgLayer: CALayer!
    private var previewImageView: NSImageView!
    private var iconImageView: NSImageView!
    private var titleLabel: AVLabel!
    private var subtitleLabel: AVLabel!

    private var errorImageView: NSImageView?
    private var errorTitleLabel: AVLabel?
    private var errorSubtitleLabel: AVLabel?

    private var previewSize = NSSize(width: 142, height: 260)
    private var insets = NSEdgeInsets(top: 12, left: 25, bottom: 12, right: 25)
    private var iconTop: CGFloat = 10
    private var iconMarginRight: CGFloat = 8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.cornerRadius = 4

        hoverBgLayer = CALayer()
        hoverBgLayer.opacity = 0
        hoverBgLayer.cornerRadius = 4
        layer?.addSublayer(hoverBgLayer)

        previewImageView = NSImageView()
        addSubview(previewImageView)

        iconImageView = NSImageView()
        addSubview(iconImageView)

        titleLabel = AVLabel()
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        subtitleLabel = AVLabel()
        subtitleLabel.textColor = .labelColor
        addSubview(subtitleLabel)

        applyCompactLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func applyCompactLayout() {
        if compactLayout {
            previewSize = NSSize(width: 120, height: 220)
            insets = NSEdgeInsets(top: 12, left: 13, bottom: 8, right: 13)
            iconTop = 10
            iconMarginRight = 6
            titleLabel.font = NSFontMake(12)
            subtitleLabel.font = NSFontMake(11)
        } else {
            previewSize = NSSize(width: 142, height: 260)
            insets = NSEdgeInsets(top: 12, left: 25, bottom: 12, right: 25)
            iconTop = 10
            iconMarginRight = 8
            titleLabel.font = NSFontMake(13)
            subtitleLabel.font = NSFontMake(12)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        hoverBgLayer.frame = layer?.bounds ?? .zero

        if app?.serverVersionError != nil {
            guard let errorImageView, let errorTitleLabel, let errorSubtitleLabel else { return }
            lk(errorImageView).sizeToFit().horAlign()
            lk(errorTitleLabel).x(10).toRight(10).appview_heightToFit().y(errorImageView.frame.maxY + 15)
            lk(errorSubtitleLabel).sizeToFit().horAlign().y(errorTitleLabel.frame.maxY + 10)
            lk(errorImageView, errorTitleLabel, errorSubtitleLabel).groupVerAlign().offsetY(-10)
        } else {
            lk(previewImageView).size(previewSize).horAlign().y(insets.top)
            lk(iconImageView).sizeToFit().y(insets.top + previewSize.height + iconTop)
            lk(titleLabel).sizeToFit()
            lk(subtitleLabel).sizeToFit().y(titleLabel.frame.maxY + 2)
            lk(titleLabel, subtitleLabel)
                .x(iconImageView.frame.maxX + iconMarginRight)
                .groupMidY(iconImageView.frame.midY)
            lk(iconImageView, titleLabel, subtitleLabel).groupHorAlign().offsetX(-2)
        }
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        if app?.serverVersionError != nil {
            return NSSize(
                width: previewSize.width + insets.left + insets.right,
                height: insets.top + previewSize.height + iconTop + insets.bottom
            )
        }

        let previewWidth = previewSize.width + insets.left + insets.right
        let iconWidth = iconImageView.image?.size.width ?? 0
        let labelsWidth = iconWidth + iconMarginRight +
            max(titleLabel.sizeThatFits(NSSizeMax).width, subtitleLabel.sizeThatFits(NSSizeMax).width) +
            insets.left + insets.right
        let width = max(previewWidth, labelsWidth)
        let height = insets.top + previewSize.height + iconTop + iconWidth + insets.bottom
        return NSSize(width: width, height: height)
    }

    override func sizeToFit() {
        frame.size = sizeThatFits(NSSizeMax)
    }

    private func renderApp() {
        guard let app else { return }

        if let error = app.serverVersionError {
            initErrorViewsIfNeeded()
            errorImageView?.isHidden = false
            errorTitleLabel?.isHidden = false
            errorSubtitleLabel?.isHidden = false
            previewImageView.isHidden = true
            iconImageView.isHidden = true
            titleLabel.isHidden = true
            subtitleLabel.isHidden = true

            if error.code == Int(AppViewErrCode_ServerVersionTooLow) {
                errorTitleLabel?.stringValue = NSLocalizedString(
                    "The version of AppViewServer linked with this iOS App is too low.",
                    comment: ""
                )
            } else if error.code == Int(AppViewErrCode_ServerVersionTooHigh) {
                errorTitleLabel?.stringValue = NSLocalizedString(
                    "Unable to inspect this iOS App. Current version of AppView app is too low.",
                    comment: ""
                )
            } else {
                errorTitleLabel?.stringValue = "Unknown Error"
                assertionFailure()
            }
        } else {
            errorImageView?.isHidden = true
            errorTitleLabel?.isHidden = true
            errorSubtitleLabel?.isHidden = true
            previewImageView.isHidden = false
            iconImageView.isHidden = false
            titleLabel.isHidden = false
            subtitleLabel.isHidden = false

            guard let appInfo = app.appInfo else { return }

            previewImageView.image = appInfo.screenshot
            if app.isLaunchUSBPendingPlaceholder {
                previewImageView.image = nil
            }
            switch appInfo.deviceType {
            case .simulator:
                iconImageView.image = NSImageMake("icon_simulator_big")
            case .iPad:
                iconImageView.image = NSImageMake("icon_ipad_big")
            case .others:
                iconImageView.image = NSImageMake("icon_iphone_big")
            @unknown default:
                iconImageView.image = NSImageMake("icon_iphone_big")
            }
            titleLabel.stringValue = appInfo.deviceDescription ?? ""
            let appName = appInfo.appName ?? ""
            let os = appInfo.osDescription ?? ""
            if appName.isEmpty {
                subtitleLabel.stringValue = "iOS \(os)"
            } else {
                subtitleLabel.stringValue = "\(appName) · iOS \(os)"
            }

            let bundleId = appInfo.appBundleIdentifier ?? ""
            let usesUSB = app.isLaunchUSBPendingPlaceholder
                || AVConnectionManager.sharedInstance.channelUsesUSB(app.channel)
            let channelTag = AVMCPChannelTag(usb: usesUSB).rawValue
            let idSuffix = bundleId.isEmpty ? "pending-usb" : bundleId
            setAccessibilityIdentifier("appview.launch.app.\(idSuffix).\(channelTag)")
            setAccessibilityLabel(appInfo.appName ?? appInfo.deviceDescription ?? bundleId)
            setAccessibilityElement(true)
        }

        updateLayer()
        needsLayout = true
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        hoverBgLayer.opacity = 1
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoverBgLayer.opacity = 0
    }

    override func updateLayer() {
        super.updateLayer()
        let dark = effectiveAppearance.lk_isDarkMode
        hoverBgLayer.backgroundColor = (dark ? AppViewColorRGBAMake(0, 0, 0, 0.17) : AppViewColorRGBAMake(0, 0, 0, 0.08)).cgColor

        if app?.serverVersionError != nil {
            layer?.backgroundColor = (dark ? AppViewColorRGBAMake(0, 0, 0, 0.13) : AppViewColorRGBAMake(0, 0, 0, 0.05)).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let newArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newArea)
    }

    private func initErrorViewsIfNeeded() {
        if errorImageView == nil {
            let imageView = NSImageView()
            imageView.image = NSImageMake("icon_alert_big")
            addSubview(imageView)
            errorImageView = imageView
        }
        if errorTitleLabel == nil {
            let label = AVLabel()
            label.textColor = .labelColor
            label.alignment = .center
            label.maximumNumberOfLines = 0
            addSubview(label)
            errorTitleLabel = label
        }
        if errorSubtitleLabel == nil {
            let label = AVLabel()
            label.stringValue = NSLocalizedString("Find solution…", comment: "")
            label.textColor = .linkColor
            addSubview(label)
            errorSubtitleLabel = label
        }
    }
}
