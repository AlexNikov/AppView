//
//  AVExportAccessoryView.swift
//  AppView
//

import AppKit
import AppViewShared
import RxSwift

class AVExportAccessoryView: AVBaseView {
    var dataSize: UInt = 0 {
        didSet {
            sizeLabel.stringValue = String(format: NSLocalizedString("File Size: %.2f M", comment: ""), Double(dataSize) / 1_000_000.0)
        }
    }

    private var compressionLabel: AVLabel!
    private var compressionButton: NSPopUpButton!
    private var sizeLabel: AVLabel!
    private let compressionArray: [CGFloat] = [0.1, 0.3, 0.5, 0.75, 1.0]
    private let insetTop: CGFloat = 20
    private let insetBottom: CGFloat = 10
    private let buttonWidth: CGFloat = 150
    private let sizeLabelTop: CGFloat = 5
    private let disposeBag = DisposeBag()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        compressionLabel = AVLabel()
        compressionLabel.stringValue = NSLocalizedString("Image Quality:", comment: "")
        compressionLabel.font = NSFontMake(15)
        compressionLabel.alignment = .right
        addSubview(compressionLabel)

        compressionButton = NSPopUpButton()
        compressionButton.font = NSFontMake(14)
        compressionButton.target = self
        compressionButton.action = #selector(handleCompressionButton)
        compressionButton.addItems(withTitles: compressionArray.map { "\(Int($0 * 100))%" })
        addSubview(compressionButton)

        sizeLabel = AVLabel()
        sizeLabel.font = NSFontMake(13)
        sizeLabel.stringValue = NSLocalizedString("File Size", comment: "")
        sizeLabel.alignment = .right
        addSubview(sizeLabel)

        AVPreferenceMain().preferredExportCompressionObservable
            .distinctUntilChanged()
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { owner, compression in
                let shouldSelectIdx = owner.compressionArray.firstIndex { abs(compression - $0) < 0.05 } ?? 0
                if owner.compressionButton.indexOfSelectedItem != shouldSelectIdx {
                    owner.compressionButton.selectItem(at: shouldSelectIdx)
                }
            }
            .disposed(by: disposeBag)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        lk(compressionLabel).sizeToFit().y(insetTop).x(0)
        lk(compressionButton).width(buttonWidth).heightToFit().x(compressionLabel.frame.maxX).midY(compressionLabel.frame.midY)
        lk(sizeLabel).fullWidth().heightToFit().y(compressionButton.frame.maxY + sizeLabelTop)
    }

    @objc private func handleCompressionButton() {
        let compression = compressionArray[compressionButton.indexOfSelectedItem]
        AVPreferenceMain().preferredExportCompression = compression
    }

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        var size = limitedSize
        size.width = compressionLabel.sizeThatFits(NSSizeMax).width + buttonWidth
        size.height = insetTop + compressionLabel.sizeThatFits(NSSizeMax).height + sizeLabelTop +
            sizeLabel.sizeThatFits(NSSizeMax).height + insetBottom
        return size
    }
}
