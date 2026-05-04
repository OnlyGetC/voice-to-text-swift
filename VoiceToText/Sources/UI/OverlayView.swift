import SwiftUI
import AppKit

struct OverlayView: View {
    @ObservedObject var appState: AppState
    var onClose: () -> Void

    @State private var copied = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(borderColor.opacity(0.25), lineWidth: 1.2)
                )

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 18)
                    .padding(.top, 16)

                if appState.modelLoading {
                    loadingArea
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 18)
                } else {
                    contentArea
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                }
            }
        }
        .frame(width: 440, height: contentHeight)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.isRecording)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.isTranscribing)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.lastText)
        .shadow(color: .black.opacity(0.45), radius: 32, x: 0, y: 12)
    }

    // MARK: - Layout

    private var contentHeight: CGFloat {
        if appState.modelLoading  { return 180 }
        if appState.isRecording   { return 180 }
        if appState.isTranscribing { return 160 }
        if !appState.lastText.isEmpty { return 200 }
        return 160
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 8) {
            // Индикатор статуса
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 22, height: 22)
                    .scaleEffect(appState.isRecording ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: appState.isRecording)

                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
            }

            Text(statusText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))

            Spacer()

            closeButton
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(0.07))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if appState.isRecording {
            recordingArea
        } else if appState.isTranscribing {
            transcribingArea
        } else if !appState.lastText.isEmpty {
            resultArea
        } else {
            idleArea
        }
    }

    // Запись идёт — волна
    private var recordingArea: some View {
        VStack(spacing: 10) {
            WaveformView(level: appState.audioLevel, isRecording: true)
                .frame(height: 64)

            Text("Говорите... отпустите клавишу для завершения")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(.white.opacity(0.35))
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    // Обработка — пульсирующие точки
    private var transcribingArea: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.4))
                        .frame(width: 4, height: CGFloat.random(in: 12...36))
                        .animation(
                            .easeInOut(duration: 0.4)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.1),
                            value: appState.isTranscribing
                        )
                }
            }
            .frame(height: 40)

            Text("Распознавание речи...")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
        }
        .transition(.opacity)
    }

    // Результат — текст + кнопки
    private var resultArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Разделитель
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            // Текст результата
            Text(appState.lastText)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.combined(with: .move(edge: .bottom)))

            // Кнопки
            HStack(spacing: 8) {
                // Копировать
                Button(action: copyText) {
                    HStack(spacing: 5) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                        Text(copied ? "Скопировано" : "Копировать")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(copied ? .green : .white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(copied ? Color.green.opacity(0.15) : Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: copied)

                Spacer()

                Text("Вставлено автоматически")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // Ожидание
    private var idleArea: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic")
                .font(.system(size: 24, weight: .thin))
                .foregroundColor(.white.opacity(0.15))

            Text(idleHint)
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(.white.opacity(0.25))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .transition(.opacity)
    }

    // MARK: - Loading

    private var loadingArea: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.75)
                    .tint(.white.opacity(0.5))

                Text(appState.modelProgressLabel.isEmpty ? "Загрузка модели..." : appState.modelProgressLabel)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                Text("\(Int(appState.modelProgress * 100))%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.07)).frame(height: 4)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.85)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(appState.modelProgress), height: 4)
                        .animation(.easeInOut(duration: 0.3), value: appState.modelProgress)
                }
            }
            .frame(height: 4)

            Text("Первый запуск: загрузка модели с HuggingFace (~500 МБ)")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.white.opacity(0.2))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        if appState.isRecording    { return .red    }
        if appState.isTranscribing { return .orange }
        if appState.modelLoading   { return .yellow }
        if !appState.lastText.isEmpty { return Color(red: 0.3, green: 0.85, blue: 0.5) }
        return .white.opacity(0.4)
    }

    private var borderColor: Color {
        if appState.isRecording    { return .red    }
        if appState.isTranscribing { return .orange }
        return .white
    }

    private var statusText: String {
        if appState.modelLoading      { return "Загрузка модели..." }
        if appState.isRecording       { return appState.isVADMode ? "VAD · Запись" : "Запись" }
        if appState.isTranscribing    { return "Распознавание..." }
        if !appState.lastText.isEmpty { return "Готово" }
        if appState.isVADMode         { return "VAD · Слушаю" }
        return "Готово к записи"
    }

    private var idleHint: String {
        let ptt = HotkeyManager.shared.pttBinding.displayString
        return "Удерживайте \(ptt) для записи"
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.lastText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}
