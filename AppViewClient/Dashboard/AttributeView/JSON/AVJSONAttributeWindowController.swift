import AppKit
import AppViewShared

final class AVJSONAttributeWindowController: AVWindowController {
    init() {
        let window = AVWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 200, height: 200)
        window.center()
        super.init(window: window)
        let vc = AVJSONAttributeViewController()
        window.contentView = vc.view
        contentViewController = vc
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
