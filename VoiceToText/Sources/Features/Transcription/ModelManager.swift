import Foundation
import WhisperKit

// MARK: - Модели

enum LocalWhisperModel: String, CaseIterable, Identifiable {
    case tiny   = "openai_whisper-tiny"
    case base   = "openai_whisper-base"
    case small  = "openai_whisper-small"
    case medium = "openai_whisper-medium"
    case large  = "openai_whisper-large-v3"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny:   return "Tiny (~75 МБ)"
        case .base:   return "Base (~142 МБ)"
        case .small:  return "Small (~466 МБ)"
        case .medium: return "Medium (~1.5 ГБ)"
        case .large:  return "Large v3 (~3 ГБ)"
        }
    }

    var description: String {
        switch self {
        case .tiny:   return "Быстрая, низкое качество"
        case .base:   return "Быстрая, базовое качество"
        case .small:  return "Баланс скорости и качества"
        case .medium: return "Высокое качество"
        case .large:  return "Максимальное качество"
        }
    }
}

// MARK: - Статус модели

enum ModelDownloadStatus: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case loading
    case error(String)
}

// MARK: - ModelManager

@MainActor
class ModelManager: ObservableObject {
    static let shared = ModelManager()

    @Published var modelStatuses: [LocalWhisperModel: ModelDownloadStatus] = {
        var dict: [LocalWhisperModel: ModelDownloadStatus] = [:]
        for m in LocalWhisperModel.allCases { dict[m] = .notDownloaded }
        return dict
    }()

    private let fileManager = FileManager.default

    private init() {
        refreshDownloadedStatus()
    }

    // WhisperKit по умолчанию кладёт модели в ~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/
    private var modelsDirectory: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
    }

    func refreshDownloadedStatus() {
        for model in LocalWhisperModel.allCases {
            // Не сбрасывать статус если идёт загрузка
            if case .downloading = modelStatuses[model] { continue }

            let modelDir = modelsDirectory.appendingPathComponent(model.rawValue)
            // Считаем модель скачанной если папка существует и содержит хотя бы один .mlmodelc
            let hasFiles = (try? fileManager.contentsOfDirectory(atPath: modelDir.path))?.contains(where: { $0.hasSuffix(".mlmodelc") }) ?? false
            modelStatuses[model] = hasFiles ? .downloaded : .notDownloaded
        }
    }

    func isDownloaded(_ model: LocalWhisperModel) -> Bool {
        modelStatuses[model] == .downloaded
    }

    func downloadModel(_ model: LocalWhisperModel, onProgress: @escaping (Double, String) -> Void) async {
        modelStatuses[model] = .downloading(progress: 0)

        do {
            onProgress(0.05, "Подготовка загрузки \(model.displayName)...")

            let _ = try await WhisperKit(
                model: model.rawValue,
                verbose: false,
                logLevel: .none,
                prewarm: false,
                load: false,
                download: true
            )

            onProgress(0.5, "Загрузка файлов модели...")

            // Небольшая пауза для обновления UI
            try await Task.sleep(nanoseconds: 200_000_000)

            onProgress(1.0, "Готово")
            modelStatuses[model] = .downloaded
        } catch {
            modelStatuses[model] = .error(error.localizedDescription)
            onProgress(0.0, "Ошибка: \(error.localizedDescription)")
        }
    }
}
