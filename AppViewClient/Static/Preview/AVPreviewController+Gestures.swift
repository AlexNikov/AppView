import AppKit
import AppViewShared

extension AVPreviewController {
    // MARK: - Gestures

    @objc func handlePanGesture(_ recognizer: AVPreviewPanGestureRecognizer) {
        if recognizer.state == .began {
            AVUserActionManager.sharedInstance.send(.previewOperation)
            view.window?.makeFirstResponder(self)

            if isKeyingDownSpace {
                recognizer.purpose = .translate
                if staticViewController?.isShowingMoveWithSpaceTutorialTips == true {
                    staticViewController?.removeTutorialTips()
                }
            } else {
                recognizer.purpose = .rotate
            }
            recognizer.initialRotation = previewView.rotation
            let t = previewView.translation
            recognizer.initialTranslation = NSPoint(x: t.x, y: t.y)
        } else if recognizer.state == .changed {
            let translation = recognizer.translation(in: view)
            if recognizer.purpose == .rotate {
                guard previewView.dimension == .dimension3D else { return }
                let newRotationX = recognizer.initialRotation.x + translation.x * 0.01
                let newRotationY: CGFloat
                if dataSource.preferenceManager().freeRotation {
                    newRotationY = recognizer.initialRotation.y + translation.y * 0.004
                } else {
                    newRotationY = 0
                }
                previewView.setRotation(CGPoint(x: newRotationX, y: newRotationY), animated: false)
            } else if recognizer.purpose == .translate {
                TutorialMng.moveWithSpace = true
                if staticViewController?.isShowingMoveWithSpaceTutorialTips == true {
                    staticViewController?.removeTutorialTips()
                }
                let currentScale = previewView.scale
                let factor = (1 - currentScale) * 0.92 + 0.08
                let initial = recognizer.initialTranslation
                previewView.translation = CGPoint(
                    x: initial.x + translation.x * 0.01 * factor,
                    y: initial.y - translation.y * 0.01 * factor
                )
            }
        }
    }

    @objc func handleClickGesture(_ recognizer: NSClickGestureRecognizer) {
        AVUserActionManager.sharedInstance.send(.previewOperation)
        view.window?.makeFirstResponder(self)

        let point = recognizer.location(in: previewView)
        guard let item = previewView.displayItem(at: point) else { return }
        if dataSource.selectedItem === item { return }

        if !item.displayingInHierarchy {
            TutorialMng.quickSelection = true
            if staticViewController?.isShowingQuickSelectTutorialTips == true {
                staticViewController?.removeTutorialTips()
            }
            dataSource.expandToShowItem(item)
        }
        dataSource.selectedItem = item

        if !TutorialMng.hasAlreadyShowedTipsThisLaunch, !TutorialMng.togglePreview {
            let parsedRotation = (previewView.rotation.x * 180.0) / .pi
            if (parsedRotation > 75 && parsedRotation < 100) || (parsedRotation < -75 && parsedRotation > -100) {
                TutorialMng.togglePreview = true
                TutorialMng.hasAlreadyShowedTipsThisLaunch = true
                staticViewController?.showNoPreviewTutorialTips()
            }
        }
    }

    @objc func handleRightClick(_ recognizer: NSClickGestureRecognizer) {
        AVUserActionManager.sharedInstance.send(.previewOperation)
        view.window?.makeFirstResponder(self)

        let point = recognizer.location(in: previewView)
        guard let item = previewView.displayItem(at: point), item.displayingInHierarchy else { return }

        if dataSource.selectedItem !== item {
            dataSource.selectedItem = item
        }
        rightClickingDisplayItem = item
        rightClickMenu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
        AVUserActionManager.sharedInstance.send(.previewOperation)
        view.window?.makeFirstResponder(self)

        let point = recognizer.location(in: previewView)
        guard let item = previewView.displayItem(at: point) else { return }

        if AVPreferenceManager.popupToAskDoubleClickBehaviorIfNeeded(with: view.window) {
            return
        }

        if !item.displayingInHierarchy {
            dataSource.expandToShowItem(item)
        }

        let behavior = AVPreferenceMain().doubleClickBehavior
        if behavior == .collapse {
            guard item.isExpandable else {
                dataSource.selectedItem = item
                return
            }
            if item.isExpanded {
                dataSource.collapseItem(item)
            } else {
                dataSource.expandItem(item)
            }
        } else if behavior == .focus {
            dataSource.focusDisplayItem(item)
            return
        } else {
            assertionFailure()
        }

        dataSource.selectedItem = item
    }
}
