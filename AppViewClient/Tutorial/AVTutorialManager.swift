//
//  AVTutorialManager.swift
//  AppView
//

import AppKit
import Foundation

private let Key_TogglePreview = "Tut_2"
private let Key_QuickSelection = "Tut_5"
private let Key_MoveWithSpace = "Tut_6"
private let Key_CopyTitle = "Tut_8"
private let Key_EventsHandler = "Tut_EventsHandler"
private let Key_DoubleClickBehavior = "Tut_DoubleClickBehavior"

class AVTutorialManager: NSObject, NSPopoverDelegate {
    private static let _shared = AVTutorialManager()

    class func sharedInstance() -> AVTutorialManager {
        _shared
    }

    var togglePreview = false {
        didSet {
            guard togglePreview != oldValue else { return }
            UserDefaults.standard.set(togglePreview, forKey: Key_TogglePreview)
        }
    }

    var quickSelection = false {
        didSet {
            guard quickSelection != oldValue else { return }
            UserDefaults.standard.set(quickSelection, forKey: Key_QuickSelection)
        }
    }

    var moveWithSpace = false {
        didSet {
            guard moveWithSpace != oldValue else { return }
            UserDefaults.standard.set(moveWithSpace, forKey: Key_MoveWithSpace)
        }
    }

    var copyTitle = false {
        didSet {
            guard copyTitle != oldValue else { return }
            UserDefaults.standard.set(copyTitle, forKey: Key_CopyTitle)
        }
    }

    var eventsHandler = false {
        didSet {
            guard eventsHandler != oldValue else { return }
            UserDefaults.standard.set(eventsHandler, forKey: Key_EventsHandler)
        }
    }

    var hasAskedDoubleClickBehavior = false {
        didSet {
            UserDefaults.standard.set(hasAskedDoubleClickBehavior, forKey: Key_DoubleClickBehavior)
        }
    }

    var hasAlreadyShowedTipsThisLaunch = false

    override init() {
        super.init()
        let defaults = UserDefaults.standard
        togglePreview = defaults.bool(forKey: Key_TogglePreview)
        quickSelection = defaults.bool(forKey: Key_QuickSelection)
        moveWithSpace = defaults.bool(forKey: Key_MoveWithSpace)
        copyTitle = defaults.bool(forKey: Key_CopyTitle)
        eventsHandler = defaults.bool(forKey: Key_EventsHandler)
        hasAskedDoubleClickBehavior = defaults.bool(forKey: Key_DoubleClickBehavior)
    }

    func showPopover(of view: NSView, text: String, learned learnedBlock: (() -> Void)?) {
        let popover = NSPopover()
        let vc = AVTutorialPopoverController(text: text, popover: popover)
        vc.learnedBlock = learnedBlock
        popover.delegate = self
        popover.animates = true
        popover.behavior = .transient
        popover.contentSize = vc.contentSize()
        popover.contentViewController = vc
        popover.show(
            relativeTo: NSRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height),
            of: view,
            preferredEdge: .maxY
        )
        vc.showTimestamp = CurrentTime
    }

    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover,
              let tutorialVC = popover.contentViewController as? AVTutorialPopoverController else {
            assertionFailure()
            return
        }
        if tutorialVC.hasClickedCloseButton || (CurrentTime - tutorialVC.showTimestamp > 1.8) {
            tutorialVC.learnedBlock?()
        }
    }
}
