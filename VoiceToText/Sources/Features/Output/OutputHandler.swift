import AppKit

class OutputHandler {
    static let shared = OutputHandler()

    private var targetAppName: String?

    // Путь к paste_helper.py рядом с .app bundle
    private var pasteHelperPath: String {
        let bundlePath = Bundle.main.bundlePath
        // dist/VoiceToText.app -> dist/paste_helper.py
        let dir = URL(fileURLWithPath: bundlePath)
            .deletingLastPathComponent()
        return dir.appendingPathComponent("paste_helper.py").path
    }

    func rememberFocusedApp() {
        let app = NSWorkspace.shared.frontmostApplication
        targetAppName = app?.localizedName
    }

    func send(text: String) {
        copyToClipboard(text: text)

        let appName = targetAppName

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Сначала активируем нужное приложение
            if let name = appName {
                let activateScript = "tell application \"\(name)\" to activate"
                var err: NSDictionary?
                NSAppleScript(source: activateScript)?.executeAndReturnError(&err)
            }

            // Небольшая пауза чтобы приложение получило фокус
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.pasteViaPython()
            }
        }
    }

    private func copyToClipboard(text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func pasteViaPython() {
        let helper = pasteHelperPath
        let python = "/usr/bin/python3"

        // Проверяем есть ли скрипт рядом с .app
        if FileManager.default.fileExists(atPath: helper) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: python)
            task.arguments = [helper]
            try? task.run()
            return
        }

        // Fallback: AppleScript
        let script = "tell application \"System Events\" to keystroke \"v\" using command down"
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if let e = err {
            print("[OutputHandler] ошибка вставки: \(e)")
        }
    }
}
