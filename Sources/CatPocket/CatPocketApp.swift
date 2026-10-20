#if canImport(CatPocketCore)
import CatPocketCore
#endif
import SwiftUI

@main
struct CatPocketApp: App {
    @StateObject private var store = ModelStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onAppear { store.start() }
                .onChange(of: store.state) { _, state in
                    if state == .ready { AutoBench.runIfRequested(store: store) }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: ModelStore

    var body: some View {
        switch store.state {
        case .ready:
            TabView {
                ChatView()
                    .tabItem { Label("Чат", systemImage: "bubble.left.and.bubble.right") }
                BenchView()
                    .tabItem { Label("Бенч", systemImage: "gauge.with.dots.needle.33percent") }
            }
        case .missing:
            SetupView(title: "Модели пока нет", detail: "Qwen 3.5 2B, 1,3 ГБ. Скачивается один раз.") {
                Button("Скачать модель") { store.download() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("CatPocket.Download")
            }
        case .downloading(let progress):
            SetupView(title: "Скачиваю модель", detail: "\(Int(progress * 100))%") {
                ProgressView(value: progress).padding(.horizontal, 40)
            }
        case .loading:
            SetupView(title: "Загружаю модель", detail: "Веса открываются через mmap") {
                ProgressView()
            }
        case .failed(let message):
            SetupView(title: "Не получилось", detail: message) {
                Button("Попробовать снова") { store.start() }
            }
        }
    }
}

struct SetupView<Actions: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 16) {
            Text("🐈").font(.system(size: 64))
            Text(title).font(.title2.bold())
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            actions
        }
        .padding()
    }
}

/// `-autoBench <повторов>` в аргументах запуска: прогнать бенч без нажатий и
/// записать отчёт в Documents/bench.json. Так замер снимается с устройства
/// через `devicectl` без ручного прохода по интерфейсу.
enum AutoBench {
    @MainActor
    static func runIfRequested(store: ModelStore) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-autoBench"), let chat = store.chat else { return }
        let repetitions = arguments.indices.contains(flag + 1) ? Int(arguments[flag + 1]) ?? 5 : 5
        let loadSeconds = store.loadSeconds ?? 0
        Task.detached(priority: .userInitiated) {
            let started = Date()
            let output: [String: Any]
            do {
                let report = try PocketBench.run(on: chat, repetitions: repetitions)
                output = [
                    "device": deviceModel(),
                    "repetitions": repetitions,
                    "passRate": report.passRate,
                    "tokensPerSecond": report.tokensPerSecond,
                    "averagePrefillSeconds": report.averagePrefillSeconds,
                    "physicalFootprintMB": report.physicalFootprintMB,
                    "loadSeconds": loadSeconds,
                    "benchSeconds": Date().timeIntervalSince(started),
                    "cases": report.cases.map {
                        ["id": $0.id, "title": $0.title, "passed": $0.passed, "total": $0.total, "failures": $0.failures]
                    },
                ]
            } catch {
                output = ["error": String(describing: error)]
            }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: documents.appendingPathComponent("bench.json"))
            }
        }
    }

    static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
