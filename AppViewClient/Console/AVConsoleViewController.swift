//
//  AVConsoleViewController.swift
//  AppView
//

import AppKit
import AppViewShared
import RxSwift

final class AVConsoleViewController: AVBaseViewController, AVTableViewDelegate, AVTableViewDataSource {
    private var dataSource: AVConsoleDataSource!
    private var tableView: AVTableView!
    private var clearButton: NSButton!
    private var inputRowView: AVConsoleInputRowView!
    private var topBorderLayer: CALayer!

    private let disposeBag = DisposeBag()
    private let calculatingReturnRowViewKey = "calculatingReturnRowView"

    init(hierarchyDataSource: AVHierarchyDataSource) {
        dataSource = AVConsoleDataSource(hierarchyDataSource: hierarchyDataSource)
        super.init(containerView: nil)

        dataSource.rowItemsObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, _ in
                owner.tableView.reloadData()
                owner.tableView.layoutSubtreeIfNeeded()
                if !owner.dataSource.rowItems.isEmpty {
                    owner.tableView.scrollRowToVisible(owner.dataSource.rowItems.count - 1)
                }
                owner.inputRowView.makeTextFieldAsFirstResponder()
            }
            .disposed(by: disposeBag)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func makeContainerView() -> NSView {
        let containerView = AVBaseView()
        containerView.backgroundColorName = "ConsoleBackgroundColor"

        inputRowView = AVConsoleInputRowView(dataSource: dataSource)

        tableView = AVTableView()
        tableView.drawsBackground = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.canScrollHorizontally = false
        tableView.adjustsSelectionAutomatically = false
        tableView.adjustsHoverAutomatically = false
        tableView.automaticallyAdjustsContentInsets = false
        tableView.contentInsets = NSEdgeInsets(top: 5, left: 0, bottom: 5, right: 0)
        containerView.addSubview(tableView)

        let clearButtonImage = NSImageMake("icon_delete")
        clearButtonImage?.isTemplate = true
        clearButton = NSButton()
        clearButton.image = clearButtonImage
        clearButton.bezelStyle = .rounded
        clearButton.isBordered = false
        clearButton.target = self
        clearButton.action = #selector(handleClearButton)
        containerView.addSubview(clearButton)

        topBorderLayer = CALayer()
        topBorderLayer.appview_removeImplicitAnimations()
        containerView.layer?.addSublayer(topBorderLayer)

        containerView.didChangeAppearanceBlock = { [weak self] _, isDarkMode in
            guard let self else { return }
            if isDarkMode {
                self.topBorderLayer.backgroundColor = NSColor(white: 1, alpha: 0.12).cgColor
            } else {
                self.topBorderLayer.backgroundColor = NSColor(white: 0, alpha: 0.15).cgColor
            }
        }

        return containerView
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        DispatchQueue.main.asyncAfter(deadline: .now() + AVUITiming.brief) { [weak self] in
            guard let self else { return }
            self.tableView.scrollRowToVisible(self.dataSource.rowItems.count - 1)
            self.inputRowView.makeTextFieldAsFirstResponder()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        lk(topBorderLayer).fullWidth().height(1).y(0)
        lk(tableView).fullFrame()
        lk(clearButton).sizeToFit().right(20).bottom(8)

        let prevWidth = appview_getBindDouble(forKey: "prevWidth")
        if prevWidth != view.bounds.width {
            appview_bindDouble(view.bounds.width, forKey: "prevWidth")
            tableView.reloadData()
        }
    }

    @objc private func handleClearButton() {
        dataSource.clearHistoryContents()
    }

    var isControllerShowing: Bool {
        get { dataSource.isShowingConsole }
        set { dataSource.isShowingConsole = newValue }
    }

    func submit(withObj obj: AppViewObject, text: String) {
        dataSource.submit(withObj: obj, text: text)
            .subscribe(onError: { error in
                NSLog("Submit error: %@", error.localizedDescription)
            })
            .disposed(by: disposeBag)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        dataSource.rowItems.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < dataSource.rowItems.count else { return 0 }
        let item = dataSource.rowItems[row]
        switch item.type {
        case .input, .submit:
            return 20
        case .return:
            var calculatingView = appview_getBindObject(forKey: calculatingReturnRowViewKey) as? AVConsoleReturnRowView
            if calculatingView == nil {
                calculatingView = AVConsoleReturnRowView()
                appview_bindObject(calculatingView, forKey: calculatingReturnRowViewKey)
            }
            calculatingView?.titleLabel.stringValue = item.normalText ?? ""
            return calculatingView?.heightForWidth(self.tableView.bounds.width) ?? 0
        @unknown default:
            return 0
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard row >= 0, row < dataSource.rowItems.count else {
            return AVTableBlankRowView()
        }
        let item = dataSource.rowItems[row]

        switch item.type {
        case .input:
            return inputRowView
        case .submit:
            var view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("submit"), owner: self) as? AVConsoleSubmitRowView
            if view == nil {
                view = AVConsoleSubmitRowView()
                view?.identifier = NSUserInterfaceItemIdentifier("submit")
            }
            view?.titleLabel.stringValue = item.highlightText ?? ""
            view?.subtitleLabel.stringValue = item.normalText ?? ""
            view?.needsLayout = true
            return view
        case .return:
            var view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("return"), owner: self) as? AVConsoleReturnRowView
            if view == nil {
                view = AVConsoleReturnRowView()
                view?.identifier = NSUserInterfaceItemIdentifier("return")
            }
            view?.titleLabel.stringValue = item.normalText ?? ""
            view?.needsLayout = true
            return view
        @unknown default:
            return AVTableBlankRowView()
        }
    }

    func tableViewDidClickBlankArea(_ tableView: AVTableView) {
        inputRowView.makeTextFieldAsFirstResponder()
    }
}
