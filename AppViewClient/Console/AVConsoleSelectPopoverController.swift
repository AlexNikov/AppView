//
//  AVConsoleSelectPopoverController.swift
//  AppView
//

import AppKit
import AppViewShared
import RxSwift

final class AVConsoleSelectPopoverController: AVBaseViewController {
    private var dataSource: AVConsoleDataSource!
    private var historyTitleView: AVImageTextView!
    private var historyControls: [AVConsoleSelectPopoverItemControl] = []
    private var highlightControls: [AVConsoleSelectPopoverItemControl] = []
    private var highlightTitleView: AVImageTextView!
    private var toggleButton: NSButton!
    private var sepLayer: CALayer!

    private let insets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
    private let titleMarginTop: CGFloat = 16
    private let itemControlMarginTop: CGFloat = 5
    private let toggleButtonMarginTop: CGFloat = 22

    var needShowError: ((NSError) -> Void)?
    var needClose: (() -> Void)?

    private let disposeBag = DisposeBag()

    init(dataSource: AVConsoleDataSource) {
        self.dataSource = dataSource
        super.init(containerView: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func makeContainerView() -> NSView {
        let view = AVBaseView()

        historyTitleView = AVImageTextView()
        historyTitleView.imageMargins = HorizontalMarginsMake(0, 5)
        historyTitleView.imageView.image = NSImageMake("console_history")
        historyTitleView.label.stringValue = NSLocalizedString("Objects returned recently in console", comment: "")
        view.addSubview(historyTitleView)

        highlightTitleView = AVImageTextView()
        highlightTitleView.imageMargins = HorizontalMarginsMake(0, 5)
        highlightTitleView.imageView.image = NSImageMake("icon_cursor")
        highlightTitleView.label.stringValue = NSLocalizedString("Objects highlighted in hierarchy panel", comment: "")
        view.addSubview(highlightTitleView)

        toggleButton = NSButton()
        toggleButton.setButtonType(.switch)
        toggleButton.title = NSLocalizedString(
            "Automatically make highlighted view in hierarchy panel as console target",
            comment: ""
        )
        toggleButton.font = NSFontMake(12)
        toggleButton.target = self
        toggleButton.action = #selector(handleToggleSyncButton)
        view.addSubview(toggleButton)

        AVPreferenceMain().syncConsoleTargetObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, checked in
                owner.toggleButton.state = checked ? .on : .off
            }
            .disposed(by: disposeBag)

        sepLayer = CALayer()
        sepLayer.appview_removeImplicitAnimations()
        view.layer?.addSublayer(sepLayer)

        view.didChangeAppearanceBlock = { [weak self] _, isDarkMode in
            guard let self else { return }
            if isDarkMode {
                self.sepLayer.backgroundColor = NSColor(white: 1, alpha: 0.2).cgColor
            } else {
                self.sepLayer.backgroundColor = NSColor(white: 0, alpha: 0.12).cgColor
            }
        }

        return view
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        var y = insets.top

        if !historyTitleView.isHidden {
            lk(historyTitleView).sizeToFit().x(insets.left).y(y)
            y = historyTitleView.frame.maxY
        }
        for control in historyControls {
            lk(control).x(insets.left).toRight(insets.right).heightToFit().y(y + itemControlMarginTop)
            y = control.frame.maxY
        }
        if !highlightTitleView.isHidden {
            if !historyTitleView.isHidden {
                y += titleMarginTop
            }
            lk(highlightTitleView).sizeToFit().x(insets.left).y(y)
            y = highlightTitleView.frame.maxY
        }
        for control in highlightControls {
            lk(control).x(insets.left).toRight(insets.right).heightToFit().y(y + itemControlMarginTop)
            y = control.frame.maxY
        }

        let toggleHeight = toggleButton.sizeThatFits(NSSizeMax).height + 2
        lk(toggleButton).x(insets.left).toRight(insets.right).y(y + toggleButtonMarginTop).height(toggleHeight)
        lk(sepLayer).x(insets.left).toRight(insets.right).height(1).y(toggleButton.frame.origin.y - 7)
    }

    func bestHeight() -> CGFloat {
        var height = insets.top + insets.bottom
        if !historyTitleView.isHidden {
            height += historyTitleView.sizeThatFits(NSSizeMax).height
        }
        if !highlightTitleView.isHidden {
            height += highlightTitleView.sizeThatFits(NSSizeMax).height
            if !historyTitleView.isHidden {
                height += titleMarginTop
            }
        }
        for control in historyControls + highlightControls {
            height += control.sizeThatFits(NSSizeMax).height + itemControlMarginTop
        }
        height += toggleButton.sizeThatFits(NSSizeMax).height + toggleButtonMarginTop
        return height
    }

    func reRender() {
        if dataSource.recentObjects.isEmpty {
            historyControls = historyControls.appview_resize(count: 1, add: { [weak self] _ in
                let control = AVConsoleSelectPopoverItemControl()
                control.addTarget(self, clickAction: #selector(AVConsoleSelectPopoverController.handleControl(_:)))
                self?.view.addSubview(control)
                return control
            }, remove: { _, control in
                control.removeFromSuperview()
            }, doNext: { _, control in
                control.title = NSLocalizedString("No object was returned yet", comment: "")
                control.isChecked = false
                control.representedObject = nil
            })
        } else {
            historyControls = historyControls.appview_resize(
                count: dataSource.recentObjects.count,
                add: { [weak self] _ in
                    let control = AVConsoleSelectPopoverItemControl()
                    control.addTarget(self, clickAction: #selector(AVConsoleSelectPopoverController.handleControl(_:)))
                    self?.view.addSubview(control)
                    return control
                },
                remove: { _, control in
                    control.removeFromSuperview()
                },
                doNext: { idx, control in
                    let recent = self.dataSource.recentObjects[Int(idx)]
                    let targetObject = recent.object
                    control.title = String(
                        format: "<%@: %@>",
                        targetObject.lk_simpleDemangledClassName,
                        targetObject.memoryAddress ?? ""
                    )
                    control.subtitle = recent.message
                    control.isChecked = self.dataSource.currentObject?.oid == targetObject.oid
                    control.representedObject = targetObject
                }
            )
        }

        highlightTitleView.isHidden = dataSource.selectedObjects.isEmpty
        highlightControls = highlightControls.appview_resize(
            count: dataSource.selectedObjects.count,
            add: { [weak self] _ in
                let control = AVConsoleSelectPopoverItemControl()
                control.addTarget(self, clickAction: #selector(AVConsoleSelectPopoverController.handleControl(_:)))
                self?.view.addSubview(control)
                return control
            },
            remove: { _, control in
                control.removeFromSuperview()
            },
            doNext: { idx, control in
                let targetObject = self.dataSource.selectedObjects[Int(idx)]
                control.title = String(
                    format: "<%@: %@>",
                    targetObject.lk_simpleDemangledClassName,
                    targetObject.memoryAddress ?? ""
                )
                control.isChecked = self.dataSource.currentObject?.oid == targetObject.oid
                control.representedObject = targetObject
            }
        )

        view.needsLayout = true
    }

    @objc private func handleControl(_ control: AVConsoleSelectPopoverItemControl) {
        guard let obj = control.representedObject else { return }
        dataSource.makeObjectAsCurrent(obj)
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                if obj.oid != self.dataSource.selectedObjects.last?.oid {
                    AVPreferenceMain().syncConsoleTarget = false
                }
                self.needClose?()
            }, onError: { [weak self] _ in
                self?.needShowError?(AVAppViewClientErrors.noConnect)
            })
            .disposed(by: disposeBag)
    }

    @objc private func handleToggleSyncButton() {
        let mng = AVPreferenceMain()
        mng.syncConsoleTarget = !mng.syncConsoleTarget
        if mng.syncConsoleTarget, let last = dataSource.selectedObjects.last {
            dataSource.makeObjectAsCurrent(last)
                .subscribe(onNext: { [weak self] _ in
                    self?.reRender()
                })
                .disposed(by: disposeBag)
        }
    }
}
