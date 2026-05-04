import AppKit

// MARK: - HotkeyBinding

struct HotkeyBinding: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt  // NSEvent.ModifierFlags.rawValue

    static let defaultPTT     = HotkeyBinding(keyCode: 0x76, modifiers: 0)       // F4
    static let defaultVAD     = HotkeyBinding(keyCode: 0x60, modifiers: 0)       // F5

    var displayString: String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    static func keyName(for keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7",
            0x63: "F3", 0x64: "F8", 0x65: "F1", 0x67: "F2",
            0x69: "F9", 0x6B: "F10", 0x6D: "F11", 0x6F: "F12",
            0x31: "Space", 0x24: "Return", 0x33: "Delete",
            0x35: "Esc",  0x30: "Tab",
            0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D",
            0x0E: "E", 0x03: "F", 0x05: "G", 0x04: "H",
            0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L",
            0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P",
            0x0C: "Q", 0x0F: "R", 0x01: "S", 0x11: "T",
            0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X",
            0x10: "Y", 0x06: "Z",
        ]
        return map[keyCode] ?? "?\(keyCode)"
    }
}

// MARK: - HotkeyManager

class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    @Published var pttBinding: HotkeyBinding {
        didSet { save() }
    }
    @Published var vadBinding: HotkeyBinding {
        didSet { save() }
    }

    var onPTTPress: (() -> Void)?
    var onPTTRelease: (() -> Void)?
    var onToggleVAD: (() -> Void)?

    private var monitor: Any?
    private var pttHeld = false

    private init() {
        pttBinding = Self.load(key: "pttBinding") ?? .defaultPTT
        vadBinding = Self.load(key: "vadBinding") ?? .defaultVAD
    }

    // MARK: - Start / Stop

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handle(event: event)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    // MARK: - Handle

    private func handle(event: NSEvent) {
        let eventMods = event.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue

        // PTT
        if event.keyCode == pttBinding.keyCode && eventMods == pttBinding.modifiers {
            if event.type == .keyDown && !pttHeld {
                pttHeld = true
                onPTTPress?()
            } else if event.type == .keyUp && pttHeld {
                pttHeld = false
                onPTTRelease?()
            }
            return
        }

        // VAD toggle
        if event.keyCode == vadBinding.keyCode && eventMods == vadBinding.modifiers {
            if event.type == .keyDown {
                onToggleVAD?()
            }
            return
        }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(pttBinding) {
            UserDefaults.standard.set(data, forKey: "pttBinding")
        }
        if let data = try? JSONEncoder().encode(vadBinding) {
            UserDefaults.standard.set(data, forKey: "vadBinding")
        }
    }

    private static func load(key: String) -> HotkeyBinding? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    }
}
