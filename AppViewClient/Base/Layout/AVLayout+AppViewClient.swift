//
//  AVLayout+AppViewClient.swift
//  AppView
//

import AppKit

extension AVLayoutProxy {
    @discardableResult
    func appview_sizeToFit() -> AVLayoutProxy {
        unpackClassA(
            AVBaseView.self,
            doA: { obj, _ in
                guard let view = obj as? AVBaseView else { return }
                let size = view.sizeThatFits(NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
                var rect = view.frame
                rect.size = size
                view.lk_applyFrame(rect)
            },
            classB: NSControl.self,
            doB: { obj, _ in
                guard let control = obj as? NSControl else { return }
                var size = control.sizeThatFits(NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
                if size.width.isNaN { size.width = 0 }
                if size.height.isNaN { size.height = 0 }
                var rect = control.frame
                rect.size = size
                control.lk_applyFrame(rect)
            }
        )
        return self
    }

    @discardableResult
    func appview_heightToFit() -> AVLayoutProxy {
        unpackClassA(
            AVBaseView.self,
            doA: { obj, _ in
                guard let view = obj as? AVBaseView else { return }
                let limitedWidth = view.bounds.width
                let height = view.sizeThatFits(NSSize(width: limitedWidth, height: CGFloat.greatestFiniteMagnitude)).height
                var rect = view.frame
                rect.size.height = height
                view.lk_applyFrame(rect)
            },
            classB: NSControl.self,
            doB: { obj, _ in
                guard let control = obj as? NSControl else { return }
                let limitedWidth = control.bounds.width
                let height = control.sizeThatFits(NSSize(width: limitedWidth, height: CGFloat.greatestFiniteMagnitude)).height
                var rect = control.frame
                rect.size.height = height
                control.lk_applyFrame(rect)
            }
        )
        return self
    }

    @discardableResult
    func lk_minWidth(_ minWidth: CGFloat) -> AVLayoutProxy {
            if minWidth.isNaN {
                assertionFailure("传入了 NaN")
                return self
            }
            self.unpackClassA(
                NSView.self,
                doA: { obj, _ in
                    guard let view = obj as? NSView else { return }
                    var rect = view.frame
                    if rect.size.width < minWidth {
                        rect.size.width = minWidth
                        view.lk_applyFrame(rect)
                    }
                },
                classB: CALayer.self,
                doB: { obj, _ in
                    guard let layer = obj as? CALayer else { return }
                    var rect = layer.frame
                    if rect.size.width < minWidth {
                        rect.size.width = minWidth
                        layer.frame = rect
                    }
                }
            )
            return self
        
    }


    @discardableResult
    func lk_maxWidth(_ maxWidth: CGFloat) -> AVLayoutProxy {
            if maxWidth.isNaN {
                assertionFailure("传入了 NaN")
                return self
            }
            self.unpackClassA(
                NSView.self,
                doA: { obj, _ in
                    guard let view = obj as? NSView else { return }
                    view.lk_clampMaxWidth(maxWidth)
                },
                classB: CALayer.self,
                doB: { obj, _ in
                    guard let layer = obj as? CALayer else { return }
                    var rect = layer.frame
                    if rect.size.width > maxWidth {
                        rect.size.width = maxWidth
                        layer.frame = rect
                    }
                }
            )
            return self
        
    }

}
