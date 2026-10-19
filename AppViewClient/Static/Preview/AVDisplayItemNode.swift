//
//  AVDisplayItemNode.swift
//  AppView
//

import AppKit
import AppViewShared
import RxSwift
import SceneKit

final class AVDisplayItemNode: SCNNode, AppViewDisplayItemDelegate {
    var screenSize: CGSize = .zero {
        didSet {
            guard screenSize != oldValue, let item = displayItem else { return }
            item.previewItemDelegate?.displayItem(item, propertyDidChange: .frameToRoot)
        }
    }
    weak var preferenceManager: AVPreferenceManager? {
        didSet {
            preferenceDisposeBag = DisposeBag()
            guard let preferenceManager else { return }
            Observable.merge(
                preferenceManager.showHiddenItemsObservable.map { _ in () },
                preferenceManager.isQuickSelectingObservable.map { _ in () }
            )
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, _ in
                owner.renderVisibility()
            }
            .disposed(by: preferenceDisposeBag)

            Observable.merge(
                preferenceManager.showOutlineObservable.map { _ in () },
                preferenceManager.previewDimensionObservable.map { _ in () }
            )
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, _ in
                owner.renderImageAndColor()
            }
            .disposed(by: preferenceDisposeBag)
        }
    }
    var displayItem: AppViewDisplayItem? {
        didSet {
            oldValue?.previewItemDelegate = nil
            contentPlane.firstMaterial?.diffuse.contents = displayItem?.backgroundColor ?? NSColor.clear
            displayItem?.previewItemDelegate = self
            // Swift AppViewDisplayItem.previewItemDelegate setter does not fire .none like ObjC does.
            // Call refreshPreviewAppearance() explicitly to match the ObjC initial render.
            refreshPreviewAppearance()
        }
    }

    var isDarkMode = false {
        didSet { renderImageAndColor() }
    }

    /// Subtracted from layout position so rotation pivots at the layers' bounding center (`AVPreviewView.rotationPivotNode`).
    var rotationPivotOffset: CGPoint = .zero

    /// When true, position in parent `AVDisplayItemNode` space; when false, use frame-to-root (ObjC flat layout).

    private let dataSource: AVHierarchyDataSource
    private var preferenceDisposeBag = DisposeBag()
    private let contentNode = SCNNode()
    private let contentPlane = SCNPlane()
    private var borderGeometry: SCNGeometry?
    private let borderNode = SCNNode()
    private var borderColor: NSColor? {
        didSet { renderBorderColor() }
    }
    private let maskNode = SCNNode()
    private let maskPlane = SCNPlane()

    init(dataSource: AVHierarchyDataSource) {
        self.dataSource = dataSource
        super.init()

        contentPlane.firstMaterial?.isDoubleSided = true
        contentPlane.firstMaterial?.lightingModel = .constant
        contentNode.geometry = contentPlane
        contentPlane.firstMaterial?.diffuse.contents = NSColor.clear
        contentNode.position = SCNVector3(0, 0, 0)
        contentNode.name = "screenshot"
        contentNode.categoryBitMask = Int(AppViewPreviewBitMask.noLight.rawValue)
        addChildNode(contentNode)

        maskPlane.firstMaterial?.isDoubleSided = true
        maskPlane.firstMaterial?.lightingModel = .constant
        maskNode.geometry = maskPlane
        maskNode.name = "mask"
        maskNode.position = SCNVector3(0, 0, 0.001)
        maskNode.categoryBitMask = Int(AppViewPreviewBitMask.noLight.rawValue)

        borderNode.name = "border"
        borderNode.position = SCNVector3(0, 0, 0.002)
        borderNode.categoryBitMask = Int(AppViewPreviewBitMask.noLight.rawValue)
        addChildNode(borderNode)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var index: UInt = 0 {
        didSet {
            let order = Int(index) * 10
            contentNode.renderingOrder = order
            maskNode.renderingOrder = order + 1
            borderNode.renderingOrder = order + 2
        }
    }

    private func renderBorderColor() {
        borderGeometry?.firstMaterial?.diffuse.contents = borderColor
    }

    private func renderVisibility() {
        guard let displayItem, let preferenceManager else { return }

        let displayingInHierarchy = displayItem.displayingInHierarchy
        let inHiddenHierarchy = displayItem.inHiddenHierarchy
        let showEvenWhenCollapsed = preferenceManager.isQuickSelecting
            && displayItem.superItem?.preferToBeCollapsed == false
        let showHiddenItems = preferenceManager.showHiddenItems

        var canSelect = false
        if inHiddenHierarchy, !showHiddenItems {
            contentNode.opacity = 0
            borderNode.opacity = 0
            maskNode.isHidden = true
        } else if displayingInHierarchy {
            contentNode.opacity = 1
            borderNode.opacity = 1
            maskNode.isHidden = false
            canSelect = true
        } else {
            contentNode.opacity = 0
            maskNode.isHidden = true
            if showEvenWhenCollapsed {
                borderNode.opacity = 1
                canSelect = true
            } else {
                borderNode.opacity = 0
            }
        }

        if canSelect {
            contentNode.categoryBitMask = Int(AppViewPreviewBitMask.selectable.rawValue)
                | Int(AppViewPreviewBitMask.noLight.rawValue)
        } else {
            contentNode.categoryBitMask = Int(AppViewPreviewBitMask.unselectable.rawValue)
                | Int(AppViewPreviewBitMask.noLight.rawValue)
        }
    }

  /// In 3D, parent `solo`/`group` often bakes in descendants. Fast Mode OFF loads parent + every child,
  /// which stacks duplicates. Show leaf `group` only; hide parent texture when children are visible.
    private func imageForPreviewPlane() -> NSImage? {
        guard let displayItem else { return nil }
        let is3D = preferenceManager?.previewDimension
            == Int(AppViewPreviewDimension.dimension3D.rawValue)
        if is3D {
            if !displayItem.displayingInHierarchy {
                return nil
            }
            // Fast Mode OFF streams hundreds of chunks; defer only when real children would duplicate.
            if isDeferringExpandableTexturesDuringBatchSync(),
               displayItem.isExpandable,
               hasVisibleChildInHierarchy(displayItem) {
                return nil
            }
            return expandableScreenshotForPreviewPlane()
        }
        if displayItem.isExpandable, displayItem.isExpanded,
           !hasVisibleChildInHierarchy(displayItem) {
            return displayItem.soloScreenshot ?? displayItem.groupScreenshot
        }
        return displayItem.appropriateScreenshot()
    }

    /// Screenshot for an expandable node on the 3D preview plane (CustomCatView / CustomHorseLayer included).
    private func expandableScreenshotForPreviewPlane() -> NSImage? {
        guard let displayItem else { return nil }
        if displayItem.isExpandable {
            if displayItem.isExpanded, hasVisibleChildInHierarchy(displayItem) {
                return nil
            }
            if displayItem.isExpanded {
                return displayItem.soloScreenshot ?? displayItem.groupScreenshot
            }
            return displayItem.groupScreenshot
        }
        return displayItem.groupScreenshot
    }

    /// ObjC baseline never sets plane `contents` to nil — use clear/backgroundColor fallback.
    private func contentsForPreviewPlane() -> Any {
        guard let displayItem else { return NSColor.clear }
        if let image = imageForPreviewPlane() {
            if let rep = image.representations.first {
                assert(
                    max(rep.pixelsWide, rep.pixelsHigh) <= Int(appviewNodeImageMaxLengthInPx),
                    "image is too large"
                )
            }
            return image
        }
        if let backgroundColor = displayItem.backgroundColor as NSColor? {
            return backgroundColor
        }
        return NSColor.clear
    }

    private func isDeferringExpandableTexturesDuringBatchSync() -> Bool {
        AVStaticAsyncUpdateManager.sharedInstance.isUpdating
            && AVPreferenceMain().fastMode == false
    }

    /// Only real layer/view children suppress the parent texture in 3D.
    /// Virtual nodes from `appview_customDebugInfos` (`isUserCustom`) have no screenshot plane.
    private func hasVisibleChildInHierarchy(_ item: AppViewDisplayItem) -> Bool {
        guard let subitems = item.subitems, !subitems.isEmpty else { return false }
        for child in subitems {
            if child.isUserCustom() { continue }
            if child.inNoPreviewHierarchy { continue }
            if child.displayingInHierarchy { return true }
        }
        return false
    }

    func refreshPreviewAppearance() {
        renderImageAndColor()
        renderVisibility()
    }

    /// Texture kind shown on the preview plane (matches ObjC: appropriateScreenshot, not suppression logic).
    func mcpTextureKind() -> String {
        guard let displayItem else { return "none" }
        guard displayItem.appropriateScreenshot() != nil else {
            return displayItem.backgroundColor != nil ? "background" : "none"
        }
        if displayItem.isExpandable, displayItem.isExpanded {
            return "solo"
        }
        return "group"
    }

    func mcpContentOpacity() -> CGFloat {
        contentNode.opacity
    }

    /// Image shown on the preview plane (matches ObjC appropriateScreenshot behavior).
    func mcpPreviewScreenshotImage() -> NSImage? {
        displayItem?.appropriateScreenshot()
    }

    private func renderImageAndColor() {
        guard let displayItem else { return }

        let isSelected = dataSource.selectedItem === displayItem
        let isHovered = dataSource.hoveredItem === displayItem

        let appropriateScreenshot = displayItem.appropriateScreenshot()
        contentPlane.firstMaterial?.diffuse.contents = contentsForPreviewPlane()

        let tooLargeToFetchScreenshot = appropriateScreenshot == nil
            && displayItem.doNotFetchScreenshotReason == .tooLarge

        if isSelected || isHovered {
            if tooLargeToFetchScreenshot {
                borderColor = AppViewColorRGBAMake(255, 38, 0, 0.8)
            } else {
                borderColor = AppViewColorMake(100, 146, 199)
            }
        } else if preferenceManager?.showOutline == true {
            if tooLargeToFetchScreenshot {
                borderColor = isDarkMode
                    ? AppViewColorRGBAMake(255, 38, 0, 0.5)
                    : AppViewColorRGBAMake(255, 38, 0, 0.6)
            } else {
                borderColor = isDarkMode
                    ? AppViewColorRGBAMake(160, 168, 189, 0.6)
                    : AppViewColorRGBAMake(120, 122, 124, 0.6)
            }
        } else {
            borderColor = .clear
        }

        var maskColor: NSColor?
        var maskOpacity: CGFloat = 0
        if tooLargeToFetchScreenshot {
            maskColor = AppViewColorMake(255, 38, 0)
            if isSelected {
                maskOpacity = 0.45
            } else if isHovered {
                maskOpacity = 0.3
            } else {
                maskOpacity = AppViewClientIsDarkMode() ? 0.17 : 0.2
            }
        } else {
            maskColor = AppViewColorMake(110, 183, 255)
            var level = AVPreferenceMain().imageContrastLevel
            if level < 0 || level > 2 {
                assertionFailure()
                level = 0
            }
            let opacitiesSelected: [CGFloat] = [0.35, 0.6, 0.85]
            let opacitiesHovered: [CGFloat] = [0.18, 0.38, 0.6]
            if isSelected {
                maskOpacity = opacitiesSelected[level]
            } else if isHovered {
                maskOpacity = opacitiesHovered[level]
            }
        }

        if maskOpacity > 0, maskNode.parent == nil {
            insertChildNode(maskNode, at: 1)
        }
        maskNode.opacity = maskOpacity
        maskPlane.firstMaterial?.diffuse.contents = maskColor
    }

    func displayItem(_ displayItem: AppViewDisplayItem, propertyDidChange property: AppViewDisplayItemProperty) {
        if property == .none || property == .frameToRoot {
            let frame = displayItem.frame
            let width = frame.size.width
            let height = frame.size.height
            let factor: CGFloat = 0.01

            contentPlane.width = CGFloat(width) * factor
            contentPlane.height = CGFloat(height) * factor
            maskPlane.width = contentPlane.width
            maskPlane.height = contentPlane.height

            var position = self.position
            let frameToRoot = displayItem.calculateFrameToRoot()
            let xOffSet = -screenSize.width / 2
            let yOffSet = screenSize.height / 2
            let transformedX = frameToRoot.origin.x + frameToRoot.width / 2 + xOffSet
            let transformedY = -(frameToRoot.origin.y + frameToRoot.height / 2) + yOffSet
            position.x = CGFloat(Float(transformedX * factor)) - rotationPivotOffset.x
            position.y = CGFloat(Float(transformedY * factor)) - rotationPivotOffset.y
            self.position = position

            borderGeometry = makeBorderGeometry(with: contentNode)
            borderNode.geometry = borderGeometry
            renderBorderColor()
        }

        switch property {
        case .none, .isExpandable, .isExpanded, .soloScreenshot, .groupScreenshot,
             .isSelected, .isHovered, .avoidSyncScreenshot:
            renderImageAndColor()
        default:
            break
        }

        if property == .none || property == .displayingInHierarchy || property == .inHiddenHierarchy {
            renderVisibility()
        }
    }

    private func makeBorderGeometry(with planeNode: SCNNode) -> SCNGeometry {
        var min = SCNVector3Zero
        var max = SCNVector3Zero
        let bbox = planeNode.boundingBox
        min = bbox.min
        max = bbox.max
        let xx = max.x - min.x
        let yy = max.y - min.y
        let vec: [SCNVector3] = [
            max,
            SCNVector3(max.x, max.y - yy, max.z),
            SCNVector3(max.x - xx, max.y - yy, max.z),
            SCNVector3(max.x - xx, max.y, max.z),
        ]
        let indexs: [UInt8] = [0, 1, 1, 2, 2, 3, 3, 0]
        let vecSource = SCNGeometrySource(vertices: vec)
        let indexData = Data(indexs)
        let indexElement = SCNGeometryElement(
            data: indexData,
            primitiveType: .line,
            primitiveCount: 4,
            bytesPerIndex: MemoryLayout<UInt8>.size
        )
        let geometry = SCNGeometry(sources: [vecSource], elements: [indexElement])
        geometry.firstMaterial?.isDoubleSided = true
        geometry.firstMaterial?.lightingModel = .constant
        return geometry
    }
}
