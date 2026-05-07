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

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue
            if event.keyCode == 0x35 && mods == 0 {
                self.stopRecording()
                return nil
            }
            self.binding = HotkeyBinding(keyCode: event.keyCode, modifiers: mods)
            self.stopRecording()
            return nil
        }

        var capturedFlags: NSEvent.ModifierFlags = []
        flagMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let cur = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if !cur.isEmpty {
                capturedFlags = cur
            } else if !capturedFlags.isEmpty {
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
    @ObservedObject var appState: AppState
    var onClose: () -> Void
    var onDonate: () -> Void

    @ObservedObject private var modelManager = ModelManager.shared
    @State private var downloadingModel: LocalWhisperModel? = nil
    @State private var downloadProgress: Double = 0
    @State private var downloadLabel: String = ""
    @State private var apiKeyInput: String = ""
    @State private var showApiKey: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            ScrollView {
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

                    // MARK: Секция хоткеев
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("ХОТКЕИ")
                        HotkeyRecorderButton(label: "PTT (удерживать)", isForPTT: true,  binding: $hotkeys.pttBinding)
                        Divider().background(Color.white.opacity(0.05))
                        HotkeyRecorderButton(label: "Вкл/выкл VAD",     isForPTT: false, binding: $hotkeys.vadBinding)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    Divider().background(Color.white.opacity(0.08)).padding(.top, 16)

                    // MARK: Секция модели
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("МОДЕЛЬ")

                        // Переключатель Local / Cloud
                        HStack(spacing: 8) {
                            providerTab(label: "Локальная", isSelected: appState.transcriptionProvider == .local) {
                                appState.transcriptionProvider = .local
                            }
                            providerTab(label: "Облако (API)", isSelected: appState.transcriptionProvider == .cloud) {
                                appState.transcriptionProvider = .cloud
                            }
                        }

                        if appState.transcriptionProvider == .local {
                            localModelSection
                        } else {
                            cloudModelSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    Divider().background(Color.white.opacity(0.08)).padding(.top, 16)

                    // MARK: Секция языка
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader("ЯЗЫК ТРАНСКРИБАЦИИ")

                        HStack {
                            Text("Язык")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Picker("", selection: $appState.transcriptionLanguage) {
                                ForEach(WhisperLanguage.all) { lang in
                                    Text(lang.name).tag(lang.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 200)
                            .colorScheme(.dark)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    Divider().background(Color.white.opacity(0.08)).padding(.top, 16)

                    // MARK: Секция промта
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            sectionHeader("ПОДСКАЗКА МОДЕЛИ")
                            Spacer()
                            Toggle("", isOn: $appState.promptEnabled)
                                .toggleStyle(.switch)
                                .scaleEffect(0.75)
                                .tint(.blue)
                        }

                        if appState.promptEnabled {
                            TextEditor(text: $appState.transcriptionPrompt)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                                .scrollContentBackground(.hidden)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(8)
                                .frame(height: 72)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )

                            Text("Помогает модели правильно распознавать термины и смешанный текст (ru+en).")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(.white.opacity(0.25))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    Divider().background(Color.white.opacity(0.08)).padding(.top, 16)

                    // Подсказка по хоткеям
                    Text("Нажмите кнопку → нажмите клавишу (или зажмите модификатор и отпустите). Esc — отмена.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.white.opacity(0.25))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                    // Кнопка Поддержать
                    Button(action: onDonate) {
                        HStack(spacing: 6) {
                            Text("🪙")
                            Text("Поддержать автора")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                    .padding(.bottom, 18)
                }
            }
        }
        .frame(width: 420, height: 620)
        .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 10)
        .onAppear {
            modelManager.refreshDownloadedStatus()
            loadApiKeyInput()
        }
    }

    // MARK: - Локальные модели

    private var localModelSection: some View {
        VStack(spacing: 6) {
            ForEach(LocalWhisperModel.allCases) { model in
                localModelRow(model)
            }

            if let dm = downloadingModel {
                VStack(spacing: 4) {
                    HStack {
                        Text(downloadLabel)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text("\(Int(downloadProgress * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    ProgressView(value: downloadProgress)
                        .tint(.blue)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(2)
                }
                .padding(.top, 4)
                .id(dm.rawValue)
            }
        }
    }

    private func localModelRow(_ model: LocalWhisperModel) -> some View {
        let status = modelManager.modelStatuses[model] ?? .notDownloaded
        let isSelected = appState.transcriptionProvider == .local && appState.selectedLocalModel == model
        let isDownloaded = status == .downloaded
        let isDownloading = downloadingModel == model

        return HStack(spacing: 10) {
            // Чекбокс / статус
            ZStack {
                Circle()
                    .fill(isSelected ? Color.blue : Color.white.opacity(0.06))
                    .frame(width: 18, height: 18)
                if isSelected {
                    Circle()
                        .fill(.white)
                        .frame(width: 7, height: 7)
                }
            }
            .onTapGesture {
                if isDownloaded && !isDownloading {
                    appState.switchLocalModel(to: model)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(isDownloaded ? .white.opacity(0.85) : .white.opacity(0.35))
                    if appState.isModelSwitching && isSelected {
                        Text("загрузка...")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(.blue.opacity(0.7))
                    }
                }
                Text(model.description)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.25))
            }

            Spacer()

            // Кнопка действия
            if isDownloading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 60)
            } else if isDownloaded {
                if isSelected {
                    Text("Активна")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.green.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                } else {
                    Button("Выбрать") {
                        appState.switchLocalModel(to: model)
                    }
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.blue.opacity(0.8))
                    .buttonStyle(.plain)
                }
            } else {
                Button("Скачать") {
                    startDownload(model)
                }
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.07))
                .cornerRadius(6)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.blue.opacity(0.08) : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.blue.opacity(0.2) : Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }

    private func startDownload(_ model: LocalWhisperModel) {
        guard downloadingModel == nil else { return }
        downloadingModel = model
        downloadProgress = 0
        downloadLabel = "Подготовка..."
        Task {
            await ModelManager.shared.downloadModel(model) { progress, label in
                DispatchQueue.main.async {
                    self.downloadProgress = progress
                    self.downloadLabel = label
                }
            }
            DispatchQueue.main.async {
                self.downloadingModel = nil
                self.modelManager.refreshDownloadedStatus()
            }
        }
    }

    // MARK: - Облачные модели

    private var cloudModelSection: some View {
        VStack(spacing: 10) {
            // Выбор провайдера
            VStack(spacing: 6) {
                ForEach(CloudProvider.allCases) { provider in
                    cloudProviderRow(provider)
                }
            }

            Divider().background(Color.white.opacity(0.06))

            // Поле API-ключа
            VStack(alignment: .leading, spacing: 6) {
                Text("API-ключ для \(appState.selectedCloudProvider.displayName)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))

                HStack(spacing: 8) {
                    Group {
                        if showApiKey {
                            TextField("sk-...", text: $apiKeyInput)
                        } else {
                            SecureField("sk-...", text: $apiKeyInput)
                        }
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .colorScheme(.dark)

                    Button(action: { showApiKey.toggle() }) {
                        Image(systemName: showApiKey ? "eye.slash" : "eye")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .buttonStyle(.plain)

                    Button("Сохранить") {
                        saveApiKey()
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.blue.opacity(0.8))
                    .buttonStyle(.plain)
                }

                Text("Ключ хранится в Keychain, не покидает устройство.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
    }

    private func cloudProviderRow(_ provider: CloudProvider) -> some View {
        let isSelected = appState.selectedCloudProvider == provider

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.blue : Color.white.opacity(0.06))
                    .frame(width: 18, height: 18)
                if isSelected {
                    Circle()
                        .fill(.white)
                        .frame(width: 7, height: 7)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                Text(provider.description)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
            }

            Spacer()

            let hasKey = KeychainHelper.load(key: provider.keychainKey) != nil
            if hasKey {
                Text("ключ задан")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.green.opacity(0.6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.blue.opacity(0.08) : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.blue.opacity(0.2) : Color.white.opacity(0.05), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            appState.selectedCloudProvider = provider
            loadApiKeyInput()
        }
    }

    // MARK: - API Key helpers

    private func loadApiKeyInput() {
        apiKeyInput = KeychainHelper.load(key: appState.selectedCloudProvider.keychainKey) ?? ""
    }

    private func saveApiKey() {
        if apiKeyInput.isEmpty {
            KeychainHelper.delete(key: appState.selectedCloudProvider.keychainKey)
        } else {
            KeychainHelper.save(key: appState.selectedCloudProvider.keychainKey, value: apiKeyInput)
        }
    }

    // MARK: - Helpers

    private func providerTab(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .rounded))
                .foregroundColor(isSelected ? .white : .white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.blue.opacity(0.25) : Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.blue.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.3))
    }
}
