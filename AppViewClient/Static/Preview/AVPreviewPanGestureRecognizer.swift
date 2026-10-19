//
//  AVPreviewPanGestureRecognizer.swift
//  AppView
//

import AppKit

enum PreviewPanGesturePurpose: UInt {
    case rotate
    case translate
}

final class AVPreviewPanGestureRecognizer: NSPanGestureRecognizer {
    var purpose: PreviewPanGesturePurpose = .rotate
    var initialRotation: CGPoint = .zero
    var initialTranslation: NSPoint = .zero
}
