import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var overlayWindow: OverlayWindow?
    var settingsWindow: NSWindow?
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupOverlayWindow()
        setupHotkeys()

        Task {
            await appState.transcriber.loadModel()
        }
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Показать", action: #selector(showOverlay), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Режим: PTT / VAD", action: #selector(toggleVAD), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Настройки...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func updateStatusIcon() {
        DispatchQueue.main.async {
            if self.appState.isRecording {
                self.statusItem.button?.title = "🔴"
            } else if self.appState.isTranscribing {
                self.statusItem.button?.title = "⏳"
            } else {
                self.statusItem.button?.title = "🎙"
            }
        }
    }

    // MARK: - Overlay Window

    private func setupOverlayWindow() {
        overlayWindow = OverlayWindow(appState: appState)
    }

    @objc func showOverlay() {
        overlayWindow?.show()
    }

    // MARK: - Settings Window

    @objc func showSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView(hotkeys: HotkeyManager.shared, appState: appState, onClose: { [weak self] in
            self?.settingsWindow?.orderOut(nil)
        })

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    // MARK: - Hotkeys

    private func setupHotkeys() {
        HotkeyManager.shared.onPTTPress = { [weak self] in
            self?.startRecording()
        }
        HotkeyManager.shared.onPTTRelease = { [weak self] in
            self?.stopRecording()
        }
        HotkeyManager.shared.onToggleVAD = { [weak self] in
            self?.toggleVAD()
        }
        HotkeyManager.shared.start()
    }

    // MARK: - Recording

    func startRecording() {
        guard appState.modelReady else { return }
        // Запомнить приложение с фокусом ДО показа overlay
        OutputHandler.shared.rememberFocusedApp()
        appState.isRecording = true
        updateStatusIcon()
        overlayWindow?.show()
        appState.recorder.startPTT()
    }

    func stopRecording() {
        appState.isRecording = false
        updateStatusIcon()
        appState.recorder.stopPTT { [weak self] audio in
            guard let self, let audio else { return }
            self.transcribe(audio: audio)
        }
    }

    func transcribe(audio: [Float]) {
        appState.isTranscribing = true
        updateStatusIcon()
        let language = appState.transcriptionLanguage
        let prompt = appState.promptEnabled ? appState.transcriptionPrompt : nil
        Task {
            let result = await appState.transcriber.transcribe(audio: audio, language: language, prompt: prompt)
            await MainActor.run {
                appState.isTranscribing = false
                self.updateStatusIcon()
                if let text = result {
                    appState.addHistory(text: text)
                    OutputHandler.shared.send(text: text)
                }
            }
        }
    }

    // MARK: - Actions

    @objc func toggleVAD() {
        appState.isVADMode.toggle()
        if appState.isVADMode {
            // Запомнить приложение при включении VAD
            OutputHandler.shared.rememberFocusedApp()
            appState.recorder.startVAD { [weak self] audio in
                self?.transcribe(audio: audio)
            }
        } else {
            appState.recorder.stopVAD()
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}
