import SwiftUI
import AppKit

// MARK: - HotkeyRecorderButton

struct HotkeyRecorderButton: View {
    let label: String
    @Binding var binding: HotkeyBinding
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 120, alignment: .leading)

            Spacer()

            Button(action: toggleRecording) {
                Text(isRecording ? "Нажмите клавишу..." : binding.displayString)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(isRecording ? .orange : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isRecording
                                  ? Color.orange.opacity(0.15)
                                  : Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isRecording
                                            ? Color.orange.opacity(0.5)
                                            : Color.white.opacity(0.12),
                                            lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.15), value: isRecording)

            if binding != defaultBinding {
                Button(action: resetToDefault) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
                .help("Сбросить к значению по умолчанию")
            }
        }
    }

    private var defaultBinding: HotkeyBinding {
        label.contains("PTT") ? .defaultPTT : .defaultVAD
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [self] event in
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue
            // Esc — отмена
            if event.keyCode == 0x35 && mods == 0 {
                stopRecording()
                return nil
            }
            binding = HotkeyBinding(keyCode: event.keyCode, modifiers: mods)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
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

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.top, 14)

                // Секция хоткеев
                VStack(alignment: .leading, spacing: 6) {
                    Text("ХОТКЕИ")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.bottom, 4)

                    HotkeyRecorderButton(
                        label: "PTT (удерживать)",
                        binding: $hotkeys.pttBinding
                    )

                    Divider()
                        .background(Color.white.opacity(0.05))
                        .padding(.vertical, 2)

                    HotkeyRecorderButton(
                        label: "Вкл/выкл VAD",
                        binding: $hotkeys.vadBinding
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.top, 16)

                // Подсказка
                Text("Нажмите на кнопку хоткея, затем нажмите нужную клавишу (с модификаторами или без). Esc — отмена.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.25))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            }
        }
        .frame(width: 380, height: 240)
        .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 10)
    }
}
