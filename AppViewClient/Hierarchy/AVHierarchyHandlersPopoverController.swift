//
//  AVHierarchyHandlersPopoverController.swift
//  AppView
//

import AppKit
import AppViewShared

class AVHierarchyHandlersPopoverController: AVBaseViewController {
    private var scrollView: NSScrollView!
    private var itemViews: [AVHierarchyHandlersPopoverItemView] = []
    private let verInset: CGFloat = 0

    init(displayItem: AppViewDisplayItem, editable: Bool) {
        super.init(containerView: nil)
        scrollView.documentView = AVBaseView()

        itemViews = (displayItem.eventHandlers ?? []).enumerated().map { idx, handler in
            let view = AVHierarchyHandlersPopoverItemView(eventHandler: handler, editable: editable)
            scrollView.documentView?.addSubview(view)
            view.needTopBorder = idx > 0
            view.isHidden = false
            return view
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func makeContainerView() -> NSView {
        scrollView = NSScrollView()
        scrollView.drawsBackground = false
        return scrollView
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        lk(scrollView.documentView!).fullWidth().y(0)

        var maxY: CGFloat = 0
        let visibleViews = (itemViews as NSArray).lk_visibleViews() as? [AVHierarchyHandlersPopoverItemView] ?? []
        for (idx, view) in visibleViews.enumerated() {
            let prevView = idx > 0 ? visibleViews[idx - 1] : nil
            let y = prevView.map { $0.frame.maxY } ?? verInset
            lk(view).fullWidth().appview_heightToFit().y(y)

            if idx == visibleViews.count - 1 {
                maxY = view.frame.maxY
            }
        }
        lk(scrollView.documentView!).height(maxY)
    }

    var neededSize: NSSize {
        var resultSize = NSSize(width: 0, height: verInset * 2)
        for itemView in itemViews where !itemView.isHidden {
            let itemSize = itemView.sizeThatFits(NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
            resultSize.width = max(resultSize.width, itemSize.width)
            resultSize.height += itemSize.height
        }
        return resultSize
    }
}
