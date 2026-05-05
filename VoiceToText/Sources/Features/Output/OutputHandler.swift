import AppKit
import CoreGraphics

class OutputHandler {
    static let shared = OutputHandler()

    private var targetApp: NSRunningApplication?
    private var previousApp: NSRunningApplication?
    private var observer: NSObjectProtocol?

    private init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let myBundle = Bundle.main.bundleIdentifier
            if activated?.bundleIdentifier != myBundle {
                self.previousApp = activated
            }
        }
    }

    func rememberFocusedApp() {
        // Используем предыдущее приложение — к моменту вызова фокус уже у нас
        targetApp = previousApp ?? NSWorkspace.shared.frontmostApplication
    }

    func send(text: String) {
        let previousString = NSPasteboard.general.string(forType: .string)
        copyToClipboard(text)

        // Активация и вставка — через AppleScript, без дополнительных задержек
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.sendCmdV()

            // Восстановить буфер обмена после вставки
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let prev = previousString {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(prev, forType: .string)
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func sendCmdV() {
        guard let app = targetApp else { return }

        let pid = app.processIdentifier
        app.activate(options: .activateIgnoringOtherApps)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let src = CGEventSource(stateID: .combinedSessionState)
            guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true),
                  let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) else { return }
            keyDown.flags = .maskCommand
            keyUp.flags   = .maskCommand
            keyDown.postToPid(pid)
            keyUp.postToPid(pid)
        }
    }
}
