//
//  AVPreviewView.swift
//  AppView
//

import AppKit
import AppViewShared
import Metal
import QuartzCore
import SceneKit

enum AppViewPreviewDimension: UInt {
    case dimension2D = 0
    case dimension3D = 1
}

final class AVPreviewView: SCNView {
static weak var sharedForMCP: AVPreviewView?

    private let dataSource: AVHierarchyDataSource

    private let stageNode = SCNNode()
    /// Pan / layout compensation; rotation is on `rotationPivotNode` at the layers' bounding center.
    private let rotationPivotNode = SCNNode()
    private let cameraNode = SCNNode()
    private let rightLightNode = SCNNode()
    private let leftLightNode = SCNNode()

    private var flatDisplayItems: [AppViewDisplayItem] = []
    private var displayItemNodes: NSMutableArray = []

    /// Points → scene units (same scale as `AVDisplayItemNode` layout).
    private static let sceneUnitScale: CGFloat = 0.01

private(set) var rotation: CGPoint = .zero

    /// Extra preview frame height above the container (`titleBarHeight` in `AVPreviewController`); used to re-center content in the visible area.
var layoutTopExtraHeight: CGFloat = 0 {
        didSet { applyStageTranslation() }
    }

    /// Extra preview width extending left of the visible panel (`AVPreviewController`); re-centers layers in the area not covered by the dashboard.
var layoutLeadingExtraWidth: CGFloat = 0 {
        didSet { applyStageTranslation() }
    }

var translation: CGPoint = .zero {
        didSet { applyStageTranslation() }
    }

    private func applyStageTranslation() {
        let layoutX = layoutLeadingExtraWidth * Self.sceneUnitScale * 0.5
        let layoutY = layoutTopExtraHeight * Self.sceneUnitScale * 0.5
            - AVPreviewContentVerticalNudge * Self.sceneUnitScale
        let p = stageNode.position
        stageNode.position = SCNVector3(x: translation.x + layoutX, y: translation.y + layoutY, z: p.z)
    }

var scale: CGFloat = 0 {
        didSet {
            cameraNode.camera?.focalLength = 20 + scale * scale * 730
        }
    }

var zInterspace: CGFloat = 0 {
        didSet {
            _zInterspace = min(max(zInterspace, AppViewPreviewMinZInterspace), AppViewPreviewMaxZInterspace)
            updateZPositionByZIndex()
        }
    }
    private var _zInterspace: CGFloat = 0

private(set) var dimension: AppViewPreviewDimension = .dimension3D

var appScreenSize: CGSize = .zero {
        didSet {
            guard appScreenSize != oldValue else { return }
            let rp = rightLightNode.position
            let rightX = appScreenSize.width * 0.01 * 0.5 + 2
            let rightY = appScreenSize.height * 0.01 * 0.5 + 2
            rightLightNode.position = SCNVector3(x: rightX, y: rightY, z: rp.z)

            let lp = leftLightNode.position
            let leftX = -appScreenSize.width * 0.01 * 0.5 - 2
            let leftY = -appScreenSize.height * 0.01 * 0.5 - 2
            leftLightNode.position = SCNVector3(x: leftX, y: leftY, z: lp.z)

            for case let node as AVDisplayItemNode in displayItemNodes {
                node.screenSize = appScreenSize
            }
            updateRotationPivotCenter()
        }
    }

var preferenceManager: AVPreferenceManager?
var isDarkMode = false {
        didSet {
            backgroundColor = isDarkMode ? AppViewColorMake(19, 20, 21) : AppViewColorMake(249, 249, 249)
            for case let node as AVDisplayItemNode in displayItemNodes {
                node.isDarkMode = isDarkMode
            }
        }
    }

var showHiddenItems = false

    init(dataSource: AVHierarchyDataSource) {
        self.dataSource = dataSource
        super.init(frame: .zero, options: nil)
        AVPreviewView.sharedForMCP = self

        allowsCameraControl = false
        showsStatistics = false
        scene = SCNScene()

        stageNode.name = "stage"
        scene?.rootNode.addChildNode(stageNode)

        rotationPivotNode.name = "rotationPivot"
        stageNode.addChildNode(rotationPivotNode)

        cameraNode.name = "camera"
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true
        cameraNode.position = SCNVector3(0, 0, 34)
        scene?.rootNode.addChildNode(cameraNode)

        let rightLight = SCNLight()
        rightLight.type = .omni
                rightLight.categoryBitMask = Int(AppViewPreviewBitMask.hasLight.rawValue)
        rightLightNode.name = "right light"
        rightLightNode.light = rightLight
        scene?.rootNode.addChildNode(rightLightNode)

        // ObjC baseline reuses the omni `rightLight` on the left node (bug in AVPreviewView.m:75
        // that the QMUI baseline ships with). Mirroring it here for strict visual parity.
        leftLightNode.name = "left light"
        leftLightNode.light = rightLight
        scene?.rootNode.addChildNode(leftLightNode)

        pointOfView = cameraNode
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(with items: [AppViewDisplayItem], discardCache: Bool) {
        let nodesBefore = displayItemNodes.count
        let stageBefore = stageNode.childNodes.count
        NSLog("AVPreviewView - render items=%d discardCache=%@ nodes_before=%d stage_before=%d",
              items.count, discardCache ? "Y" : "N", nodesBefore, stageBefore)
        flatDisplayItems = items

        if discardCache {
            for case let node as AVDisplayItemNode in displayItemNodes {
                node.displayItem = nil
                node.removeFromParentNode()
            }
            displayItemNodes.removeAllObjects()
        }

        let nodesToBeDiscarded = NSMutableArray()

        displayItemNodes.appview_dequeue(
            withCount: items.count,
            add: { [self] _ in
                let newNode = AVDisplayItemNode(dataSource: dataSource)
                newNode.screenSize = appScreenSize
                newNode.preferenceManager = preferenceManager
                newNode.isDarkMode = isDarkMode
                return newNode
            },
            notDequeued: { _, node in
                (node as? AVDisplayItemNode)?.removeFromParentNode()
                nodesToBeDiscarded.add(node)
            },
            doNext: { [self] idx, node in
                guard let node = node as? AVDisplayItemNode else { return }
                let displayItem = items[Int(idx)]
                attachPreviewNode(node, to: displayItem)
                displayItem.previewNode = node
                node.index = UInt(idx)
                node.displayItem = displayItem
            }
        )

        if nodesToBeDiscarded.count > 0 {
            displayItemNodes.removeObjects(in: nodesToBeDiscarded as! [Any])
        }

        pruneOrphanPreviewNodes()

        updateZPosition()
        let nodesAfter = displayItemNodes.count
        let stageAfter = stageNode.childNodes.count
        NSLog("AVPreviewView - render done nodes=%d stage=%d", nodesAfter, stageAfter)
        AVDebugEventLog.shared.record("render", [
            "items": items.count,
            "discardCache": discardCache,
            "nodes_before": nodesBefore,
            "stage_before": stageBefore,
            "nodes_after": nodesAfter,
            "stage_after": stageAfter,
        ])
    }

    private func attachPreviewNode(_ node: AVDisplayItemNode, to item: AppViewDisplayItem) {
        _ = item
        if node.parent !== rotationPivotNode {
            node.removeFromParentNode()
            rotationPivotNode.addChildNode(node)
        }
    }

    private func pruneOrphanPreviewNodes() {
        let liveNodes = Set(displayItemNodes.compactMap { $0 as? AVDisplayItemNode })

        func prune(under parent: SCNNode) {
            for child in parent.childNodes {
                guard let node = child as? AVDisplayItemNode else { continue }
                if liveNodes.contains(node) {
                    prune(under: node)
                } else {
                    node.displayItem = nil
                    node.removeFromParentNode()
                }
            }
        }
        prune(under: rotationPivotNode)

        let rootedCount = countDisplayItemNodes(under: rotationPivotNode)
        if rootedCount != displayItemNodes.count {
            NSLog(
                "AVPreviewView - tree/displayItemNodes mismatch tree=%d nodes=%d — pruned orphans",
                rootedCount,
                displayItemNodes.count
            )
        }
    }

    private func countDisplayItemNodes(under parent: SCNNode) -> Int {
        var count = 0
        for child in parent.childNodes {
            if child is AVDisplayItemNode {
                count += 1
                count += countDisplayItemNodes(under: child)
            }
        }
        return count
    }

func mcpDebugInfo() -> [AnyHashable: Any] {
        [
            "displayItemNodesCount": displayItemNodes.count,
            "stageNodeChildrenCount": stageNode.childNodes.count,
            "treeDisplayItemNodesCount": countDisplayItemNodes(under: stageNode),
            "flatDisplayItemsCount": flatDisplayItems.count,
            "sceneLayout": "flat",
        ]
    }

    /// Wire oid from iOS (0 when layer/view has no registry oid).
static func mcpWireOid(for item: AppViewDisplayItem) -> UInt {
        item.viewObject?.oid ?? item.layerObject?.oid ?? 0
    }

  /// Stable tree id: wire oid, or synthetic `0xF0000000 + flatIndex` for layers without oid.
static let mcpSyntheticOidBase: UInt = 0xF0_00_0000

    private func mcpFlatIndex(for item: AppViewDisplayItem) -> Int {
        flatDisplayItems.firstIndex { $0 === item } ?? -1
    }

func mcpStructureOid(for item: AppViewDisplayItem) -> UInt {
        let wire = Self.mcpWireOid(for: item)
        if wire > 0 { return wire }
        let flatIdx = mcpFlatIndex(for: item)
        if flatIdx >= 0 {
            return Self.mcpSyntheticOidBase + UInt(flatIdx)
        }
        return Self.mcpSyntheticOidBase + UInt(displayItemNodes.count) + 1
    }

static func mcpOid(for item: AppViewDisplayItem) -> UInt {
        mcpWireOid(for: item)
    }

    private func mcpStructureFields(
        for item: AppViewDisplayItem,
        node: AVDisplayItemNode
    ) -> (plane: [String: Any], structure: [String: Any]) {
        let structureOid = mcpStructureOid(for: item)
        let wireOid = Self.mcpWireOid(for: item)
        let superStructureOid: UInt
        if let superItem = item.superItem {
            superStructureOid = mcpStructureOid(for: superItem)
        } else {
            superStructureOid = 0
        }

        var plane: [String: Any] = [
            "oid": structureOid,
            "wireOid": wireOid,
            "title": item.title() ?? "",
            "subtitle": item.subtitle() ?? "",
            "displayingInHierarchy": item.displayingInHierarchy,
            "indentLevel": item.indentLevel(),
            "previewZIndex": item.previewZIndex,
            "textureKind": node.mcpTextureKind(),
            "backgroundColorRGBA": AVMCPInspectorParity.rgbaArray(from: item.backgroundColor),
            "opacity": node.mcpContentOpacity(),
            "position": [
                "x": node.position.x,
                "y": node.position.y,
                "z": node.position.z,
            ],
            "hasSoloScreenshot": item.soloScreenshot != nil,
            "hasGroupScreenshot": item.groupScreenshot != nil,
            "flatIndex": mcpFlatIndex(for: item),
        ]
        plane["superOid"] = superStructureOid
        if let parentNode = node.parent as? AVDisplayItemNode,
           let parentItem = parentNode.displayItem {
            plane["scnParentOid"] = mcpStructureOid(for: parentItem)
        } else {
            plane["scnParentOid"] = 0
        }

        let frameToRoot = item.calculateFrameToRoot()
        var structEntry: [String: Any] = [
            "oid": structureOid,
            "wireOid": wireOid,
            "superOid": superStructureOid,
            "displayingInHierarchy": item.displayingInHierarchy,
            "indentLevel": item.indentLevel(),
            "previewZIndex": item.previewZIndex,
            "textureKind": node.mcpTextureKind(),
            "flatIndex": mcpFlatIndex(for: item),
            "positionRoot": [
                "x": frameToRoot.origin.x,
                "y": frameToRoot.origin.y,
                "width": frameToRoot.width,
                "height": frameToRoot.height,
            ],
        ]
        if wireOid == 0 {
            structEntry["title"] = item.title() ?? ""
            structEntry["subtitle"] = item.subtitle() ?? ""
            structEntry["isCustom"] = item.isUserCustom()
        }
        return (plane, structEntry)
    }

func mcpPreviewStateDictionary() -> [String: Any] {
        var planes: [[String: Any]] = []
        var structure: [[String: Any]] = []
        var seenStructureOids = Set<UInt>()

        for case let node as AVDisplayItemNode in displayItemNodes {
            guard let item = node.displayItem else { continue }
            let fields = mcpStructureFields(for: item, node: node)
            planes.append(fields.plane)

            let structureOid = fields.structure["oid"] as? UInt ?? 0
            if seenStructureOids.insert(structureOid).inserted {
                structure.append(fields.structure)
            }
        }
        planes.sort { ($0["oid"] as? UInt ?? 0) < ($1["oid"] as? UInt ?? 0) }
        structure.sort { ($0["oid"] as? UInt ?? 0) < ($1["oid"] as? UInt ?? 0) }

        return [
            "sceneLayout": "flat",
            "structure": structure,
            "dimension": dimension.rawValue,
            "rotationX": rotation.x,
            "rotationY": rotation.y,
            "translationX": translation.x,
            "translationY": translation.y,
            "scale": scale,
            "zInterspace": zInterspace,
            "displayItemNodesCount": displayItemNodes.count,
            "treeDisplayItemNodesCount": countDisplayItemNodes(under: stageNode),
            "flatDisplayItemsCount": flatDisplayItems.count,
            "planes": planes,
        ]
    }

func appviewUITestVisibleHiddenPreviewTitles() -> [String] {
        guard showHiddenItems else { return [] }
        var titles: [String] = []
        for case let node as AVDisplayItemNode in displayItemNodes {
            guard let item = node.displayItem, item.inHiddenHierarchy else { continue }
            guard let title = item.title()?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                continue
            }
            titles.append(title)
        }
        return titles.sorted()
    }

func mcpLightingInfo() -> [String: Any] {
        func describe(_ node: SCNNode, role: String) -> [String: Any] {
            let light = node.light
            let typeString: String = light?.type.rawValue ?? "none"
            return [
                "role": role,
                "name": node.name ?? "",
                "position": ["x": node.position.x, "y": node.position.y, "z": node.position.z],
                "lightType": typeString,
                "lightCategoryBitMask": light?.categoryBitMask ?? 0,
                "lightObjectIdentifier": light.map { ObjectIdentifier($0).hashValue } ?? 0,
            ]
        }
        let rightDesc = describe(rightLightNode, role: "right")
        let leftDesc = describe(leftLightNode, role: "left")
        let sharesLight = (rightLightNode.light != nil) && (rightLightNode.light === leftLightNode.light)
        return [
            "right": rightDesc,
            "left": leftDesc,
            "sharesLightObject": sharesLight,
            "appScreenSize": ["width": appScreenSize.width, "height": appScreenSize.height],
        ]
    }

func mcpSceneGraphDump() -> [String: Any] {
        func dump(_ node: SCNNode) -> [String: Any] {
            var entry: [String: Any] = [
                "name": node.name ?? "",
                "class": String(describing: type(of: node)),
                "position": ["x": node.position.x, "y": node.position.y, "z": node.position.z],
                "opacity": node.opacity,
                "isHidden": node.isHidden,
                "categoryBitMask": node.categoryBitMask,
                "renderingOrder": node.renderingOrder,
                "childCount": node.childNodes.count,
            ]
            if let geometry = node.geometry {
                entry["geometryClass"] = String(describing: type(of: geometry))
                if let plane = geometry as? SCNPlane {
                    entry["planeSize"] = ["width": plane.width, "height": plane.height]
                }
            }
            if let itemNode = node as? AVDisplayItemNode, let item = itemNode.displayItem {
                entry["displayItemOid"] = Self.mcpWireOid(for: item)
                entry["displayItemTitle"] = item.title() ?? ""
                entry["displayItemDisplayingInHierarchy"] = item.displayingInHierarchy
            }
            entry["children"] = node.childNodes.map { dump($0) }
            return entry
        }
        guard let root = scene?.rootNode else { return [:] }
        return [
            "sceneLayout": "flat",
            "rootChildCount": root.childNodes.count,
            "displayItemNodesCount": displayItemNodes.count,
            "stageNodeChildrenCount": stageNode.childNodes.count,
            "tree": dump(root),
        ]
    }

func mcpTextureSourcesInfo() -> [String: Any] {
        var entries: [[String: Any]] = []
        for case let node as AVDisplayItemNode in displayItemNodes {
            guard let item = node.displayItem else { continue }
            let appropriate = item.appropriateScreenshot()
            let actual = node.mcpPreviewScreenshotImage()
            func sizeDict(_ image: NSImage?) -> [String: Any] {
                guard let image else { return ["present": false] }
                let rep = image.representations.first
                return [
                    "present": true,
                    "pointsWidth": image.size.width,
                    "pointsHeight": image.size.height,
                    "pixelsWide": rep?.pixelsWide ?? 0,
                    "pixelsHigh": rep?.pixelsHigh ?? 0,
                ]
            }
            let appropriateRef = appropriate.map { ObjectIdentifier($0).hashValue } ?? 0
            let actualRef = actual.map { ObjectIdentifier($0).hashValue } ?? 0
            let entry: [String: Any] = [
                "structureOid": mcpStructureOid(for: item),
                "wireOid": Self.mcpWireOid(for: item),
                "title": item.title() ?? "",
                "subtitle": item.subtitle() ?? "",
                "specialTrace": (item.viewObject ?? item.layerObject)?.specialTrace ?? "",
                "ivarNames": AVMCPInspectorParity.ivarNames(from: item.viewObject ?? item.layerObject),
                "isExpandable": item.isExpandable,
                "isExpanded": item.isExpanded,
                "displayingInHierarchy": item.displayingInHierarchy,
                "backgroundColorRGBA": AVMCPInspectorParity.rgbaArray(from: item.backgroundColor),
                "appropriateScreenshot": sizeDict(appropriate),
                "actualPreviewImage": sizeDict(actual),
                "matchesAppropriate": appropriateRef != 0 && appropriateRef == actualRef,
                "suppressedByPreviewLogic": appropriate != nil && actual == nil,
                "textureKind": node.mcpTextureKind(),
            ]
            entries.append(entry)
        }
        entries.sort { ($0["structureOid"] as? UInt ?? 0) < ($1["structureOid"] as? UInt ?? 0) }
        let suppressed = entries.filter { ($0["suppressedByPreviewLogic"] as? Bool) == true }.count
        return [
            "sceneLayout": "flat",
            "dimension": dimension.rawValue,
            "itemsCount": entries.count,
            "suppressedCount": suppressed,
            "items": entries,
        ]
    }

func mcpSnapshotPNGData() -> Data? {
        guard let scene, let device = MTLCreateSystemDefaultDevice() else { return nil }
        let fixedSize = CGSize(width: 640, height: 480)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
        let shot = renderer.snapshot(atTime: 0, with: fixedSize, antialiasingMode: .none)
        guard let tiff = shot.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }

    func mcpExportLayerScreenshots(toDirectory directory: String) -> [String: Any] {
        let dirURL = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath, isDirectory: true)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: dirURL.path, isDirectory: &isDir), !isDir.boolValue {
            return ["error": "Path exists and is not a directory", "directory": dirURL.path]
        }
        do {
            try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        } catch {
            return ["error": error.localizedDescription, "directory": dirURL.path]
        }

        var exported: [[String: Any]] = []
        var skipped: [[String: Any]] = []
        var seenStructureOids = Set<UInt>()

        for case let node as AVDisplayItemNode in displayItemNodes {
            guard let item = node.displayItem else { continue }
            let structureOid = mcpStructureOid(for: item)
            guard seenStructureOids.insert(structureOid).inserted else { continue }

            let wireOid = Self.mcpWireOid(for: item)
            let textureKind = node.mcpTextureKind()
            var entry: [String: Any] = [
                "structureOid": structureOid,
                "wireOid": wireOid,
                "textureKind": textureKind,
                "title": item.title() ?? "",
            ]

            if let solo = item.soloScreenshot, let png = Self.pngData(from: solo) {
                let soloName = "layer-\(structureOid)-solo.png"
                try? png.write(to: dirURL.appendingPathComponent(soloName))
                entry["soloFile"] = soloName
            }
            if let group = item.groupScreenshot, let png = Self.pngData(from: group) {
                let groupName = "layer-\(structureOid)-group.png"
                try? png.write(to: dirURL.appendingPathComponent(groupName))
                entry["groupFile"] = groupName
            }

            if let image = node.mcpPreviewScreenshotImage(),
               let png = Self.pngData(from: image) {
                let filename = "layer-\(structureOid)-\(textureKind).png"
                do {
                    try png.write(to: dirURL.appendingPathComponent(filename))
                    entry["file"] = filename
                    entry["width"] = image.size.width
                    entry["height"] = image.size.height
                    exported.append(entry)
                } catch {
                    entry["error"] = error.localizedDescription
                    skipped.append(entry)
                }
            } else if entry["soloFile"] != nil || entry["groupFile"] != nil {
                exported.append(entry)
            } else {
                entry["reason"] = "no preview image"
                skipped.append(entry)
            }
        }

        let state = mcpPreviewStateDictionary()
        let structureURL = dirURL.appendingPathComponent("structure.json")
        let manifestURL = dirURL.appendingPathComponent("manifest.json")
        if let structureData = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? structureData.write(to: structureURL)
        }
        let manifest: [String: Any] = [
            "directory": dirURL.path,
            "exportedCount": exported.count,
            "skippedCount": skipped.count,
            "exported": exported,
            "skipped": skipped,
        ]
        if let manifestData = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) {
            try? manifestData.write(to: manifestURL)
        }

        return [
            "directory": dirURL.path,
            "exportedCount": exported.count,
            "skippedCount": skipped.count,
            "exported": exported,
            "skipped": skipped,
            "structureFile": "structure.json",
            "manifestFile": "manifest.json",
        ]
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }

    func updateZPosition() {
        for obj in flatDisplayItems {
            updateZIndex(for: obj)
        }
        updateZPositionByZIndex()
        updateRotationPivotCenter()
        AppViewUITestSupport.publishPreviewStructureIfNeeded()
    }

    func displayItem(at point: CGPoint) -> AppViewDisplayItem? {
        let hitResults = hitTest(
            point,
            options: [
                SCNHitTestOption.categoryBitMask: NSNumber(value: AppViewPreviewBitMask.selectable.rawValue),
                SCNHitTestOption.searchMode: NSNumber(value: SCNHitTestSearchMode.closest.rawValue),
                SCNHitTestOption.ignoreHiddenNodes: false,
            ]
        )
        guard let result = hitResults.first else { return nil }
        var node: SCNNode? = result.node
        while let current = node {
            if let itemNode = current as? AVDisplayItemNode {
                return itemNode.displayItem
            }
            node = current.parent
        }
        return nil
    }

    func didSelectItem(_ item: AppViewDisplayItem?) {
        guard let item, let displayItemNode = item.previewNode as? AVDisplayItemNode else { return }

        var rightPos = rightLightNode.position
        rightPos.z = displayItemNode.position.z + 2
        rightLightNode.position = rightPos

        var leftPos = leftLightNode.position
        leftPos.z = displayItemNode.position.z + 2
        leftLightNode.position = leftPos
    }

    func setRotation(_ rotation: CGPoint, animated: Bool) {
        setRotation(rotation, animated: animated, timingFunction: nil, duration: 0)
    }

    func setRotation(
        _ rotation: CGPoint,
        animated: Bool,
        timingFunction function: CAMediaTimingFunction?,
        duration: CGFloat
    ) {
        self.rotation = rotation
        let equivalentRotation = equivalentRotation(from: rotation)
        let angles = SCNVector3(Float(rotation.y), Float(rotation.x), 0)

        if animated {
            SCNTransaction.begin()
            if duration > 0 {
                SCNTransaction.animationDuration = duration
            }
            if let function {
                SCNTransaction.animationTimingFunction = function
            }
            SCNTransaction.completionBlock = { [weak self] in
                self?.rotation = equivalentRotation
            }
            rotationPivotNode.eulerAngles = angles
            SCNTransaction.commit()
        } else {
            rotationPivotNode.eulerAngles = angles
            self.rotation = equivalentRotation
        }
    }

    /// Center of all visible layer planes in layout space (screen-centered coordinates).
    private func rotationPivotCenterInLayoutSpace() -> CGPoint {
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        var hasBounds = false
        let factor = Self.sceneUnitScale

        for case let node as AVDisplayItemNode in displayItemNodes {
            guard let item = node.displayItem, item.displayingInHierarchy else { continue }
            let frame = item.calculateFrameToRoot()
            guard frame.width > 0, frame.height > 0 else { continue }
            let xOffSet = -appScreenSize.width / 2
            let yOffSet = appScreenSize.height / 2
            let left = (frame.origin.x + xOffSet) * factor
            let right = (frame.origin.x + frame.width + xOffSet) * factor
            let top = (-frame.origin.y + yOffSet) * factor
            let bottom = (-(frame.origin.y + frame.height) + yOffSet) * factor
            minX = min(minX, left)
            maxX = max(maxX, right)
            minY = min(minY, bottom)
            maxY = max(maxY, top)
            hasBounds = true
        }

        guard hasBounds else { return .zero }
        return CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }

    private func updateRotationPivotCenter() {
        let center = rotationPivotCenterInLayoutSpace()
        rotationPivotNode.position = SCNVector3(Float(center.x), Float(center.y), 0)
        for case let node as AVDisplayItemNode in displayItemNodes {
            node.rotationPivotOffset = center
            if let item = node.displayItem {
                node.displayItem(item, propertyDidChange: .frameToRoot)
            }
        }
    }

    func setDimension(_ dimension: AppViewPreviewDimension, animated: Bool) {
        self.dimension = dimension
        if dimension == .dimension3D {
            // 3D — keep rotation
        } else {
            setRotation(.zero, animated: animated)
        }
        refreshAllNodeImages()
        updateZPositionByZIndex()
    }

    private func refreshAllNodeImages() {
        for case let node as AVDisplayItemNode in displayItemNodes {
            node.refreshPreviewAppearance()
        }
    }

    private func updateZPositionByZIndex() {
        let interspace: CGFloat
        if dimension == .dimension2D {
            interspace = 0.01
        } else {
            interspace = 0.1 + _zInterspace * 0.7
        }

        var zIndexAndCountDict: [Int: Int] = [:]
        var maxZIndex = 0
        for case let node as AVDisplayItemNode in displayItemNodes {
            maxZIndex = max(maxZIndex, node.displayItem?.previewZIndex ?? 0)
        }
        let zIndexOffset = Int(round(Double(maxZIndex) * 0.5))

        SCNTransaction.begin()
        for case let node as AVDisplayItemNode in displayItemNodes {
            guard let item = node.displayItem else { continue }
            let adjustedZIndex = item.previewZIndex - zIndexOffset
            let countOfCurrentZIndex = zIndexAndCountDict[adjustedZIndex, default: 0]
            zIndexAndCountDict[adjustedZIndex] = countOfCurrentZIndex + 1
            let offsetToAvoidOverlapBug = CGFloat(countOfCurrentZIndex) * 0.0001

            var position = node.position
            let zBase = CGFloat(adjustedZIndex) * interspace
            position.z = zBase + offsetToAvoidOverlapBug
            node.position = position
        }
        SCNTransaction.commit()
    }

    private func updateZIndex(for item: AppViewDisplayItem) {
        item.previewZIndex = -1
        if item.displayingInHierarchy {
            if let referenceItem = maxZIndexForOverlappedItem(under: item) {
                item.previewZIndex = referenceItem.previewZIndex + 1
            } else {
                item.previewZIndex = 0
            }
        } else if let superItem = item.superItem {
            item.previewZIndex = superItem.previewZIndex
        } else {
            assertionFailure()
        }
        if item.previewZIndex < 0 {
            assertionFailure()
            item.previewZIndex = 0
        }
    }

    private func maxZIndexForOverlappedItem(under item: AppViewDisplayItem) -> AppViewDisplayItem? {
        guard let itemIndex = flatDisplayItems.firstIndex(where: { $0 === item }) else {
            assertionFailure()
            return nil
        }
        if itemIndex == 0 { return nil }

        let itemFrameToRoot = item.calculateFrameToRoot()
        var targetItem: AppViewDisplayItem?
        for idx in stride(from: itemIndex - 1, through: 0, by: -1) {
            let obj = flatDisplayItems[idx]
            if !obj.inHiddenHierarchy || showHiddenItems {
                if itemFrameToRoot.intersects(obj.calculateFrameToRoot()) {
                    if targetItem == nil {
                        targetItem = obj
                    } else if obj.previewZIndex > targetItem!.previewZIndex {
                        targetItem = obj
                    }
                }
            }
        }
        return targetItem
    }

    private func equivalentRotation(from rotation: CGPoint) -> CGPoint {
        var result = rotation
        result.x = equivalentRotationValue(from: result.x)
        result.y = equivalentRotationValue(from: result.y)
        return result
    }

    private func equivalentRotationValue(from rotation: CGFloat) -> CGFloat {
        var value = rotation
        while value <= -.pi { value += .pi * 2 }
        while value >= .pi { value -= .pi * 2 }
        return value
    }
}
