//
//  AVMeasureResultView.swift
//  AppView
//

import AppKit
import AppViewShared

class AVMeasureResultView: AVBaseView {
    private var contentView: AVBaseView!
    private var mainImageView: NSImageView!
    private var referImageView: NSImageView!
    private var linesContainerView: AVBaseView!
    private var horSolidLinesLayer: CAShapeLayer!
    private var verSolidLinesLayer: CAShapeLayer!
    private var mainImageViewBorderLayer: CALayer!
    private var referImageViewBorderLayer: CALayer!
    private var textFieldViews: [AVTextFieldView] = []

    private var originalMainFrame: CGRect = .zero
    private var originalReferFrame: CGRect = .zero
    private var scaledMainFrame: CGRect = .zero
    private var scaledReferFrame: CGRect = .zero

    private let horInset: CGFloat = 20
    private let verInset: CGFloat = 20
    private let labelHeight: CGFloat = 18

    private enum CompareResult {
        case bigger, same, smaller
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        hasEffectedBackground = true
        layer?.cornerRadius = DashboardCardCornerRadius

        contentView = AVBaseView()
        contentView.layer?.masksToBounds = false
        addSubview(contentView)

        mainImageView = NSImageView()
        mainImageView.imageScaling = .scaleProportionallyUpOrDown
        contentView.addSubview(mainImageView)

        referImageView = NSImageView()
        referImageView.imageScaling = .scaleProportionallyUpOrDown
        contentView.addSubview(referImageView)

        linesContainerView = AVBaseView()
        linesContainerView.layer?.masksToBounds = false
        contentView.addSubview(linesContainerView)

        mainImageViewBorderLayer = CALayer()
        mainImageViewBorderLayer.borderWidth = 1
        mainImageViewBorderLayer.appview_removeImplicitAnimations()
        linesContainerView.layer?.addSublayer(mainImageViewBorderLayer)

        referImageViewBorderLayer = CALayer()
        referImageViewBorderLayer.borderWidth = 1
        referImageViewBorderLayer.appview_removeImplicitAnimations()
        linesContainerView.layer?.addSublayer(referImageViewBorderLayer)

        horSolidLinesLayer = CAShapeLayer()
        horSolidLinesLayer.lineWidth = 1
        horSolidLinesLayer.appview_removeImplicitAnimations()
        horSolidLinesLayer.strokeColor = AppViewColorMake(10, 127, 251).cgColor
        linesContainerView.layer?.addSublayer(horSolidLinesLayer)

        verSolidLinesLayer = CAShapeLayer()
        verSolidLinesLayer.lineWidth = 1
        verSolidLinesLayer.appview_removeImplicitAnimations()
        verSolidLinesLayer.strokeColor = AppViewColorMake(209, 120, 0).cgColor
        linesContainerView.layer?.addSublayer(verSolidLinesLayer)

        updateColors()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func updateColors() {
        super.updateColors()
        let borderColor = AppViewClientIsDarkMode() ? AppViewColorMake(123, 123, 123) : AppViewColorMake(190, 190, 190)
        referImageViewBorderLayer.borderColor = borderColor.cgColor
        mainImageViewBorderLayer.borderColor = borderColor.cgColor
    }

    override func layout() {
        super.layout()
        mainImageView.frame = scaledMainFrame
        referImageView.frame = scaledReferFrame

        let unionSize = unionSize(of: scaledMainFrame, and: scaledReferFrame)
        let contentWidth = unionSize.width
        let contentHeight = unionSize.height
        lk(contentView).width(contentWidth).height(contentHeight).centerAlign()

        linesContainerView.frame = contentView.bounds
        horSolidLinesLayer.frame = linesContainerView.bounds
        verSolidLinesLayer.frame = linesContainerView.bounds
        mainImageViewBorderLayer.frame = mainImageView.frame
        referImageViewBorderLayer.frame = referImageView.frame
        renderLinesAndLabels()
    }

    func render(
        mainRect originalMainRect: CGRect,
        mainImage: AppViewImage?,
        referRect originalReferRect: CGRect,
        referImage: AppViewImage?
    ) {
        originalMainFrame = originalMainRect
        originalReferFrame = originalReferRect

        mainImageView.image = mainImage
        referImageView.image = referImage

        let scaleFactor = calculateScaleFactor(mainRect: originalMainRect, referRect: originalReferRect)

        let mainFrame = adjustRect(originalMainRect, scaleFactor: scaleFactor)
        let referFrame = adjustRect(originalReferRect, scaleFactor: scaleFactor)

        let unionOrigin = unionBounds(of: mainFrame, and: referFrame).origin

        scaledMainFrame = adjustRect(mainFrame, offsetX: unionOrigin.x, offsetY: unionOrigin.y)
        scaledReferFrame = adjustRect(referFrame, offsetX: unionOrigin.x, offsetY: unionOrigin.y)

        needsLayout = true
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        let minY = min(scaledMainFrame.minY, scaledReferFrame.minY)
        let maxY = max(scaledMainFrame.maxY, scaledReferFrame.maxY)
        let height = maxY - minY
        return NSSize(width: MeasureViewWidth, height: height + verInset * 2)
    }

    // MARK: - Lines and labels

    private func renderLinesAndLabels() {
        hideAllLabels()
        horSolidLinesLayer.isHidden = true
        verSolidLinesLayer.isHidden = true

        let rectA = scaledMainFrame
        let rectB = scaledReferFrame

        if rectA.contains(rectB) {
            mainImageView.alphaValue = 0.2
            referImageView.alphaValue = 1
        } else if rectB.contains(rectA) {
            mainImageView.alphaValue = 1
            referImageView.alphaValue = 0.2
        } else if rectA.intersects(rectB) {
            mainImageView.alphaValue = 0.2
            referImageView.alphaValue = 0.2
        } else {
            mainImageView.alphaValue = 1
            referImageView.alphaValue = 1
        }

        let minX_A = rectA.minX
        let midX_A = rectA.midX
        let maxX_A = rectA.maxX
        let minX_B = rectB.minX
        let midX_B = rectB.midX
        let maxX_B = rectB.maxX

        let minY_A = rectA.minY
        let midY_A = rectA.midY
        let maxY_A = rectA.maxY
        let minY_B = rectB.minY
        let midY_B = rectB.midY
        let maxY_B = rectB.maxY

        var horDatas: [AVMeasureResultHorLineData] = []

        if compare(minX_A, with: minX_B) == .smaller {
            if compare(maxX_A, with: minX_B) == .smaller {
                addHor(&horDatas, maxX_A, minX_B, midY_A, originalReferFrame.minX - originalMainFrame.maxX)
            } else {
                if compare(maxX_A, with: maxX_B) == .smaller {
                    addHor(&horDatas, maxX_A, maxX_B, midY_A, originalReferFrame.maxX - originalMainFrame.maxX)
                } else if compare(maxX_A, with: maxX_B) == .same {
                    // nothing
                } else if compare(maxX_A, with: maxX_B) == .bigger {
                    addHor(&horDatas, maxX_B, maxX_A, midY_B, originalMainFrame.maxX - originalReferFrame.maxX)
                    addHor(&horDatas, minX_A, minX_B, midY_B, originalReferFrame.minX - originalMainFrame.minX)
                } else {
                    assertionFailure()
                }
            }
        } else if compare(minX_A, with: minX_B) == .same {
            if compare(maxX_A, with: maxX_B) == .smaller {
                addHor(&horDatas, maxX_A, maxX_B, midY_A, originalReferFrame.maxX - originalMainFrame.maxX)
            } else if compare(maxX_A, with: maxX_B) == .same {
                // nothing
            } else if compare(maxX_A, with: maxX_B) == .bigger {
                addHor(&horDatas, maxX_B, maxX_A, midY_B, originalMainFrame.maxX - originalReferFrame.maxX)
            } else {
                assertionFailure()
            }
        } else if compare(minX_A, with: minX_B) == .bigger {
            if compare(minX_A, with: maxX_B) == .bigger {
                addHor(&horDatas, minX_A, maxX_B, midY_A, originalMainFrame.minX - originalReferFrame.maxX)
            } else {
                addHor(&horDatas, minX_B, minX_A, midY_A, originalMainFrame.minX - originalReferFrame.minX)
                if compare(maxX_A, with: maxX_B) == .smaller {
                    addHor(&horDatas, maxX_A, maxX_B, midY_A, originalReferFrame.maxX - originalMainFrame.maxX)
                }
            }
        } else {
            assertionFailure()
        }

        var verDatas: [AVMeasureResultVerLineData] = []

        if compare(minY_A, with: minY_B) == .smaller {
            if compare(maxY_A, with: minY_B) == .smaller {
                addVer(&verDatas, maxY_A, minY_B, midX_A, originalReferFrame.minY - originalMainFrame.maxY)
            } else {
                if compare(maxY_A, with: maxY_B) == .smaller {
                    addVer(&verDatas, maxY_A, maxY_B, midX_A, originalReferFrame.maxY - originalMainFrame.maxY)
                } else if compare(maxY_A, with: maxY_B) == .same {
                    // nothing
                } else if compare(maxY_A, with: maxY_B) == .bigger {
                    addVer(&verDatas, maxY_B, maxY_A, midX_B, originalMainFrame.maxY - originalReferFrame.maxY)
                    addVer(&verDatas, minY_A, minY_B, midX_B, originalReferFrame.minY - originalMainFrame.minY)
                } else {
                    assertionFailure()
                }
            }
        } else if compare(minY_A, with: minY_B) == .same {
            if compare(maxY_A, with: maxY_B) == .smaller {
                addVer(&verDatas, maxY_A, maxY_B, midX_A, originalReferFrame.maxY - originalMainFrame.maxY)
            } else if compare(maxY_A, with: maxY_B) == .same {
                // nothing
            } else if compare(maxY_A, with: maxY_B) == .bigger {
                addVer(&verDatas, maxY_B, maxY_A, midX_B, originalMainFrame.maxY - originalReferFrame.maxY)
            } else {
                assertionFailure()
            }
        } else if compare(minY_A, with: minY_B) == .bigger {
            if compare(minY_A, with: maxY_B) == .bigger {
                addVer(&verDatas, maxY_B, minY_A, midX_A, originalMainFrame.minY - originalReferFrame.maxY)
            } else {
                addVer(&verDatas, minY_B, minY_A, midX_A, originalMainFrame.minY - originalReferFrame.minY)
                if compare(maxY_A, with: maxY_B) == .smaller {
                    addVer(&verDatas, maxY_A, maxY_B, midX_A, originalReferFrame.maxY - originalMainFrame.maxY)
                }
            }
        } else {
            assertionFailure()
        }

        let horPath = CGMutablePath()
        let verPath = CGMutablePath()
        let handlerLength: CGFloat = 3

        for data in horDatas {
            horPath.move(to: CGPoint(x: data.startX, y: data.y))
            horPath.addLine(to: CGPoint(x: data.endX, y: data.y))
            horPath.move(to: CGPoint(x: data.startX + 0.5, y: data.y - handlerLength))
            horPath.addLine(to: CGPoint(x: data.startX + 0.5, y: data.y + handlerLength))
            horPath.move(to: CGPoint(x: data.endX - 0.5, y: data.y - handlerLength))
            horPath.addLine(to: CGPoint(x: data.endX - 0.5, y: data.y + handlerLength))

            let labelView = dequeueAvailableTextField()
            labelView.backgroundColor = .systemBlue
            labelView.textField.stringValue = NSString.appview_string(from: Double(data.displayValue), decimal: 2)
            lk(labelView).sizeToFit().height(labelHeight).midX(data.startX + (data.endX - data.startX) / 2.0).maxY(data.y - 5)
        }

        for data in verDatas {
            verPath.move(to: CGPoint(x: data.x, y: data.startY))
            verPath.addLine(to: CGPoint(x: data.x, y: data.endY))
            verPath.move(to: CGPoint(x: data.x - handlerLength, y: data.startY + 0.5))
            verPath.addLine(to: CGPoint(x: data.x + handlerLength, y: data.startY + 0.5))
            verPath.move(to: CGPoint(x: data.x - handlerLength, y: data.endY - 0.5))
            verPath.addLine(to: CGPoint(x: data.x + handlerLength, y: data.endY - 0.5))

            let labelView = dequeueAvailableTextField()
            labelView.backgroundColor = AppViewColorRGBAMake(209, 120, 0, 1.0)
            labelView.textField.stringValue = NSString.appview_string(from: Double(data.displayValue), decimal: 2)
            lk(labelView).sizeToFit().height(labelHeight).midY(data.startY + (data.endY - data.startY) / 2.0).maxX(data.x - 5)
            if checkOverlap(ofTargetLabelView: labelView) {
                lk(labelView).x(data.x + 5)
                labelView.backgroundColor = AppViewColorRGBAMake(209, 120, 0, 0.5)
            }
        }

        horSolidLinesLayer.path = horPath
        horSolidLinesLayer.isHidden = false
        verSolidLinesLayer.path = verPath
        verSolidLinesLayer.isHidden = false
    }

    private func checkOverlap(ofTargetLabelView targetView: NSView) -> Bool {
        for otherView in textFieldViews {
            if otherView === targetView { continue }
            if !otherView.appview_isEffectivelyVisible { continue }
            let inter = otherView.frame.intersection(targetView.frame)
            if !inter.isNull, inter.width * inter.height > 100 {
                return true
            }
        }
        return false
    }

    // MARK: - Geometry helpers

    private func calculateScaleFactor(mainRect: CGRect, referRect: CGRect) -> CGFloat {
        let maxContentWidth = MeasureViewWidth - horInset * 2
        let windowHeight = window?.frame.size.height ?? 0
        let maxContentHeight = max((windowHeight - AVNavigationManager.sharedInstance.windowTitleBarHeight) * 0.8, 200)

        let contentSize = unionSize(of: mainRect, and: referRect)

        let scaleFactorX = contentSize.width / maxContentWidth
        let scaleFactorY = contentSize.height / maxContentHeight
        var scaleFactor = max(scaleFactorX, scaleFactorY)
        if scaleFactor <= 0 {
            scaleFactor = 1
            assertionFailure()
        }
        return scaleFactor
    }

    private func unionBounds(of rectA: CGRect, and rectB: CGRect) -> CGRect {
        rectA.union(rectB)
    }

    private func unionSize(of rectA: CGRect, and rectB: CGRect) -> CGSize {
        unionBounds(of: rectA, and: rectB).size
    }

    private func adjustRect(_ rect: CGRect, scaleFactor factor: CGFloat) -> CGRect {
        var result = rect
        var safeFactor = factor
        if safeFactor == 0 {
            assertionFailure()
            safeFactor = 1
        }
        result.origin.x /= safeFactor
        result.origin.y /= safeFactor
        result.size.width /= safeFactor
        result.size.height /= safeFactor
        return result
    }

    private func adjustRect(_ rect: CGRect, offsetX: CGFloat, offsetY: CGFloat) -> CGRect {
        var result = rect
        result.origin.x -= offsetX
        result.origin.y -= offsetY
        return result
    }

    private func hideAllLabels() {
        textFieldViews.forEach { $0.isHidden = true }
    }

    private func dequeueAvailableTextField() -> AVTextFieldView {
        if let resultView = textFieldViews.first(where: { $0.isHidden }) {
            resultView.isHidden = false
            return resultView
        }
        let resultView = AVTextFieldView.label()
        resultView.insets = NSEdgeInsets(top: 0, left: 3, bottom: 0, right: 3)
        resultView.textField.textColor = .white
        resultView.textField.font = NSFontMake(13)
        resultView.textField.alignment = .center
        resultView.layer?.cornerRadius = labelHeight / 2.0
        contentView.addSubview(resultView)
        textFieldViews.append(resultView)
        resultView.isHidden = false
        return resultView
    }

    private func compare(_ a: CGFloat, with b: CGFloat) -> CompareResult {
        if abs(a - b) < 0.00001 { return .same }
        if a > b { return .bigger }
        return .smaller
    }

    private func addHor(
        _ array: inout [AVMeasureResultHorLineData],
        _ startX: CGFloat,
        _ endX: CGFloat,
        _ y: CGFloat,
        _ value: CGFloat
    ) {
        array.append(AVMeasureResultHorLineData.data(startX: startX, endX: endX, y: y, value: value))
    }

    private func addVer(
        _ array: inout [AVMeasureResultVerLineData],
        _ startY: CGFloat,
        _ endY: CGFloat,
        _ x: CGFloat,
        _ value: CGFloat
    ) {
        array.append(AVMeasureResultVerLineData.data(startY: startY, endY: endY, x: x, value: value))
    }
}
