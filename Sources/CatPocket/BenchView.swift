#if canImport(CatPocketCore)
import CatPocketCore
#endif
import SwiftUI

/// Тот же бенчмарк, что `swift run CatBench`, одной кнопкой на телефоне.
struct BenchView: View {
    @EnvironmentObject private var store: ModelStore
    @State private var report: PocketBench.Report?
    @State private var progress: (done: Int, total: Int)?
    @State private var error: String?
    @State private var repetitions = 5

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Stepper("Повторов на кейс: \(repetitions)", value: $repetitions, in: 1...20)
                    Button(progress == nil ? "Прогнать бенч" : "Идёт прогон…", action: run)
                        .disabled(progress != nil)
                        .accessibilityIdentifier("CatPocket.RunBench")
                    if let progress {
                        ProgressView(value: Double(progress.done), total: Double(progress.total))
                    }
                    if let error {
                        Text(error).foregroundStyle(.red)
                    }
                }

                if let report {
                    Section("Итог") {
                        Metric(title: "Проход", value: String(format: "%.0f%%", report.passRate * 100))
                            .accessibilityIdentifier("CatPocket.PassRate")
                        Metric(title: "Скорость", value: String(format: "%.1f ток/с", report.tokensPerSecond))
                        Metric(title: "Разбор промпта", value: String(format: "%.2f с", report.averagePrefillSeconds))
                        Metric(title: "Physical footprint", value: String(format: "%.0f МБ", report.physicalFootprintMB))
                        if let load = store.loadSeconds {
                            Metric(title: "Загрузка модели", value: String(format: "%.1f с", load))
                        }
                    }
                    Section("Кейсы") {
                        ForEach(report.cases) { result in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(result.title)
                                    Spacer()
                                    Text("\(result.passed)/\(result.total)")
                                        .monospacedDigit()
                                        .foregroundStyle(result.passed == result.total ? .green : .orange)
                                }
                                ForEach(result.failures.prefix(1), id: \.self) { failure in
                                    Text("✗ \(failure)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Бенч на устройстве")
        }
    }

    private func run() {
        guard let chat = store.chat else { return }
        let repetitions = repetitions
        error = nil
        progress = (0, PocketBench.cases.count * repetitions)
        Task.detached(priority: .userInitiated) {
            do {
                let report = try PocketBench.run(on: chat, repetitions: repetitions) { done, total in
                    Task { @MainActor in progress = (done, total) }
                }
                await MainActor.run {
                    self.report = report
                    progress = nil
                }
            } catch {
                await MainActor.run {
                    self.error = String(describing: error)
                    progress = nil
                }
            }
        }
    }
}

private struct Metric: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit().bold()
        }
    }
}
