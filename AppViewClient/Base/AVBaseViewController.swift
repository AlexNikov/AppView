//
//  AVBaseViewController.swift
//  AppView
//

import AppKit
import AppViewShared
import RxSwift

class AVBaseViewController: NSViewController {
    private(set) var isViewAppeared = false
    private(set) var connectionTipsView: AVRedTipsView!
    private var connectionTipsDisposeBag = DisposeBag()

    init(containerView view: NSView?) {
        super.init(nibName: nil, bundle: nil)
        self.view = view ?? makeContainerView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nil, bundle: nil)
        self.view = makeContainerView()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        isViewAppeared = true
    }

    override func loadView() {
        self.view = makeContainerView()
    }

    override var view: NSView {
        get { super.view }
        set {
            super.view = newValue
            appview_didSetView(newValue)
        }
    }

    func appview_didSetView(_ view: NSView) {
        guard shouldShowConnectionTips() else { return }

        connectionTipsDisposeBag = DisposeBag()
        connectionTipsView = AVRedTipsView()
        connectionTipsView.isHidden = true
        connectionTipsView.title = NSLocalizedString("Reconnecting…", comment: "")
        connectionTipsView.buttonText = NSLocalizedString("Change App", comment: "")
        connectionTipsView.target = self
        connectionTipsView.clickAction = #selector(handleClickReconnectTips)

        AVAppsManager.sharedInstance.inspectingAppObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, app in
                if let app {
                    owner.connectionTipsView.endAnimation()
                    owner.connectionTipsView.isHidden = true
                    owner.connectionTipsView.setImageByDeviceType(app.appInfo?.deviceType ?? .others)
                } else {
                    if owner.connectionTipsView.superview == nil {
                        owner.view.addSubview(owner.connectionTipsView)
                    }
                    owner.connectionTipsView.isHidden = false
                    owner.connectionTipsView.startAnimation()
                    owner.view.needsLayout = true
                }
            }
            .disposed(by: connectionTipsDisposeBag)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if let connectionTipsView, !connectionTipsView.isHidden {
            let windowTitleHeight = AVNavigationManager.sharedInstance.windowTitleBarHeight
            lk(connectionTipsView).sizeToFit().horAlign().y(windowTitleHeight + 10)
        }
    }

    @objc private func handleClickReconnectTips() {
        let wc = view.window?.windowController
        let staticWc = AVNavigationManager.sharedInstance.staticWindowController
        if wc === staticWc {
            staticWc?.popupAllInspectableApps(with: .noConnectionTips)
        } else if let staticWc {
            staticWc.showWindow(self)
            staticWc.popupAllInspectableApps(with: .noConnectionTips)
        } else {
            assertionFailure()
        }
    }

    func makeContainerView() -> NSView {
        AVBaseView()
    }

    func shouldShowConnectionTips() -> Bool {
        false
    }

    deinit {
        NSLog("%@ dealloc", String(describing: type(of: self)))
    }
}
