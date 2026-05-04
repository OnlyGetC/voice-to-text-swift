import AppKit

class OutputHandler {
    static let shared = OutputHandler()

    func send(text: String) {
        copyToClipboard(text: text)
        // Задержка: дать время overlay спрятаться и фокусу вернуться в нужное поле
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.paste()
        }
    }

    private func copyToClipboard(text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func paste() {
        // AppleScript — надёжнее CGEvent, работает во всех приложениях
        let script = "tell application \"System Events\" to keystroke \"v\" using command down"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let err = error {
            print("Ошибка вставки: \(err)")
        }
    }
}
