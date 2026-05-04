import AppKit

// MARK: - HotkeyBinding

struct HotkeyBinding: Codable, Equatable {
    // keyCode == 0xFFFF означает «только модификатор»
    var keyCode: UInt16
    var modifiers: UInt

    static let modifierOnly: UInt16 = 0xFFFF

    static let defaultPTT = HotkeyBinding(keyCode: modifierOnly, modifiers: NSEvent.ModifierFlags.control.rawValue)  // ⌃ Control
    static let defaultVAD = HotkeyBinding(keyCode: 0x60, modifiers: 0)  // F5

    var isModifierOnly: Bool { keyCode == Self.modifierOnly }

    var displayString: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃ Control") }
        if flags.contains(.option)  { parts.append("⌥ Option")  }
        if flags.contains(.shift)   { parts.append("⇧ Shift")   }
        if flags.contains(.command) { parts.append("⌘ Command") }
        if !isModifierOnly {
            parts.append(Self.keyName(for: keyCode))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " + ")
    }

    static func keyName(for keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7",
            0x63: "F3", 0x64: "F8", 0x65: "F1", 0x67: "F2",
            0x69: "F9", 0x6B: "F10", 0x6D: "F11", 0x6F: "F12",
            0x31: "Space", 0x24: "Return", 0x33: "Delete",
            0x35: "Esc",   0x30: "Tab",
            0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D",
            0x0E: "E", 0x03: "F", 0x05: "G", 0x04: "H",
            0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L",
            0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P",
            0x0C: "Q", 0x0F: "R", 0x01: "S", 0x11: "T",
            0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X",
            0x10: "Y", 0x06: "Z",
        ]
        return map[keyCode] ?? "Key(\(keyCode))"
    }
}

// MARK: - HotkeyManager

class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    @Published var pttBinding: HotkeyBinding { didSet { save(); restart() } }
    @Published var vadBinding: HotkeyBinding { didSet { save(); restart() } }

    var onPTTPress:   (() -> Void)?
    var onPTTRelease: (() -> Void)?
    var onToggleVAD:  (() -> Void)?

    private var keyMonitor:  Any?
    private var flagMonitor: Any?
    private var pttHeld = false
    // Отслеживаем предыдущие флаги для modifier-only хоткеев
    private var prevFlags: NSEvent.ModifierFlags = []

    private init() {
        pttBinding = Self.load(key: "pttBinding") ?? .defaultPTT
        vadBinding = Self.load(key: "vadBinding") ?? .defaultVAD
    }

    // MARK: - Start / Stop

    func start() {
        // Обычные клавиши
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleKey(event: event)
        }
        // Modifier-only хоткеи
        flagMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event: event)
        }
    }

    func stop() {
        if let m = keyMonitor  { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = flagMonitor { NSEvent.removeMonitor(m); flagMonitor = nil }
    }

    private func restart() {
        stop()
        start()
    }

    // MARK: - Key events

    private func handleKey(event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue

        // PTT (не modifier-only)
        if !pttBinding.isModifierOnly,
           event.keyCode == pttBinding.keyCode,
           mods == pttBinding.modifiers {
            if event.type == .keyDown && !pttHeld {
                pttHeld = true
                onPTTPress?()
            } else if event.type == .keyUp && pttHeld {
                pttHeld = false
                onPTTRelease?()
            }
            return
        }

        // VAD toggle (не modifier-only)
        if !vadBinding.isModifierOnly,
           event.keyCode == vadBinding.keyCode,
           mods == vadBinding.modifiers,
           event.type == .keyDown {
            onToggleVAD?()
        }
    }

    // MARK: - Flags events (modifier-only)

    private func handleFlags(event: NSEvent) {
        let cur = event.modifierFlags.intersection([.command, .option, .control, .shift])

        // PTT modifier-only: press
        if pttBinding.isModifierOnly {
            let target = NSEvent.ModifierFlags(rawValue: pttBinding.modifiers)
                .intersection([.command, .option, .control, .shift])
            let wasHeld = prevFlags.contains(target) && !target.isEmpty
            let isHeld  = cur.contains(target) && !target.isEmpty

            if isHeld && !wasHeld && !pttHeld {
                pttHeld = true
                onPTTPress?()
            } else if !isHeld && wasHeld && pttHeld {
                pttHeld = false
                onPTTRelease?()
            }
        }

        // VAD modifier-only: on press (leading edge)
        if vadBinding.isModifierOnly {
            let target = NSEvent.ModifierFlags(rawValue: vadBinding.modifiers)
                .intersection([.command, .option, .control, .shift])
            let wasHeld = prevFlags.contains(target) && !target.isEmpty
            let isHeld  = cur.contains(target) && !target.isEmpty
            if isHeld && !wasHeld {
                onToggleVAD?()
            }
        }

        prevFlags = cur
    }

    // MARK: - Persistence

    private func save() {
        if let d = try? JSONEncoder().encode(pttBinding) { UserDefaults.standard.set(d, forKey: "pttBinding") }
        if let d = try? JSONEncoder().encode(vadBinding) { UserDefaults.standard.set(d, forKey: "vadBinding") }
    }

    private static func load(key: String) -> HotkeyBinding? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeyBinding.self, from: d)
    }
}
