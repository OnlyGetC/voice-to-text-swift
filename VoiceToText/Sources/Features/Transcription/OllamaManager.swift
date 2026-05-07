import Foundation
import AppKit

// MARK: - Статусы

enum OllamaInstallStatus {
    case notInstalled
    case installing(progress: Double, label: String)
    case installed
    case error(String)
}

enum OllamaServerStatus {
    case stopped
    case starting
    case running
    case stopping
    case error(String)
}

enum OllamaModelStatus {
    case notPulled
    case pulling(progress: Double)
    case ready
    case error(String)
}

// MARK: - OllamaManager

@MainActor
class OllamaManager: ObservableObject {
    static let shared = OllamaManager()

    @Published var installStatus: OllamaInstallStatus = .notInstalled
    @Published var serverStatus: OllamaServerStatus = .stopped
    @Published var modelStatus: OllamaModelStatus = .notPulled
    @Published var enabled: Bool = false {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "ollamaEnabled")
            if enabled { Task { await start() } }
            else { Task { await stop() } }
        }
    }

    // Модель по умолчанию для коррекции
    static let defaultModel = "llama3.2:1b"
    private let ollamaBinaryPath = "/usr/local/bin/ollama"
    private let ollamaAppPath = "/Applications/Ollama.app"
    private var serverProcess: Process?

    private init() {
        self.enabled = UserDefaults.standard.bool(forKey: "ollamaEnabled")
        refreshInstallStatus()
    }

    // MARK: - Статус установки

    func refreshInstallStatus() {
        if FileManager.default.fileExists(atPath: ollamaBinaryPath) ||
           FileManager.default.fileExists(atPath: ollamaAppPath) {
            installStatus = .installed
            checkModelStatus()
        } else {
            installStatus = .notInstalled
        }
    }

    var isInstalled: Bool {
        if case .installed = installStatus { return true }
        return false
    }

    // MARK: - Установка Ollama

    func install() async {
        installStatus = .installing(progress: 0.05, label: "Подготовка...")

        // Скачиваем официальный установщик Ollama для macOS
        let downloadURL = URL(string: "https://ollama.com/download/Ollama-darwin.zip")!
        let destZip = FileManager.default.temporaryDirectory.appendingPathComponent("Ollama-darwin.zip")

        do {
            installStatus = .installing(progress: 0.1, label: "Загрузка Ollama (~100 МБ)...")
            let (tmpURL, _) = try await URLSession.shared.download(from: downloadURL)
            try? FileManager.default.removeItem(at: destZip)
            try FileManager.default.moveItem(at: tmpURL, to: destZip)

            installStatus = .installing(progress: 0.7, label: "Распаковка...")
            let unzipResult = try await runShell("/usr/bin/unzip", args: ["-o", destZip.path, "-d", "/Applications"])
            guard unzipResult == 0 else {
                installStatus = .error("Ошибка распаковки")
                return
            }

            installStatus = .installing(progress: 0.9, label: "Настройка...")
            // Ollama.app устанавливает CLI в /usr/local/bin при первом запуске
            let openResult = try await runShell("/usr/bin/open", args: [ollamaAppPath])
            _ = openResult

            // Ждём появления бинаря
            for _ in 0..<20 {
                try await Task.sleep(nanoseconds: 500_000_000)
                if FileManager.default.fileExists(atPath: ollamaBinaryPath) { break }
            }

            installStatus = .installed
            checkModelStatus()
        } catch {
            installStatus = .error(error.localizedDescription)
        }
    }

    // MARK: - Сервер

    func start() async {
        guard isInstalled else { return }
        guard case .stopped = serverStatus else { return }

        serverStatus = .starting

        // Если Ollama.app установлен — открываем его (он сам запустит сервер)
        if FileManager.default.fileExists(atPath: ollamaAppPath) {
            let _ = try? await runShell("/usr/bin/open", args: ["-a", "Ollama"])
        } else {
            // Fallback: запустить ollama serve напрямую
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ollamaBinaryPath)
            process.arguments = ["serve"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            serverProcess = process
        }

        // Ждём пока сервер ответит
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if await pingServer() {
                serverStatus = .running
                // Если модель не скачана — скачать
                if case .notPulled = modelStatus { await pullModel() }
                return
            }
        }
        serverStatus = .error("Сервер не ответил за 10 секунд")
    }

    func stop() async {
        serverStatus = .stopping
        serverProcess?.terminate()
        serverProcess = nil

        // Закрыть Ollama.app если запущен
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.ollama.ollama").first {
            app.terminate()
        }
        serverStatus = .stopped
    }

    private func pingServer() async -> Bool {
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return false }
        var request = URLRequest(url: url, timeoutInterval: 2)
        request.httpMethod = "GET"
        return (try? await URLSession.shared.data(for: request)) != nil
    }

    // MARK: - Модель

    func checkModelStatus() {
        Task {
            guard await pingServer() else { return }
            let hasModel = await checkModelExists(OllamaManager.defaultModel)
            await MainActor.run {
                modelStatus = hasModel ? .ready : .notPulled
            }
        }
    }

    func pullModel() async {
        guard case .running = serverStatus else { return }
        modelStatus = .pulling(progress: 0)

        guard let url = URL(string: "http://localhost:11434/api/pull") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600

        let body = ["name": OllamaManager.defaultModel, "stream": true] as [String: Any]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        request.httpBody = data

        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: request)
            for try await line in bytes.lines {
                guard let lineData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                else { continue }

                if let status = json["status"] as? String, status == "success" {
                    modelStatus = .ready
                    return
                }
                // Прогресс: completed / total
                if let completed = json["completed"] as? Double,
                   let total = json["total"] as? Double, total > 0 {
                    modelStatus = .pulling(progress: completed / total)
                }
            }
            modelStatus = .ready
        } catch {
            modelStatus = .error(error.localizedDescription)
        }
    }

    private func checkModelExists(_ name: String) async -> Bool {
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return false }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]]
        else { return false }
        return models.contains { ($0["name"] as? String)?.hasPrefix(name.components(separatedBy: ":").first ?? name) == true }
    }

    // MARK: - Shell helper

    @discardableResult
    private func runShell(_ path: String, args: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
