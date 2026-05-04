import AppKit
import CoreGraphics

class OutputHandler {
    static let shared = OutputHandler()

    private var targetApp: NSRunningApplication?

    func rememberFocusedApp() {
        targetApp = NSWorkspace.shared.frontmostApplication
    }

    func send(text: String) {
        copyToClipboard(text)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.targetApp?.activate(options: .activateIgnoringOtherApps)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.sendCmdV()
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func sendCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)!
        let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)!
        keyDown.flags = .maskCommand
        keyUp.flags   = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
