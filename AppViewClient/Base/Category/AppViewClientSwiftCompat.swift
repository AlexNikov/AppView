//
//  AppViewClientSwiftCompat.swift
//  AppView
//

import AppKit
import AppViewShared
import RxSwift

// MARK: - Types migrated from stub headers

enum AVViewBorderPosition: Int {
    case none
    case top
    case left
    case bottom
    case right
}

enum AVUserActionType: Int {
    case none
    case previewOperation
    case dashboardClick
    case selectedItemChange
}

protocol AVUserActionManagerDelegate: AnyObject {
    func lkUserActionManager(_ manager: AVUserActionManager, didAct type: AVUserActionType)
}

enum AVNumberInputViewStyle: UInt {
    case horizontal
    case vertical
}

func AppViewCastDisplayItemDetails(_ value: Any) -> [AppViewDisplayItemDetail] {
    if let detail = value as? AppViewDisplayItemDetail {
        return [detail]
    }
    if let details = value as? [AppViewDisplayItemDetail] {
        return details
    }
    if let array = value as? [Any] {
        return array.compactMap { $0 as? AppViewDisplayItemDetail }
    }
    if let nsArray = value as? NSArray {
        return nsArray.compactMap { $0 as? AppViewDisplayItemDetail }
    }
    return []
}

func AppViewCastConnectionResponseAttachment(_ value: Any?) -> AppViewConnectionResponseAttachment? {
    value as? AppViewConnectionResponseAttachment
}

func NSImageMake(_ imageName: String) -> NSImage? {
    NSImage(named: imageName)
}

func NSFontMake(_ fontSize: CGFloat) -> NSFont {
    NSFont.systemFont(ofSize: fontSize)
}

func AppViewColorMake(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(calibratedRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: 1)
}

func AppViewColorRGBAMake(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> NSColor {
    NSColor(calibratedRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
}

var CurrentKeyWindow: NSWindow? { NSApp.keyWindow }

var CurrentTime: TimeInterval { Date().timeIntervalSince1970 }

let NSSizeMax = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

var IsEnglish: Bool { AVHelper.isEnglish() }

var TutorialMng: AVTutorialManager { AVTutorialManager.sharedInstance() }

func AppViewErrorMake(_ errorTitle: String, _ errorDetail: String) -> NSError {
    NSError(
        domain: AppViewErrorDomain,
        code: Int(AppViewErrCode_Default),
        userInfo: [
            NSLocalizedDescriptionKey: errorTitle,
            NSLocalizedRecoverySuggestionErrorKey: errorDetail,
        ]
    )
}

func AVColorsCombine(_ colorA: NSColor, _ b: NSColor) -> AVTwoColors {
    let colors = AVTwoColors()
    colors.colorInLightMode = colorA
    colors.colorInDarkMode = b
    return colors
}

var InspectingApp: AVInspectableApp? { AVAppsManager.sharedInstance.inspectingApp }


extension Array {
    func appview_hasIndex(_ index: Int) -> Bool {
        guard index != NSNotFound, index >= 0 else { return false }
        return count > index
    }

    func appview_firstFiltered(_ block: (Element) -> Bool) -> Element? {
        first(where: block)
    }
}


let NSColorGray1 = AppViewColorMake(53, 60, 70)
let NSColorGray9 = AppViewColorMake(216, 220, 228)

let SeparatorLightModeColor = AppViewColorMake(215, 215, 215)
let SeparatorDarkModeColor = AppViewColorMake(67, 67, 69)

// MARK: - Layout constants (formerly AVHelper.h)

let HierarchyMinWidth: CGFloat = 200
let MeasureViewWidth: CGFloat = 240
let DashboardViewWidth: CGFloat = 260
let DashboardAttrItemHorInterspace: CGFloat = 10
let DashboardAttrItemVerInterspace: CGFloat = 9
let DashboardHorInset: CGFloat = 10
let DashboardCardControlCornerRadius: CGFloat = 4
let DashboardSectionMarginTop: CGFloat = 10
let DashboardCardCornerRadius: CGFloat = 6
let DashboardSearchCardInset: CGFloat = 6
let ConsoleInsetLeft: CGFloat = 10
let ConsoleInsetRight: CGFloat = 26
let ZoomSliderMaxValue: CGFloat = 2.8

struct HorizontalMargins {
    var left: CGFloat
    var right: CGFloat
}

func HorizontalMarginsMake(_ left: CGFloat, _ right: CGFloat) -> HorizontalMargins {
    HorizontalMargins(left: left, right: right)
}

// MARK: - Alerts (ObjC macros)

func AlertError(_ error: NSError, _ window: NSWindow?) {
    guard error.code != Int(AppViewErrCode_Discard) else { return }
    AVLogsManager.shared.logError(error)
    NotificationCenter.default.post(
        name: .AVShowErrorNotification,
        object: nil,
        userInfo: [AVShowErrorNotificationTitleKey: error.localizedDescription]
    )
}

func AlertErrorText(_ title: String, _ detail: String, _ window: NSWindow?) {
    AlertError(AppViewErrorMake(title, detail), window)
}

func AppViewAnyDoubleValue(_ value: Any) -> Double {
    if let params = value as? AppViewMsgActionParams { return params.doubleValue }
    if let n = value as? NSNumber { return n.doubleValue }
    if let n = value as? Double { return n }
    if let s = value as? String { return Double(s) ?? 0 }
    return 0
}

// MARK: - Array resize (Swift ports of NSArray+AppView)

private func appviewResizeElements<T>(
    _ elements: [T],
    count: Int,
    add: (UInt) -> T,
    remove: ((UInt, T) -> Void)? = nil,
    doNext: ((UInt, T) -> Void)? = nil
) -> [T] {
    var result = elements
    while result.count < count {
        let idx = UInt(result.count)
        result.append(add(idx))
    }
    while result.count > count {
        let idx = UInt(result.count - 1)
        let obj = result.removeLast()
        remove?(idx, obj)
    }
    for (idx, obj) in result.enumerated() {
        doNext?(UInt(idx), obj)
    }
    return result
}


extension Array {
    func appview_resize(
        withCount count: Int,
        add: @escaping (UInt) -> Element,
        remove: ((UInt, Element) -> Void)? = nil,
        doNext: ((UInt, Element) -> Void)? = nil
    ) -> [Element] {
        appviewResizeElements(self, count: count, add: add, remove: remove, doNext: doNext)
    }

    func appview_resize(
        count: Int,
        add: @escaping (UInt) -> Element,
        remove: ((UInt, Element) -> Void)? = nil,
        doNext: ((UInt, Element) -> Void)? = nil
    ) -> [Element] {
        appviewResizeElements(self, count: count, add: add, remove: remove, doNext: doNext)
    }
}


extension NSMutableArray {
    func appview_resize<T>(
        withCount count: Int,
        add: @escaping (UInt) -> T,
        remove: ((UInt, T) -> Void)? = nil,
        doNext: ((UInt, T) -> Void)? = nil
    ) {
        let typed = compactMap { $0 as? T }
        let result = appviewResizeElements(typed, count: count, add: add, remove: remove, doNext: doNext)
        removeAllObjects()
        addObjects(from: result)
    }
}

extension Int {
    func appview_resize<T>(
        count: Int,
        add: @escaping (UInt) -> T,
        remove: ((UInt, T) -> Void)? = nil,
        doNext: ((UInt, T) -> Void)? = nil
    ) -> [T] {
        appviewResizeElements([T](), count: count, add: add, remove: remove, doNext: doNext)
    }
}

// MARK: - RAC bridging

extension Array where Element: Equatable {
    func appview_arrayByRemovingObject(_ obj: Element) -> [Element] {
        filter { $0 != obj }
    }
}

// MARK: - NSEdgeInsets

extension NSEdgeInsets {
    static var zero: NSEdgeInsets { NSEdgeInsetsZero }
}

// MARK: - NSMutableArray dequeue (ObjC API)

extension NSMutableArray {
    func appview_dequeue(
        withCount count: UInt,
        add: @escaping (UInt) -> Any,
        notDequeued: ((UInt, Any) -> Void)? = nil,
        doNext: ((UInt, Any) -> Void)? = nil
    ) {
        while UInt(self.count) < count {
            let idx = UInt(self.count)
            self.add(add(idx))
        }
        if UInt(self.count) > count {
            let extraRange = Int(count) ..< self.count
            for idx in extraRange {
                notDequeued?(UInt(idx), self[idx])
            }
            self.removeObjects(at: IndexSet(extraRange))
        }
        for idx in 0 ..< Int(count) {
            doNext?(UInt(idx), self[idx])
        }
    }

    func appview_dequeue(
        withCount count: Int,
        add: @escaping (UInt) -> Any,
        notDequeued: ((UInt, Any) -> Void)? = nil,
        doNext: ((UInt, Any) -> Void)? = nil
    ) {
        appview_dequeue(
            withCount: UInt(count),
            add: add,
            notDequeued: notDequeued,
            doNext: doNext
        )
    }
}

extension Int {
    func appview_dequeue<T>(
        count: Int,
        add: @escaping (UInt) -> T,
        remove: ((UInt, T) -> Void)? = nil,
        doNext: ((UInt, T) -> Void)? = nil
    ) -> [T] {
        appview_resize(count: count, add: add, remove: remove, doNext: doNext)
    }
}


extension NSView {
    var appview_isEffectivelyVisible: Bool {
        !isHidden && alphaValue >= 0.01
    }
}

extension AVBaseView {
    var lk_clientIsVisible: Bool {
        superview != nil && !isHidden && alphaValue >= 0.01
    }
}

extension NSImage {
    static func appviewNamed(_ name: String) -> NSImage {
        NSImage(named: name) ?? NSImage(size: NSSize(width: 1, height: 1))
    }
}

// Re-export for client targets that don't see AppViewServerShared module constants in all files.
func AVPreferenceMain() -> AVPreferenceManager {
    AVPreferenceManager.mainManager()
}

func AppViewClientIsDarkMode() -> Bool {
    NSApp.effectiveAppearance.lk_isDarkMode
}

let appviewNodeImageMaxLengthInPx: Double = 16384


