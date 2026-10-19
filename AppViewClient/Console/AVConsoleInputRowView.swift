//
//  AVConsoleInputRowView.swift
//  AppView
//

import AppKit
import AppViewShared
import RxSwift

final class AVConsoleInputRowView: AVTableRowView, AVInputSearchViewDelegate {
    private var dataSource: AVConsoleDataSource!
    private var selectButton: NSButton!
    private var inputView: AVInputSearchView!
    private var selectPopoverController: AVConsoleSelectPopoverController!

    private let disposeBag = DisposeBag()

    init(dataSource: AVConsoleDataSource) {
        self.dataSource = dataSource
        super.init(frame: .zero)

        selectPopoverController = AVConsoleSelectPopoverController(dataSource: dataSource)
        selectPopoverController.needShowError = { [weak self] error in
            guard let self, let window = self.window else { return }
            NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
        }

        selectButton = NSButton()
        selectButton.font = NSFontMake(13)
        selectButton.imagePosition = .imageRight
        selectButton.bezelStyle = .rounded
        selectButton.isBordered = false
        selectButton.image = NSImageMake("Console_UpDownArrow")
        selectButton.target = self
        selectButton.action = #selector(handleSelectButton)
        addSubview(selectButton)

        inputView = AVInputSearchView(throttleTime: 0.15)
        inputView.delegate = self
        inputView.textField.focusRingType = NSFocusRingType.none
        addSubview(inputView)

        setIsDarkMode(effectiveAppearance.lk_isDarkMode)

        dataSource.currentObjectObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, _ in
                owner.handleCurrentObjectDidChange()
            }
            .disposed(by: disposeBag)

        dataSource.selectorNamesDidUpdateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, _ in
                owner.inputView.refreshSuggestionsIfNeeded()
            }
            .disposed(by: disposeBag)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        lk(selectButton).fullHeight().widthToFit().lk_maxWidth(bounds.width * 0.5).x(ConsoleInsetLeft)
        lk(inputView).x(selectButton.frame.maxX + 5).toRight(ConsoleInsetRight).fullHeight()
    }

    override func setIsDarkMode(_ isDarkMode: Bool) {
        super.setIsDarkMode(isDarkMode)
        handleCurrentObjectDidChange()
    }

    func makeTextFieldAsFirstResponder() {
        window?.makeFirstResponder(inputView.textField)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard selectButton.frame.contains(point), let obj = dataSource.currentObject else {
            super.rightMouseDown(with: event)
            return
        }
        let title = String(format: "<%@: %@>", obj.lk_simpleDemangledClassName, obj.memoryAddress ?? "")
        let menu = NSMenu()
        let item = NSMenuItem(title: NSLocalizedString("Copy", comment: ""), action: #selector(handleCopyCurrentObject), keyEquivalent: "")
        item.representedObject = title
        item.target = self
        menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func handleCopyCurrentObject(_ sender: NSMenuItem) {
        guard let title = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(title, forType: .string)
    }

    @objc private func handleSelectButton() {
        selectPopoverController.reRender()
        let popover = NSPopover()
        popover.animates = false
        popover.behavior = .transient
        popover.contentSize = NSSize(
            width: IsEnglish ? 465 : 400,
            height: selectPopoverController.bestHeight()
        )
        popover.contentViewController = selectPopoverController
        popover.show(
            relativeTo: NSRect(x: 0, y: 0, width: selectButton.bounds.width, height: selectButton.bounds.height),
            of: selectButton,
            preferredEdge: .minY
        )
        selectPopoverController.needClose = { [weak popover] in
            popover?.close()
        }
    }

    private func handleCurrentObjectDidChange() {
        inputView.clearContentAndSuggestions()

        let selectButtonColor = isDarkMode ? AppViewColorMake(85, 200, 95) : AppViewColorMake(54, 155, 62)
        if let obj = dataSource.currentObject {
            let string = String(
                format: "<%@: %@>",
                obj.lk_simpleDemangledClassName,
                obj.memoryAddress ?? ""
            )
            selectButton.attributedTitle = AVAttrString(string).textColor(selectButtonColor).build()
            inputView.textField.isEditable = true
            inputView.textField.placeholderString = NSLocalizedString("Type property or method name here", comment: "")
        } else {
            let str = NSLocalizedString("Select target object", comment: "")
            selectButton.attributedTitle = AVAttrString(str).textColor(selectButtonColor).build()
            inputView.textField.isEditable = false
            inputView.textField.placeholderString = ""
        }
        needsLayout = true
    }

    func inputSearchView(_ view: AVInputSearchView, suggestionsForString string: String) -> [AVInputSearchSuggestionItem] {
        guard string.count >= 3 else { return [] }
        let candidates = dataSource.currentObjectSelectorNameList() ?? []
        if candidates.isEmpty {
            dataSource.fetchSelectorNamesIfNeeded()
            return []
        }
        var array: [AVInputSearchSuggestionItem] = []
        let suggestions = AVHelper.bestMatchesInCandidates(candidates, input: string, maxResultsCount: 8)
        for text in suggestions {
            let item = AVInputSearchSuggestionItem()
            item.image = NSImageMake("icon_method")
            item.text = text
            array.append(item)
        }
        return array
    }

    func inputSearchView(_ view: AVInputSearchView, submitText text: String) {
        dataSource.submit(text)
            .subscribe(onNext: { [weak view] _ in
                view?.clearContentAndSuggestions()
            }, onError: { [weak self] error in
                AlertError(error as NSError, self?.window)
            })
            .disposed(by: disposeBag)
    }
}
