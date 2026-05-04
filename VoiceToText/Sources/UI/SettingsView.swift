import SwiftUI
import AppKit

// MARK: - HotkeyRecorderButton

struct HotkeyRecorderButton: View {
    let label: String
    let isForPTT: Bool
    @Binding var binding: HotkeyBinding
    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @State private var flagMonitor: Any?

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .frame(minWidth: 130, alignment: .leading)

            Spacer()

            Button(action: toggleRecording) {
                Text(isRecording ? "Нажмите клавишу..." : binding.displayString)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(isRecording ? .orange : .white)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isRecording ? Color.orange.opacity(0.15) : Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isRecording ? Color.orange.opacity(0.5) : Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.15), value: isRecording)

            Button(action: resetToDefault) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(binding == defaultBinding ? 0.15 : 0.4))
            }
            .buttonStyle(.plain)
            .disabled(binding == defaultBinding)
            .help("Сбросить к значению по умолчанию")
        }
    }

    private var defaultBinding: HotkeyBinding {
        isForPTT ? .defaultPTT : .defaultVAD
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true

        // Обычные клавиши
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue
            if event.keyCode == 0x35 && mods == 0 { // Esc — отмена
                self.stopRecording()
                return nil
            }
            self.binding = HotkeyBinding(keyCode: event.keyCode, modifiers: mods)
            self.stopRecording()
            return nil
        }

        // Modifier-only: зажать только модификатор и отпустить
        var capturedFlags: NSEvent.ModifierFlags = []
        flagMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let cur = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if !cur.isEmpty {
                capturedFlags = cur
            } else if !capturedFlags.isEmpty {
                // Модификатор отпущен — записываем как modifier-only
                self.binding = HotkeyBinding(keyCode: HotkeyBinding.modifierOnly, modifiers: capturedFlags.rawValue)
                self.stopRecording()
            }
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = keyMonitor  { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = flagMonitor { NSEvent.removeMonitor(m); flagMonitor = nil }
    }

    private func resetToDefault() {
        binding = defaultBinding
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var hotkeys: HotkeyManager
    var onClose: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            VStack(spacing: 0) {
                // Заголовок
                HStack {
                    Text("Настройки")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.4))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                Divider().background(Color.white.opacity(0.08)).padding(.top, 14)

                VStack(alignment: .leading, spacing: 10) {
                    Text("ХОТКЕИ")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.bottom, 2)

                    HotkeyRecorderButton(label: "PTT (удерживать)", isForPTT: true,  binding: $hotkeys.pttBinding)
                    Divider().background(Color.white.opacity(0.05))
                    HotkeyRecorderButton(label: "Вкл/выкл VAD",     isForPTT: false, binding: $hotkeys.vadBinding)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Divider().background(Color.white.opacity(0.08)).padding(.top, 16)

                Text("Нажмите кнопку → нажмите клавишу (или зажмите модификатор и отпустите). Esc — отмена.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.25))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            }
        }
        .frame(width: 420, height: 240)
        .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 10)
    }
}
