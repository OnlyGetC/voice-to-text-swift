import AppKit

class OutputHandler {
    static let shared = OutputHandler()

    private var targetAppName: String?
    private var targetAppBundleId: String?

    func rememberFocusedApp() {
        let app = NSWorkspace.shared.frontmostApplication
        targetAppName = app?.localizedName
        targetAppBundleId = app?.bundleIdentifier
        print("[OutputHandler] запомнено приложение: \(targetAppName ?? "nil")")
    }

    func send(text: String) {
        copyToClipboard(text: text)

        guard let appName = targetAppName else {
            print("[OutputHandler] нет сохранённого приложения, вставляем как есть")
            pasteViaAppleScript(appName: nil)
            return
        }

        // AppleScript: активировать нужное приложение и вставить
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.pasteViaAppleScript(appName: appName)
        }
    }

    private func copyToClipboard(text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func pasteViaAppleScript(appName: String?) {
        let script: String
        if let name = appName {
            // Активируем конкретное приложение и вставляем в него
            script = """
            tell application "\(name)" to activate
            delay 0.1
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """
        } else {
            script = "tell application \"System Events\" to keystroke \"v\" using command down"
        }

        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let err = error {
            print("[OutputHandler] ошибка вставки: \(err)")
        }
    }
}
