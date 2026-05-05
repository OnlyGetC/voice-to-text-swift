import AppKit
import CoreGraphics

class OutputHandler {
    static let shared = OutputHandler()

    private var targetApp: NSRunningApplication?

    func rememberFocusedApp() {
        targetApp = NSWorkspace.shared.frontmostApplication
    }

    func send(text: String) {
        // Сохранить текущий буфер обмена
        let previousItems = NSPasteboard.general.pasteboardItems?.compactMap { item -> (types: [NSPasteboard.PasteboardType], data: [(NSPasteboard.PasteboardType, Data)])? in
            let types = item.types
            let data = types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let d = item.data(forType: type) else { return nil }
                return (type, d)
            }
            return (types: types, data: data)
        }

        copyToClipboard(text)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.targetApp?.activate(options: .activateIgnoringOtherApps)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.sendCmdV()

                // Восстановить буфер обмена через небольшую паузу
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.restoreClipboard(previousItems)
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func restoreClipboard(_ items: [(types: [NSPasteboard.PasteboardType], data: [(NSPasteboard.PasteboardType, Data)])]?) {
        guard let items, !items.isEmpty else {
            NSPasteboard.general.clearContents()
            return
        }
        NSPasteboard.general.clearContents()
        for item in items {
            let pbItem = NSPasteboardItem()
            for (type, data) in item.data {
                pbItem.setData(data, forType: type)
            }
            NSPasteboard.general.writeObjects([pbItem])
        }
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
