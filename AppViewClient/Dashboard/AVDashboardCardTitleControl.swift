import AppKit

final class AVDashboardCardTitleControl: AVBaseControl {
    private(set) var iconImageView: NSImageView!
    private(set) var label: AVLabel!
    private(set) var disclosureImageView: NSImageView!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconImageView = NSImageView()
        addSubview(iconImageView)

        label = AVLabel()
        label.textColor = .labelColor
        label.font = NSFontMake(13)
        addSubview(label)

        disclosureImageView = NSImageView()
        addSubview(disclosureImageView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        lk(iconImageView).sizeToFit().verAlign().x(DashboardHorInset).offsetY(-1)
        lk(label).sizeToFit().verAlign().offsetY(-1).x(iconImageView.frame.maxX + 3)
        lk(disclosureImageView).sizeToFit().verAlign().x(label.frame.maxX + 3)
    }
}
