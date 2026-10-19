//
//  AVPreviewStageView.swift
//  AppView
//

import AppKit

protocol AVPreviewStageViewDelegate: AnyObject {
    func previewStageView(_ view: AVPreviewStageView, mouseMoved event: NSEvent)
    func previewStageView(_ view: AVPreviewStageView, mouseExited event: NSEvent)
    func didResetCursorRects(in previewStageView: AVPreviewStageView)
}

final class AVPreviewStageView: AVBaseView {
    weak var delegate: AVPreviewStageViewDelegate?

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        delegate?.previewStageView(self, mouseMoved: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        delegate?.previewStageView(self, mouseExited: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for oldArea in trackingAreas {
            removeTrackingArea(oldArea)
        }
        let newArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newArea)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        delegate?.didResetCursorRects(in: self)
    }
}
