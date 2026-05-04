import AppKit
import SwiftUI

class OverlayWindow: NSWindow {
    init(appState: AppState) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 180),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hasShadow = true
        // Не перехватываем фокус — курсор остаётся в нужном поле
        hidesOnDeactivate = false

        let view = OverlayView(appState: appState, onClose: { [weak self] in
            self?.hide()
        })
        contentView = NSHostingView(rootView: view)

        positionNearTop()
    }

    private func positionNearTop() {
        guard let screen = NSScreen.main else { return }
        let x = (screen.frame.width - 440) / 2
        let y = screen.frame.height * 0.68
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func show() {
        if !isVisible {
            positionNearTop()
        }
        orderFrontRegardless() // показываем без перехвата фокуса
    }

    func hide() {
        orderOut(nil)
    }

    override var canBecomeKey: Bool { false }  // не крадём фокус
    override var canBecomeMain: Bool { false }
}
