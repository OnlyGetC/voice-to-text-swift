import AppKit

class OutputHandler {
    static let shared = OutputHandler()

    // Запомнить приложение с фокусом перед началом записи
    private var targetApp: NSRunningApplication?

    func rememberFocusedApp() {
        targetApp = NSWorkspace.shared.frontmostApplication
    }

    func send(text: String) {
        copyToClipboard(text: text)

        guard let app = targetApp else {
            pasteViaAppleScript()
            return
        }

        // Активируем нужное приложение, затем вставляем
        app.activate(options: .activateIgnoringOtherApps)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.pasteViaAppleScript()
        }
    }

    private func copyToClipboard(text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func pasteViaAppleScript() {
        let script = "tell application \"System Events\" to keystroke \"v\" using command down"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let err = error {
            print("Ошибка вставки: \(err)")
        }
    }
}
