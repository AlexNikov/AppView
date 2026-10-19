import AppKit
import AppViewShared
import RxSwift

final class AVDashboardAttributeOpenImageView: AVDashboardAttributeView {
    private var control: AVTextControl!
    private let disposeBag = DisposeBag()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.cornerRadius = DashboardCardControlCornerRadius
        borderColors = AVColorsCombine(AppViewColorMake(181, 181, 181), AppViewColorMake(83, 83, 83))

        control = AVTextControl()
        control.adjustAlphaWhenClick = true
        control.label.stringValue = NSLocalizedString("Open Image with Preview…", comment: "")
        control.label.font = NSFontMake(11)
        control.addTarget(self, clickAction: #selector(handleClick))
        addSubview(control)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func layout() {
        super.layout()
        lk(control).fullFrame()
    }

    override func renderWithAttribute() {}

    override func sizeThatFits(_ limitedSize: NSSize) -> NSSize {
        NSSize(width: limitedSize.width, height: AVNumberInputHorizontalHeight)
    }

    @objc private func handleClick() {
        guard case .customObject(let rawValue)? = attribute?.value,
              let imageViewOidNum = rawValue as? NSNumber else {
            AlertError(AVAppViewClientErrors.inner, window)
            assertionFailure()
            return
        }
        let imageViewOid = imageViewOidNum.uintValue
        guard dashboardViewController?.isStaticMode == true else {
            AlertErrorText(
                NSLocalizedString("The feature is not available in current mode.", comment: ""),
                NSLocalizedString("You must connect AppView with target iOS app before using this feature.", comment: ""),
                window
            )
            return
        }
        guard let app = AVAppsManager.sharedInstance.inspectingApp else {
            AlertError(AVAppViewClientErrors.noConnect, window)
            return
        }
        AppViewRACSignalRx.observeMainThread(app.fetchImage(withImageViewOid: imageViewOid))
            .subscribe(with: self, onSuccess: { owner, imageData in
                guard !imageData.isEmpty else {
                    AlertErrorText(
                        NSLocalizedString("Operation failed. The image property value of selected UIImageView is nil.", comment: ""),
                        "",
                        owner.window
                    )
                    return
                }
                let fileName = String(format: "%.0f", Date().timeIntervalSince1970)
                let filePath = (NSTemporaryDirectory() as NSString).appendingPathComponent("AppView_UIImageView_\(fileName).png")
                do {
                    try imageData.write(to: URL(fileURLWithPath: filePath))
                } catch {
                    assertionFailure()
                    AlertError(error as NSError, owner.window)
                    return
                }
                let previewURL = URL(fileURLWithPath: "/System/Applications/Preview.app")
                NSWorkspace.shared.open([URL(fileURLWithPath: filePath)], withApplicationAt: previewURL, configuration: NSWorkspace.OpenConfiguration())
                if AVHelper.sharedInstance.tempImageFiles == nil {
                    AVHelper.sharedInstance.tempImageFiles = NSMutableArray()
                }
                AVHelper.sharedInstance.tempImageFiles?.add(filePath)
            }, onFailure: { owner, error in
                AlertError(error as NSError, owner.window)
            })
            .disposed(by: disposeBag)
    }
}
