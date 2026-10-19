import AppKit
import AppViewShared

class AVDashboardAttributeStringArrayView: AVDashboardAttributeView {
    private var labels: [AVLabel] = []
    private var sepLayers: [CALayer] = []
    private var danceButton: NSButton?
    private let labelsVerInterSpace: CGFloat = 10

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        labels = []
        sepLayers = []
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        for (idx, obj) in labels.enumerated() {
            let prevLabel = idx > 0 ? labels[idx - 1] : nil
            lk(obj).fullFrame().heightToFit().y(prevLabel.map { $0.frame.maxY + labelsVerInterSpace } ?? 0)
            if idx > 0, sepLayers.indices.contains(idx - 1) {
                lk(sepLayers[idx - 1]).fullFrame().height(1).y(obj.frame.origin.y - labelsVerInterSpace / 2 + 1)
            }
        }
        if danceButton?.isVisible == true {
            lk(danceButton!).width(150).horAlign().height(25).bottom(0)
        }
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        var height = labels.reduce(0) { acc, obj in
            var h = acc + obj.sizeThatFits(limitedSize).height
            if acc > 0 { h += labelsVerInterSpace }
            return h
        }
        if danceButton?.isVisible == true {
            height += 35
        }
        return NSSize(width: limitedSize.width, height: height)
    }

    func stringList(with attribute: AppViewAttribute) -> [String] {
        assertionFailure("should implement by subclass")
        return []
    }

    override func renderWithAttribute() {
        guard let attribute else { return }
        let lists = stringList(with: attribute)
        labels = labels.appview_resize(
            count: lists.count,
            add: { [weak self] (_: UInt) in
                let label = AVLabel()
                label.lineBreakStrategy = []
                label.isSelectable = true
                label.allowsEditingTextAttributes = true
                self?.addSubview(label)
                return label
            },
            remove: { _, label in label.removeFromSuperview() },
            doNext: { idx, label in
                label.attributedStringValue = AVAttrString(lists[Int(idx)], style: .dashboardListItem).build()
            }
        )

        if lists.count > 1 {
            sepLayers = (lists.count - 1).appview_resize(
                count: lists.count - 1,
                add: { [weak self] (_: UInt) in
                    let layer = CALayer()
                    layer.appview_removeImplicitAnimations()
                    self?.layer?.addSublayer(layer)
                    return layer
                },
                remove: { _, layer in layer.removeFromSuperlayer() },
                doNext: { _, _ in }
            )
            updateColors()
        } else {
            sepLayers.forEach { $0.removeFromSuperlayer() }
            sepLayers = []
        }

        danceButton?.isHidden = true
        if attribute.identifier == AppViewAttr_Class_Class_Class {
            var danceSource = attribute.targetDisplayItem?.danceuiSource
            if danceSource == nil {
                danceSource = attribute.targetDisplayItem?.customInfo?.danceuiSource
            }
            if danceSource != nil {
                addDanceButtonIfNeeded()
                danceButton?.title = NSLocalizedString("Navigate…", comment: "")
                danceButton?.isHidden = false
            }
        }
        needsLayout = true
    }

    override func updateColors() {
        super.updateColors()
        let color = AppViewClientIsDarkMode() ? SeparatorDarkModeColor.cgColor : SeparatorLightModeColor.cgColor
        sepLayers.forEach { $0.backgroundColor = color }
    }

    private func addDanceButtonIfNeeded() {
        guard danceButton == nil else { return }
        let button = NSButton.lk_normalButton(withTitle: "", target: self, action: #selector(handleDanceButton))
        button.font = NSFontMake(12)
        addSubview(button)
        danceButton = button
    }

    @objc private func handleDanceButton() {
        guard let attribute else { return }
        var json = attribute.targetDisplayItem?.danceuiSource
        if json == nil {
            json = attribute.targetDisplayItem?.customInfo?.danceuiSource
        }
        if let json {
            DanceScriptManager.shared.handleText(json)
        }
    }
}
