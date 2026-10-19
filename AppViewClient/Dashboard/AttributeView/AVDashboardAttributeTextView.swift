import AppKit
import AppViewShared
import RxSwift

final class AVDashboardAttributeTextView: AVDashboardAttributeView, NSTextViewDelegate {
    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    private var initialText = ""
    private var modifyDisposable: Disposable?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView = AVHelper.scrollableTextView()
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = DashboardCardControlCornerRadius
        textView = scrollView.documentView as? NSTextView ?? NSTextView()
        textView.font = NSFontMake(12)
        textView.backgroundColor = NSColor(named: "DashboardCardValueBGColor") ?? NSColor.labelColor
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.delegate = self
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        lk(scrollView).fullFrame()
    }

    override func renderWithAttribute() {
        super.renderWithAttribute()
        initialText = attribute?.value.dashboardStringValue ?? ""
        textView.string = initialText
        textView.isEditable = canEdit()
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        var size = limitedSize
        size.width -= textView.textContainerInset.width * 2
        let attributes = [NSAttributedString.Key.font: textView.font!]
        let attrString = NSAttributedString(string: textView.string, attributes: attributes)
        let rect = attrString.boundingRect(with: size, options: .usesLineFragmentOrigin)
        size.height = min(rect.height + textView.textContainerInset.height * 2, 80)
        return size
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSText.insertNewline(_:)) {
            window?.makeFirstResponder(nil)
            return true
        }
        return false
    }

    func textDidEndEditing(_ notification: Notification) {
        let expectedValue = textView.string
        if expectedValue == initialText { renderWithAttribute(); return }
        modifyDisposable = subscribeAttributeModification(newValue: .string(expectedValue), onSuccess: { [weak self] in self?.renderWithAttribute() })
    }
}
