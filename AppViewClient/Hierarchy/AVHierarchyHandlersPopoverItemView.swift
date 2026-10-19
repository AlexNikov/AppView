//
//  AVHierarchyHandlersPopoverItemView.swift
//  AppView
//

import AppKit
import AppViewShared
import RxSwift

class AVHierarchyHandlersPopoverItemView: AVBaseView {
    var needTopBorder = false {
        didSet { topSepLayer.isHidden = !needTopBorder }
    }

    private var eventHandler: AppViewEventHandler!
    private var iconImageView: NSImageView!
    private var titleLabel: AVLabel!
    private var subtitleLabel: AVLabel?
    private var recognizerEnableButton: NSButton?
    private var contentView: AVTextsMenuView!
    private var topSepLayer: CALayer!

    private let contentX: CGFloat = 28
    private let insetRight: CGFloat = 16
    private let verInset: CGFloat = 10
    private let contentMarginTop: CGFloat = 4
    private let subtitleMarginTop: CGFloat = 3

    init(eventHandler: AppViewEventHandler, editable: Bool) {
        super.init(frame: .zero)

        self.eventHandler = eventHandler

        topSepLayer = CALayer()
        layer?.addSublayer(topSepLayer)

        iconImageView = NSImageView()
        addSubview(iconImageView)

        titleLabel = AVLabel()
        titleLabel.isSelectable = true
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(titleLabel)

        contentView = AVTextsMenuView()
        contentView.font = NSFontMake(13)
        addSubview(contentView)

        let darkMode = AppViewClientIsDarkMode()
        topSepLayer.backgroundColor = darkMode
            ? AppViewColorRGBAMake(255, 255, 255, 0.15).cgColor
            : AppViewColorRGBAMake(0, 0, 0, 0.12).cgColor

        var texts: [AppViewStringTwoTuple] = []

        if eventHandler.handlerType == .gesture {
            texts.append(AppViewStringTwoTuple.tuple(withFirst: "Enabled", second: ""))

            if editable {
                let button = NSButton()
                button.setButtonType(.switch)
                button.title = ""
                button.target = self
                button.action = #selector(handleGestureButton(_:))
                renderRecognizerEnabledButton()
                contentView.add(button, atIndex: 0)
                recognizerEnableButton = button
            } else {
                texts.append(AppViewStringTwoTuple.tuple(withFirst: "Enabled",
                    second: eventHandler.gestureRecognizerIsEnabled ? "YES" : "NO"
                ))
            }

            texts.append(AppViewStringTwoTuple.tuple(withFirst: "Delegate",
                second: eventHandler.gestureRecognizerDelegator ?? "nil"
            ))
            titleLabel.font = NSFont.boldSystemFont(ofSize: 12)
        } else {
            titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        }

        let targetActions = eventHandler.targetActions ?? []
        if targetActions.isEmpty {
            texts.append(AppViewStringTwoTuple.tuple(withFirst: "Target", second: "nil"))
            texts.append(AppViewStringTwoTuple.tuple(withFirst: "Action", second: "NULL"))
        } else if targetActions.count == 1, let tuple = targetActions.first {
            texts.append(AppViewStringTwoTuple.tuple(withFirst: "Target", second: tuple.first ?? ""))
            texts.append(AppViewStringTwoTuple.tuple(withFirst: "Action", second: tuple.second ?? ""))
        } else {
            for (idx, tuple) in targetActions.enumerated() {
                texts.append(AppViewStringTwoTuple.tuple(withFirst: "Target \(idx + 1)", second: tuple.first ?? ""))
                texts.append(AppViewStringTwoTuple.tuple(withFirst: "Action \(idx + 1)", second: tuple.second ?? ""))
            }
        }
        contentView.texts = texts

        titleLabel.stringValue = eventHandler.eventName ?? ""
        if eventHandler.handlerType == .gesture {
            iconImageView.image = NSImageMake("icon_gesture_tap")
        } else if eventHandler.eventName?.hasPrefix("UIControlEventEditing") == true {
            iconImageView.image = NSImageMake("icon_targetaction_edit")
        } else {
            iconImageView.image = NSImageMake("icon_targetaction_touch")
        }

        if eventHandler.handlerType == .gesture {
            var subtitleTexts: [String] = []
            if let inheritedRecognizerName = eventHandler.inheritedRecognizerName {
                subtitleTexts.append("\(NSLocalizedString("Inherits from", comment: "")) \(inheritedRecognizerName)")
            }
            subtitleTexts.append(contentsOf: eventHandler.recognizerIvarTraces ?? [])
            if !subtitleTexts.isEmpty {
                let label = AVLabel()
                label.textColor = darkMode
                    ? NSColorGray9.withAlphaComponent(0.5)
                    : NSColorGray1.withAlphaComponent(0.6)
                label.stringValue = subtitleTexts.joined(separator: "\n")
                label.isSelectable = true
                label.font = NSFontMake(12)
                label.maximumNumberOfLines = 0
                label.lineBreakMode = .byTruncatingMiddle
                addSubview(label)
                subtitleLabel = label
            }
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()

        lk(topSepLayer).x(contentX).toRight(insetRight).y(0).height(1)
        lk(titleLabel).x(contentX).toRight(insetRight).appview_heightToFit().y(verInset)

        var y = titleLabel.frame.maxY
        if let subtitleLabel {
            lk(subtitleLabel).x(contentX).toRight(insetRight).appview_heightToFit().y(y + subtitleMarginTop)
            y = subtitleLabel.frame.maxY
        }

        lk(contentView).x(contentX).toRight(insetRight).appview_heightToFit().y(y + contentMarginTop)
        lk(iconImageView).sizeToFit().midX(contentX / 2.0 + 1).midY(titleLabel.frame.midY)
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        var size = limitedSize
        let titleSize = titleLabel.bestSize
        let contentSize = contentView.sizeThatFits(NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        let subtitleSize = subtitleLabel?.bestSize ?? .zero
        size.width = max(max(titleSize.width, contentSize.width), subtitleSize.width) + contentX + insetRight + 2
        size.height = titleSize.height + contentSize.height + contentMarginTop + verInset * 2
        if subtitleLabel != nil {
            size.height += subtitleMarginTop + subtitleSize.height
        }
        return size
    }

    @objc
    private func handleGestureButton(_ button: NSButton) {
        let mainWindow = AVNavigationManager.sharedInstance.staticWindowController?.window

        guard let inspectingApp = InspectingApp else {
            AlertError(AVAppViewClientErrors.noConnect, mainWindow)
            renderRecognizerEnabledButton()
            return
        }

        let shouldEnableRecognizer = button.state == .on
        _ = inspectingApp.modifyGestureRecognizer(UInt(truncatingIfNeeded: eventHandler.recognizerOid), toBeEnabled: shouldEnableRecognizer)
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onCompleted: { owner in
                owner.eventHandler.gestureRecognizerIsEnabled = shouldEnableRecognizer
                owner.renderRecognizerEnabledButton()
            }, onError: { owner, error in
                AlertError((error as NSError?) ?? AVAppViewClientErrors.inner, mainWindow)
                owner.renderRecognizerEnabledButton()
            })
    }

    private func renderRecognizerEnabledButton() {
        recognizerEnableButton?.state = eventHandler.gestureRecognizerIsEnabled ? .on : .off
    }
}
