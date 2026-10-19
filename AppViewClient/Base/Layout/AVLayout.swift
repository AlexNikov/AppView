//
//  AVLayout.swift
//  AVLayout.swift
//  AppView
//

import AppKit
import Foundation
import QuartzCore

private func scLayerContentsAreFlipped(_ layer: CALayer) -> Bool {
    if layer.responds(to: NSSelectorFromString("contentsAreFlipped")) {
        return layer.value(forKey: "contentsAreFlipped") as? Bool ?? layer.isGeometryFlipped
    }
    return layer.isGeometryFlipped
}

private func scSnapToPixel(_ rawValue: CGFloat) -> CGFloat {
    if rawValue == -CGFloat.greatestFiniteMagnitude || rawValue == CGFloat.greatestFiniteMagnitude {
        return rawValue
    }
    let screenScale = NSScreen.main?.backingScaleFactor ?? 2.0
    return ceil(rawValue * screenScale) / screenScale
}

extension AVLayoutProxy {
    @discardableResult
    func sizeToFit() -> AVLayoutProxy {
        appview_sizeToFit()
    }

    @discardableResult
    func width(_ value: CGFloat) -> AVLayoutProxy {
            var safeValue = value
            if safeValue.isNaN {
                assertionFailure("传入了 NaN")
                safeValue = 0
            }
            self.unpackClassA(
                NSView.self,
                doA: { obj, _ in
                    guard let view = obj as? NSView else { return }
                    var rect = view.frame
                    rect.size.width = scSnapToPixel(safeValue)
                    view.lk_applyFrame(rect)
                },
                classB: CALayer.self,
                doB: { obj, _ in
                    guard let layer = obj as? CALayer else { return }
                    var rect = layer.frame
                    rect.size.width = scSnapToPixel(safeValue)
                    layer.frame = rect
                }
            )
            return self
        
    }


    @discardableResult
    func height(_ value: CGFloat) -> AVLayoutProxy {
            var safeValue = value
            if safeValue.isNaN {
                assertionFailure("传入了 NaN")
                safeValue = 0
            }
            self.unpackClassA(
                NSView.self,
                doA: { obj, _ in
                    guard let view = obj as? NSView else { return }
                    var rect = view.frame
                    rect.size.height = scSnapToPixel(safeValue)
                    view.lk_applyFrame(rect)
                },
                classB: CALayer.self,
                doB: { obj, _ in
                    guard let layer = obj as? CALayer else { return }
                    var rect = layer.frame
                    rect.size.height = scSnapToPixel(safeValue)
                    layer.frame = rect
                }
            )
            return self
        
    }


    @discardableResult
    func size(_ value: CGSize) -> AVLayoutProxy {
            self.width(value.width).height(value.height)
        
    }


    @discardableResult
    func frame(_ value: CGRect) -> AVLayoutProxy {
            self.origin(value.origin).size(value.size)
        
    }


    @discardableResult
    func x(_ value: CGFloat) -> AVLayoutProxy {
            var safeValue = value
            if safeValue.isNaN {
                assertionFailure("传入了 NaN")
                safeValue = 0
            }
            self.unpackClassA(
                NSView.self,
                doA: { obj, _ in
                    guard let view = obj as? NSView else { return }
                    var rect = view.frame
                    rect.origin.x = scSnapToPixel(safeValue)
                    view.lk_applyFrame(rect)
                },
                classB: CALayer.self,
                doB: { obj, _ in
                    guard let layer = obj as? CALayer else { return }
                    var rect = layer.frame
                    rect.origin.x = scSnapToPixel(safeValue)
                    layer.frame = rect
                }
            )
            return self
        
    }


    @discardableResult
    func y(_ value: CGFloat) -> AVLayoutProxy {
            var safeValue = value
            if safeValue.isNaN {
                assertionFailure("传入了 NaN")
                safeValue = 0
            }
            self.unpackClassA(
                NSView.self,
                doA: { obj, _ in
                    guard let view = obj as? NSView else { return }
                    var rect = view.frame
                    rect.origin.y = scSnapToPixel(safeValue)
                    view.lk_applyFrame(rect)
                },
                classB: CALayer.self,
                doB: { obj, _ in
                    guard let layer = obj as? CALayer else { return }
                    var rect = layer.frame
                    rect.origin.y = scSnapToPixel(safeValue)
                    layer.frame = rect
                }
            )
            return self
        
    }


    @discardableResult
    func origin(_ value: CGPoint) -> AVLayoutProxy {
            self.x(value.x).y(value.y)
        
    }


    @discardableResult
    func offset(_ x: CGFloat, _ y: CGFloat) -> AVLayoutProxy {
            var safeX = x
            var safeY = y
            if safeX.isNaN {
                assertionFailure("传入了 NaN")
                safeX = 0
            }
            if safeY.isNaN {
                assertionFailure("传入了 NaN")
                safeY = 0
            }
            self.unpackClassA(
                NSView.self,
                doA: { obj, _ in
                    guard let view = obj as? NSView else { return }
                    var rect = view.frame
                    rect.origin.x = scSnapToPixel(view.frame.minX + safeX)
                    rect.origin.y = scSnapToPixel(view.frame.minY + safeY)
                    view.lk_applyFrame(rect)
                },
                classB: CALayer.self,
                doB: { obj, _ in
                    guard let layer = obj as? CALayer else { return }
                    var rect = layer.frame
                    rect.origin.x = scSnapToPixel(layer.frame.minX + safeX)
                    rect.origin.y = scSnapToPixel(layer.frame.minY + safeY)
                    layer.frame = rect
                }
            )
            return self
        
    }


    @discardableResult
    func midX(_ value: CGFloat) -> AVLayoutProxy {
            var safeValue = value
            if safeValue.isNaN {
                assertionFailure("传入了 NaN")
                safeValue = 0
            }
            self.unpackClassA(
                NSView.self,
                doA: { obj, _ in
                    guard let view = obj as? NSView else { return }
                    let width = view.bounds.width
                    lkLayoutMake(view).x(safeValue - width / 2)
                },
                classB: CALayer.self,
                doB: { obj, _ in
                    guard let layer = obj as? CALayer else { return }
                    let width = layer.bounds.width
                    lkLayoutMake(layer).x(safeValue - width / 2)
                }
            )
            return self
        
    }


    @discardableResult
    func maxX(_ value: CGFloat) -> AVLayoutProxy {
            var safeValue = value
            if safeValue.isNaN {
                assertionFailure("传入了 NaN")
                safeValue = 0
            }
            self.unpackClassA(
                NSView.self,
                doA: { obj, _ in
                    guard let view = obj as? NSView else { return }
                    let width = view.bounds.width
                    lkLayoutMake(view).x(safeValue - width)
                },
                classB: CALayer.self,
                doB: { obj, _ in
                    guard let layer = obj as? CALayer else { return }
                    let width = layer.bounds.width
                    lkLayoutMake(layer).x(safeValue - width)
                }
            )
            return self
        
    }


    @discardableResult
    func midY(_ value: CGFloat) -> AVLayoutProxy {
            var safeValue = value
            if safeValue.isNaN {
                assertionFailure("传入了 NaN")
                safeValue = 0
            }
            self.unpackClassA(
                NSView.self,
                doA: { obj, _ in
                    guard let view = obj as? NSView else { return }
                    let height = view.bounds.height
                    lkLayoutMake(view).y(safeValue - height / 2)
                },
                classB: CALayer.self,
                doB: { obj, _ in
                    guard let layer = obj as? CALayer else { return }
                    let height = layer.bounds.height
                    lkLayoutMake(layer).y(safeValue - height / 2)
                }
            )
            return self
        
    }


    @discardableResult
    func maxY(_ value: CGFloat) -> AVLayoutProxy {
            var safeValue = value
            if safeValue.isNaN {
                assertionFailure("传入了 NaN")
                safeValue = 0
            }
            self.unpackClassA(
                NSView.self,
                doA: { obj, _ in
                    guard let view = obj as? NSView else { return }
                    let height = view.bounds.height
                    lkLayoutMake(view).y(safeValue - height)
                },
                classB: CALayer.self,
                doB: { obj, _ in
                    guard let layer = obj as? CALayer else { return }
                    let height = layer.bounds.height
                    lkLayoutMake(layer).y(safeValue - height)
                }
            )
            return self
        
    }


    @discardableResult
    func right(_ value: CGFloat) -> AVLayoutProxy {
            var safeValue = value
            if safeValue.isNaN {
                assertionFailure("传入了 NaN")
                safeValue = 0
            }
            self.unpackClassA(
                NSView.self,
                doA: { obj, _ in
                    guard let view = obj as? NSView else { return }
                    if let superview = view.superview {
                        let superWidth = superview.bounds.width
                        lkLayoutMake(view).maxX(superWidth - safeValue)
                    } else {
                        assertionFailure("必须存在 superview 才可使用该方法")
                    }
                },
                classB: CALayer.self,
                doB: { obj, _ in
                    guard let layer = obj as? CALayer else { return }
                    if let superlayer = layer.superlayer {
                        let superWidth = superlayer.bounds.width
                        lkLayoutMake(layer).maxX(superWidth - safeValue)
                    } else {
                        assertionFailure("必须存在 superlayer 才可使用该方法")
                    }
                }
            )
            return self
        
    }


    @discardableResult
    func bottom(_ value: CGFloat) -> AVLayoutProxy {
            var safeValue = value
            if safeValue.isNaN {
                assertionFailure("传入了 NaN")
                safeValue = 0
            }
            self.unpackClassA(
                NSView.self,
                doA: { obj, _ in
                    guard let view = obj as? NSView else { return }
                    if let superview = view.superview {
                        let superHeight = superview.bounds.height
                        if superview.isFlipped {
                            lkLayoutMake(view).maxY(superHeight - safeValue)
                        } else {
                            lkLayoutMake(view).y(safeValue)
                        }
                    } else {
                        assertionFailure("必须存在 superview 才可使用该方法")
                    }
                },
                classB: CALayer.self,
                doB: { obj, _ in
                    guard let layer = obj as? CALayer else { return }
                    if let superlayer = layer.superlayer {
                        if scLayerContentsAreFlipped(superlayer) {
                            let superHeight = superlayer.bounds.height
                            lkLayoutMake(layer).maxY(superHeight - safeValue)
                        } else {
                            lkLayoutMake(layer).y(safeValue)
                        }
                    } else {
                        assertionFailure("必须存在 superlayer 才可使用该方法")
                    }
                }
            )
            return self
        
    }


    @discardableResult
    func horAlign() -> AVLayoutProxy {
        unpackClassA(
            NSView.self,
            doA: { obj, _ in
                guard let view = obj as? NSView else { return }
                if let superview = view.superview {
                    let superWidth = superview.bounds.width
                    lkLayoutMake(view).midX(superWidth / 2)
                } else {
                    assertionFailure("必须存在 superview 才可使用该方法")
                }
            },
            classB: CALayer.self,
            doB: { obj, _ in
                guard let layer = obj as? CALayer else { return }
                if let superlayer = layer.superlayer {
                    let superWidth = superlayer.bounds.width
                    lkLayoutMake(layer).midX(superWidth / 2)
                } else {
                    assertionFailure("必须存在 superlayer 才可使用该方法")
                }
            }
        )
        return self
    }

    @discardableResult
    func verAlign() -> AVLayoutProxy {
        unpackClassA(
            NSView.self,
            doA: { obj, _ in
                guard let view = obj as? NSView else { return }
                if let superview = view.superview {
                    let superHeight = superview.bounds.height
                    lkLayoutMake(view).midY(superHeight / 2)
                } else {
                    assertionFailure("必须存在 superview 才可使用该方法")
                }
            },
            classB: CALayer.self,
            doB: { obj, _ in
                guard let layer = obj as? CALayer else { return }
                if let superlayer = layer.superlayer {
                    let superHeight = superlayer.bounds.height
                    lkLayoutMake(layer).midY(superHeight / 2)
                } else {
                    assertionFailure("必须存在 superlayer 才可使用该方法")
                }
            }
        )
        return self
    }

    @discardableResult
    func centerAlign() -> AVLayoutProxy {
        verAlign().horAlign()
    }

    @discardableResult
    func fullWidth() -> AVLayoutProxy {
        x(0).toRight(0)
        return self
    }

    @discardableResult
    func fullHeight() -> AVLayoutProxy {
        unpackClassA(
            NSView.self,
            doA: { obj, _ in
                guard let view = obj as? NSView else { return }
                if let superview = view.superview {
                    let superHeight = superview.bounds.height
                    lkLayoutMake(view).height(superHeight).y(0)
                } else {
                    assertionFailure("必须存在 superview 才可使用该方法")
                }
            },
            classB: CALayer.self,
            doB: { obj, _ in
                guard let layer = obj as? CALayer else { return }
                if let superlayer = layer.superlayer {
                    let superHeight = superlayer.bounds.height
                    lkLayoutMake(layer).height(superHeight).y(0)
                } else {
                    assertionFailure("必须存在 superlayer 才可使用该方法")
                }
            }
        )
        return self
    }

    @discardableResult
    func fullFrame() -> AVLayoutProxy {
        fullWidth().fullHeight()
    }

    @discardableResult
    func offsetX(_ x: CGFloat) -> AVLayoutProxy {
            self.offset(x, 0)
            return self
        
    }


    @discardableResult
    func offsetY(_ y: CGFloat) -> AVLayoutProxy {
            self.offset(0, y)
            return self
        
    }


    @discardableResult
    func groupX(_ value: CGFloat) -> AVLayoutProxy {
            self.offsetX(value - self.dollarGroupX)
            return self
        
    }


    @discardableResult
    func groupMidX(_ value: CGFloat) -> AVLayoutProxy {
            self.offsetX(value - self.dollarGroupMidX)
            return self
        
    }


    @discardableResult
    func groupMaxX(_ value: CGFloat) -> AVLayoutProxy {
            self.offsetX(value - self.dollarGroupMaxX)
            return self
        
    }


    @discardableResult
    func groupY(_ value: CGFloat) -> AVLayoutProxy {
            self.offsetY(value - self.dollarGroupY)
            return self
        
    }


    @discardableResult
    func groupMidY(_ value: CGFloat) -> AVLayoutProxy {
            self.offsetY(value - self.dollarGroupMidY)
            return self
        
    }


    @discardableResult
    func groupMaxY(_ value: CGFloat) -> AVLayoutProxy {
            self.offsetY(value - self.dollarGroupMaxY)
            return self
        
    }


    @discardableResult
    func groupOrigin(_ value: CGPoint) -> AVLayoutProxy {
            self.offset(value.x - self.dollarGroupX, value.y - self.dollarGroupY)
            return self
        
    }


    @discardableResult
    func groupRight(_ value: CGFloat) -> AVLayoutProxy {
            if !self.allPackedViewsAndLayersAreInTheSameCoordinate() {
                return self
            }
            var superWidth: CGFloat = 0
            self.unpackClassA(
                NSView.self,
                doA: { obj, stop in
                    guard let view = obj as? NSView else { return }
                    superWidth = view.superview?.bounds.width ?? 0
                    stop.pointee = true
                },
                classB: CALayer.self,
                doB: { obj, stop in
                    guard let layer = obj as? CALayer else { return }
                    superWidth = layer.superlayer?.bounds.width ?? 0
                    stop.pointee = true
                }
            )
            self.groupMaxX(superWidth - value)
            return self
        
    }


    @discardableResult
    func groupBottom(_ value: CGFloat) -> AVLayoutProxy {
            var superlayer: CALayer?
            var superview: NSView?
            if !self.allPackedViewsAndLayersAreInTheSameCoordinate(superlayer: &superlayer, superview: &superview) {
                return self
            }
            if let superlayer {
                if scLayerContentsAreFlipped(superlayer) {
                    self.groupMaxY(superlayer.bounds.height - value)
                } else {
                    self.groupY(value)
                }
            } else if let superview {
                if superview.isFlipped {
                    self.groupMaxY(superview.bounds.height - value)
                } else {
                    self.groupY(value)
                }
            }
            return self
        
    }


    @discardableResult
    func groupHorAlign() -> AVLayoutProxy {
        if !allPackedViewsAndLayersAreInTheSameCoordinate() {
            return self
        }
        var superWidth: CGFloat = 0
        unpackClassA(
            NSView.self,
            doA: { obj, stop in
                guard let view = obj as? NSView else { return }
                superWidth = view.superview?.bounds.width ?? 0
                stop.pointee = true
            },
            classB: CALayer.self,
            doB: { obj, stop in
                guard let layer = obj as? CALayer else { return }
                superWidth = layer.superlayer?.bounds.width ?? 0
                stop.pointee = true
            }
        )
        groupMidX(superWidth / 2)
        return self
    }

    @discardableResult
    func groupVerAlign() -> AVLayoutProxy {
        if !allPackedViewsAndLayersAreInTheSameCoordinate() {
            return self
        }
        var superHeight: CGFloat = 0
        unpackClassA(
            NSView.self,
            doA: { obj, stop in
                guard let view = obj as? NSView else { return }
                superHeight = view.superview?.bounds.height ?? 0
                stop.pointee = true
            },
            classB: CALayer.self,
            doB: { obj, stop in
                guard let layer = obj as? CALayer else { return }
                superHeight = layer.superlayer?.bounds.height ?? 0
                stop.pointee = true
            }
        )
        groupMidY(superHeight / 2)
        return self
    }

    @discardableResult
    func groupCenterAlign() -> AVLayoutProxy {
        groupVerAlign().groupHorAlign()
    }

    var dollarGroupX: CGFloat {
        if (filteredGet(NSView.self, CALayer.self)?.count ?? 0) > 1,
           !allPackedViewsAndLayersAreInTheSameCoordinate() {
            return 0
        }
        var minX: CGFloat = 0
        var hasDeterminedMinX = false
        unpackClassA(
            NSView.self,
            doA: { obj, _ in
                guard let view = obj as? NSView else { return }
                minX = hasDeterminedMinX ? min(minX, view.frame.minX) : view.frame.minX
                hasDeterminedMinX = true
            },
            classB: CALayer.self,
            doB: { obj, _ in
                guard let layer = obj as? CALayer else { return }
                minX = hasDeterminedMinX ? min(minX, layer.frame.minX) : layer.frame.minX
                hasDeterminedMinX = true
            }
        )
        return minX
    }

    var dollarGroupMidX: CGFloat {
        if (filteredGet(NSView.self, CALayer.self)?.count ?? 0) > 1,
           !allPackedViewsAndLayersAreInTheSameCoordinate() {
            return 0
        }
        let minX = dollarGroupX
        let maxX = dollarGroupMaxX
        return minX + (maxX - minX) / 2
    }

    var dollarGroupMaxX: CGFloat {
        if (filteredGet(NSView.self, CALayer.self)?.count ?? 0) > 1,
           !allPackedViewsAndLayersAreInTheSameCoordinate() {
            return 0
        }
        var maxX: CGFloat = 0
        var hasDeterminedMaxX = false
        unpackClassA(
            NSView.self,
            doA: { obj, _ in
                guard let view = obj as? NSView else { return }
                maxX = hasDeterminedMaxX ? max(maxX, view.frame.maxX) : view.frame.maxX
                hasDeterminedMaxX = true
            },
            classB: CALayer.self,
            doB: { obj, _ in
                guard let layer = obj as? CALayer else { return }
                maxX = hasDeterminedMaxX ? max(maxX, layer.frame.maxX) : layer.frame.maxX
                hasDeterminedMaxX = true
            }
        )
        return maxX
    }

    var dollarGroupY: CGFloat {
        if (filteredGet(NSView.self, CALayer.self)?.count ?? 0) > 1,
           !allPackedViewsAndLayersAreInTheSameCoordinate() {
            return 0
        }
        var minY: CGFloat = 0
        var hasDeterminedMinY = false
        unpackClassA(
            NSView.self,
            doA: { obj, _ in
                guard let view = obj as? NSView else { return }
                minY = hasDeterminedMinY ? min(minY, view.frame.minY) : view.frame.minY
                hasDeterminedMinY = true
            },
            classB: CALayer.self,
            doB: { obj, _ in
                guard let layer = obj as? CALayer else { return }
                minY = hasDeterminedMinY ? min(minY, layer.frame.minY) : layer.frame.minY
                hasDeterminedMinY = true
            }
        )
        return minY
    }

    var dollarGroupMidY: CGFloat {
        if (filteredGet(NSView.self, CALayer.self)?.count ?? 0) > 1,
           !allPackedViewsAndLayersAreInTheSameCoordinate() {
            return 0
        }
        let minY = dollarGroupY
        let maxY = dollarGroupMaxY
        return minY + (maxY - minY) / 2
    }

    var dollarGroupMaxY: CGFloat {
        if (filteredGet(NSView.self, CALayer.self)?.count ?? 0) > 1,
           !allPackedViewsAndLayersAreInTheSameCoordinate() {
            return 0
        }
        var maxY: CGFloat = 0
        var hasDeterminedMaxY = false
        unpackClassA(
            NSView.self,
            doA: { obj, _ in
                guard let view = obj as? NSView else { return }
                maxY = hasDeterminedMaxY ? max(maxY, view.frame.maxY) : view.frame.maxY
                hasDeterminedMaxY = true
            },
            classB: CALayer.self,
            doB: { obj, _ in
                guard let layer = obj as? CALayer else { return }
                maxY = hasDeterminedMaxY ? max(maxY, layer.frame.maxY) : layer.frame.maxY
                hasDeterminedMaxY = true
            }
        )
        return maxY
    }

    var dollarGroupOrigin: CGPoint {
        CGPoint(x: dollarGroupX, y: dollarGroupY)
    }

    var dollarGroupWidth: CGFloat {
        if (filteredGet(NSView.self, CALayer.self)?.count ?? 0) > 1,
           !allPackedViewsAndLayersAreInTheSameCoordinate() {
            return 0
        }
        return dollarGroupMaxX - dollarGroupX
    }

    var dollarGroupHeight: CGFloat {
        if (filteredGet(NSView.self, CALayer.self)?.count ?? 0) > 1,
           !allPackedViewsAndLayersAreInTheSameCoordinate() {
            return 0
        }
        return dollarGroupMaxY - dollarGroupY
    }

    var dollarGroupSize: CGSize {
        if (filteredGet(NSView.self, CALayer.self)?.count ?? 0) > 1,
           !allPackedViewsAndLayersAreInTheSameCoordinate() {
            return .zero
        }
        return CGSize(width: dollarGroupWidth, height: dollarGroupHeight)
    }

    @discardableResult
    func toX(_ value: CGFloat) -> AVLayoutProxy {
            var safeValue = value
            if safeValue.isNaN {
                assertionFailure("传入了 NaN")
                safeValue = 0
            }
            self.unpackClassA(
                NSView.self,
                doA: { obj, _ in
                    guard let view = obj as? NSView else { return }
                    var rect = view.frame
                    var clamped = safeValue
                    if clamped > rect.maxX { clamped = rect.maxX }
                    rect.size.width = scSnapToPixel(rect.maxX - clamped)
                    rect.origin.x = scSnapToPixel(clamped)
                    view.lk_applyFrame(rect)
                },
                classB: CALayer.self,
                doB: { obj, _ in
                    guard let layer = obj as? CALayer else { return }
                    var rect = layer.frame
                    var clamped = safeValue
                    if clamped > rect.maxX { clamped = rect.maxX }
                    rect.size.width = scSnapToPixel(rect.maxX - clamped)
                    rect.origin.x = scSnapToPixel(clamped)
                    layer.frame = rect
                }
            )
            return self
        
    }


    @discardableResult
    func toMaxX(_ value: CGFloat) -> AVLayoutProxy {
            var safeValue = value
            if safeValue.isNaN {
                assertionFailure("传入了 NaN")
                safeValue = 0
            }
            self.unpackClassA(
                NSView.self,
                doA: { obj, _ in
                    guard let view = obj as? NSView else { return }
                    var rect = view.frame
                    var clamped = safeValue
                    if clamped < rect.minX { clamped = rect.minX }
                    rect.size.width = scSnapToPixel(clamped - rect.minX)
                    view.lk_applyFrame(rect)
                },
                classB: CALayer.self,
                doB: { obj, _ in
                    guard let layer = obj as? CALayer else { return }
                    var rect = layer.frame
                    var clamped = safeValue
                    if clamped < rect.minX { clamped = rect.minX }
                    rect.size.width = scSnapToPixel(clamped - rect.minX)
                    layer.frame = rect
                }
            )
            return self
        
    }


    @discardableResult
    func toY(_ value: CGFloat) -> AVLayoutProxy {
            var safeValue = value
            if safeValue.isNaN {
                assertionFailure("传入了 NaN")
                safeValue = 0
            }
            self.unpackClassA(
                NSView.self,
                doA: { obj, _ in
                    guard let view = obj as? NSView else { return }
                    var rect = view.frame
                    var clamped = safeValue
                    if clamped > rect.maxY { clamped = rect.maxY }
                    rect.size.height = scSnapToPixel(rect.maxY - clamped)
                    rect.origin.y = scSnapToPixel(clamped)
                    view.lk_applyFrame(rect)
                },
                classB: CALayer.self,
                doB: { obj, _ in
                    guard let layer = obj as? CALayer else { return }
                    var rect = layer.frame
                    var clamped = safeValue
                    if clamped > rect.maxY { clamped = rect.maxY }
                    rect.size.height = scSnapToPixel(rect.maxY - clamped)
                    rect.origin.y = scSnapToPixel(clamped)
                    layer.frame = rect
                }
            )
            return self
        
    }


    @discardableResult
    func toMaxY(_ value: CGFloat) -> AVLayoutProxy {
            var safeValue = value
            if safeValue.isNaN {
                assertionFailure("传入了 NaN")
                safeValue = 0
            }
            self.unpackClassA(
                NSView.self,
                doA: { obj, _ in
                    guard let view = obj as? NSView else { return }
                    var rect = view.frame
                    var clamped = safeValue
                    if clamped < rect.minY { clamped = rect.minY }
                    rect.size.height = scSnapToPixel(clamped - rect.minY)
                    view.lk_applyFrame(rect)
                },
                classB: CALayer.self,
                doB: { obj, _ in
                    guard let layer = obj as? CALayer else { return }
                    var rect = layer.frame
                    var clamped = safeValue
                    if clamped < rect.minY { clamped = rect.minY }
                    rect.size.height = scSnapToPixel(clamped - rect.minY)
                    layer.frame = rect
                }
            )
            return self
        
    }


    @discardableResult
    func toRight(_ value: CGFloat) -> AVLayoutProxy {
            var safeValue = value
            if safeValue.isNaN {
                assertionFailure("传入了 NaN")
                safeValue = 0
            }
            self.unpackClassA(
                NSView.self,
                doA: { obj, _ in
                    guard let view = obj as? NSView, let superview = view.superview else { return }
                    var rect = view.frame
                    var width = scSnapToPixel(superview.bounds.width - rect.minX - safeValue)
                    if width < 0 { width = 0 }
                    rect.size.width = width
                    view.lk_applyFrame(rect)
                },
                classB: CALayer.self,
                doB: { obj, _ in
                    guard let layer = obj as? CALayer, let superlayer = layer.superlayer else { return }
                    var rect = layer.frame
                    var width = scSnapToPixel(superlayer.bounds.width - rect.minX - safeValue)
                    if width < 0 { width = 0 }
                    rect.size.width = width
                    layer.frame = rect
                }
            )
            return self
        
    }


    @discardableResult
    func toBottom(_ value: CGFloat) -> AVLayoutProxy {
            var safeValue = value
            if safeValue.isNaN {
                assertionFailure("传入了 NaN")
                safeValue = 0
            }
            self.unpackClassA(
                NSView.self,
                doA: { obj, _ in
                    guard let view = obj as? NSView else { return }
                    if let superview = view.superview {
                        if superview.isFlipped {
                            let maxY = superview.bounds.height - safeValue
                            lkLayoutMake(view).toMaxY(maxY)
                        } else {
                            lkLayoutMake(view).toY(safeValue)
                        }
                    } else {
                        assertionFailure("必须存在 superview 才可使用该方法")
                    }
                },
                classB: CALayer.self,
                doB: { obj, _ in
                    guard let layer = obj as? CALayer else { return }
                    if let superlayer = layer.superlayer {
                        if scLayerContentsAreFlipped(superlayer) {
                            let maxY = superlayer.bounds.height - safeValue
                            lkLayoutMake(layer).toMaxY(maxY)
                        } else {
                            lkLayoutMake(layer).toY(safeValue)
                        }
                    } else {
                        assertionFailure("必须存在 superlayer 才可使用该方法")
                    }
                }
            )
            return self
        
    }


    @discardableResult
    func heightToFit() -> AVLayoutProxy {
        appview_heightToFit()
    }

    @discardableResult
    func widthToFit() -> AVLayoutProxy {
        unpack(NSControl.self) { obj, _ in
            guard let view = obj as? NSControl else { return }
            let height = view.bounds.height
            let width = view.sizeThatFits(NSSize(width: CGFloat.greatestFiniteMagnitude, height: height)).width
            lkLayoutMake(view).width(width)
        }
        return self
    }

    func getBestSize() -> CGSize {
        var size = CGSize.zero
        unpack(NSControl.self) { obj, _ in
            guard let view = obj as? NSControl else { return }
            size = view.sizeThatFits(NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        }
        return size
    }

    func getBestWidth() -> CGFloat {
        getBestSize().width
    }

    func getBestHeight() -> CGFloat {
        getBestSize().height
    }

    func allPackedViewsAndLayersAreInTheSameCoordinate(
        superlayer: AutoreleasingUnsafeMutablePointer<CALayer?>? = nil,
        superview: AutoreleasingUnsafeMutablePointer<NSView?>? = nil
    ) -> Bool {
        guard _get != nil else { return false }

        var validated = true
        var foundSuperview: NSView?
        var foundSuperlayer: CALayer?

        unpackClassA(
            NSView.self,
            doA: { obj, stop in
                guard let view = obj as? NSView else { return }
                guard let parent = view.superview else {
                    validated = false
                    assertionFailure("superview 不存在")
                    stop.pointee = true
                    return
                }
                if let foundSuperview {
                    if parent != foundSuperview {
                        validated = false
                        assertionFailure("包装了多个 View 对象，但它们没有相同的 superview")
                        stop.pointee = true
                    }
                } else {
                    foundSuperview = parent
                }
            },
            classB: CALayer.self,
            doB: { obj, stop in
                guard let layer = obj as? CALayer else { return }
                guard let parent = layer.superlayer else {
                    validated = false
                    assertionFailure("superlayer 不存在")
                    stop.pointee = true
                    return
                }
                if let foundSuperlayer {
                    if parent != foundSuperlayer {
                        validated = false
                        assertionFailure("包装了多个 CALayer 对象，但它们没有相同的 superlayer")
                        stop.pointee = true
                    }
                } else {
                    foundSuperlayer = parent
                }
            }
        )

        if validated, let foundSuperview, let foundSuperlayer, foundSuperview.layer != foundSuperlayer {
            if foundSuperview.layer == nil {
                validated = false
                assertionFailure("同时包装了 View 和 Layer 对象，但其中某些 View 的 layer 属性为 nil，是否忘记设置 wantsLayer 为 YES？")
            } else if foundSuperview.layer != foundSuperlayer {
                validated = false
                assertionFailure("同时包装了 View 和 Layer 对象，但这些 View 和 Layer 没有相同的 superlayer")
            }
        }

        if validated {
            if let foundSuperlayer, let superlayer {
                superlayer.pointee = foundSuperlayer
            }
            if let foundSuperview, let superview {
                superview.pointee = foundSuperview
            }
            if foundSuperlayer == nil, let foundSuperview, let superlayer {
                superlayer.pointee = foundSuperview.layer
            }
        }
        return validated
    }
}

extension NSView {
    var scDollarX: CGFloat { lkLayoutMake(self).dollarGroupX }

    var scDollarMidX: CGFloat { lkLayoutMake(self).dollarGroupMidX }

    var scDollarMaxX: CGFloat { lkLayoutMake(self).dollarGroupMaxX }

    var scDollarY: CGFloat { lkLayoutMake(self).dollarGroupY }

    var scDollarMidY: CGFloat { lkLayoutMake(self).dollarGroupMidY }

    var scDollarMaxY: CGFloat { lkLayoutMake(self).dollarGroupMaxY }

    var scDollarWidth: CGFloat { lkLayoutMake(self).dollarGroupWidth }

    var scDollarHeight: CGFloat { lkLayoutMake(self).dollarGroupHeight }

    var scDollarSize: CGSize { lkLayoutMake(self).dollarGroupSize }
}

extension CALayer {
    var scDollarX: CGFloat { lkLayoutMake(self).dollarGroupX }

    var scDollarMidX: CGFloat { lkLayoutMake(self).dollarGroupMidX }

    var scDollarMaxX: CGFloat { lkLayoutMake(self).dollarGroupMaxX }

    var scDollarY: CGFloat { lkLayoutMake(self).dollarGroupY }

    var scDollarMidY: CGFloat { lkLayoutMake(self).dollarGroupMidY }

    var scDollarMaxY: CGFloat { lkLayoutMake(self).dollarGroupMaxY }

    var scDollarWidth: CGFloat { lkLayoutMake(self).dollarGroupWidth }

    var scDollarHeight: CGFloat { lkLayoutMake(self).dollarGroupHeight }

    var scDollarSize: CGSize { lkLayoutMake(self).dollarGroupSize }
}
