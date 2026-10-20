#if canImport(CatPocketCore)
import CatPocketCore
#endif
import Foundation

/// Где лежит модель и в каком она состоянии.
///
/// Модель не вшита в приложение: 1,3 ГБ GGUF скачиваются один раз в
/// Application Support и дальше открываются через mmap.
@MainActor
final class ModelStore: NSObject, ObservableObject {
    enum State: Equatable {
        case missing
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    static let fileName = "Qwen3.5-2B-UD-Q4_K_XL.gguf"
    static let remoteURL = URL(string: "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/\(fileName)")!

    @Published private(set) var state: State = .missing
    @Published private(set) var loadSeconds: Double?
    private(set) var chat: LlamaChat?
    private var session: URLSession?

    var localURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(Self.fileName)
    }

    func start() {
        if FileManager.default.fileExists(atPath: localURL.path) {
            load()
        } else {
            state = .missing
        }
    }

    func download() {
        state = .downloading(0)
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        self.session = session
        session.downloadTask(with: Self.remoteURL).resume()
    }

    func load() {
        state = .loading
        let path = localURL.path
        Task.detached(priority: .userInitiated) {
            let start = Date()
            do {
                let chat = try LlamaChat(modelPath: path)
                let seconds = Date().timeIntervalSince(start)
                await MainActor.run {
                    self.chat = chat
                    self.loadSeconds = seconds
                    self.state = .ready
                }
            } catch {
                await MainActor.run { self.state = .failed(String(describing: error)) }
            }
        }
    }
}

extension ModelStore: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        MainActor.assumeIsolated { self.state = .downloading(progress) }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Временный файл живёт только до конца этого вызова, переносим сразу.
        let destination = MainActor.assumeIsolated { self.localURL }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            MainActor.assumeIsolated { self.load() }
        } catch {
            MainActor.assumeIsolated { self.state = .failed(error.localizedDescription) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        MainActor.assumeIsolated { self.state = .failed(error.localizedDescription) }
    }
}
