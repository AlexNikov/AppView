//
//  AVWindowToolbarAppButton.swift
//  AppViewClient
//
//  Created by 李凯 on 2020/6/14.
//

import AppKit
import AppViewShared

class AVWindowToolbarAppButton: NSButton {
    private var appImageView: NSImageView!
    private var appNameLabel: AVLabel!
    private var sepImageView: NSImageView!
    private var deviceImageView: NSImageView!
    private var deviceLabel: AVLabel!
    private let appImageWidth: CGFloat = 14
    private let spaces: [CGFloat] = [7, 3, 3, 4, 1]

    var appInfo: AppViewAppInfo? {
        didSet { updateAppInfo() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        setAccessibilityIdentifier("appview.toolbar.selectApp")
        setAccessibilityLabel("Select App")

        appImageView = NSImageView()
        appImageView.wantsLayer = true
        appImageView.layer?.cornerRadius = 2
        appImageView.layer?.masksToBounds = true
        addSubview(appImageView)

        appNameLabel = AVLabel()
        appNameLabel.textColors = AVColorsCombine(AppViewColorMake(65, 65, 65), .labelColor)
        addSubview(appNameLabel)

        sepImageView = NSImageView()
        sepImageView.image = NSImageMake("icon_go_forward")
        sepImageView.image?.isTemplate = true
        addSubview(sepImageView)

        deviceImageView = NSImageView()
        addSubview(deviceImageView)

        deviceLabel = AVLabel()
        deviceLabel.textColors = AVColorsCombine(AppViewColorMake(65, 65, 65), .labelColor)
        deviceLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(deviceLabel)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        lk(appImageView).width(appImageWidth).height(appImageWidth).x(spaces[0]).verAlign().offsetY(-0.5)
        lk(appNameLabel).sizeToFit().verAlign().x(appImageView.frame.maxX + spaces[1]).offsetY(-1)
        lk(sepImageView).sizeToFit().verAlign().x(appNameLabel.frame.maxX + spaces[2]).offsetY(-0.5)
        lk(deviceImageView).sizeToFit().x(sepImageView.frame.maxX + spaces[3]).verAlign()
        lk(deviceLabel).sizeToFit().verAlign().x(deviceImageView.frame.maxX + spaces[4]).toMaxX(bounds.width).offsetY(-1)
    }

    private func updateAppInfo() {
        if let appInfo {
            appImageView.isHidden = false
            appNameLabel.isHidden = false
            sepImageView.isHidden = false
            deviceImageView.isHidden = false
            deviceLabel.isHidden = false
            image = nil

            let appIcon = appInfo.appIcon ?? NSImageMake("Icon_EmptyProject")
            appImageView.image = appIcon
            appNameLabel.stringValue = appInfo.appName ?? ""
            deviceLabel.stringValue = "\(appInfo.deviceDescription ?? "") (\(appInfo.osDescription ?? ""))"

            let deviceIcon: NSImage?
            switch appInfo.deviceType {
            case .simulator:
                deviceIcon = NSImageMake("icon_simulator_small")
            case .iPad:
                deviceIcon = NSImageMake("icon_ipad_small")
            case .others:
                deviceIcon = NSImageMake("icon_iphone_small")
            @unknown default:
                deviceIcon = NSImageMake("icon_simulator_small")
            }
            deviceImageView.image = deviceIcon
        } else {
            appImageView.isHidden = true
            appNameLabel.isHidden = true
            sepImageView.isHidden = true
            deviceImageView.isHidden = true
            deviceLabel.isHidden = true
            image = NSImageMake("icon_app")
        }
        needsLayout = true
    }

    override func sizeThatFits(_ size: NSSize) -> NSSize {
        var width = spaces.reduce(0, +)
        width += appImageWidth + appNameLabel.bestWidth + sepImageView.bestWidth +
            deviceImageView.bestWidth + deviceLabel.bestWidth
        var result = size
        result.width = width
        return result
    }
}
