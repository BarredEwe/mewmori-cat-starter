import CatPocketCore
import Foundation

// Тот же бенчмарк, что в iOS-приложении CatPocket, но из терминала:
//   swift run -c release CatBench /path/to/model.gguf [повторов]

let arguments = Array(CommandLine.arguments.dropFirst())
guard let modelPath = arguments.first else {
    print("Использование: swift run -c release CatBench /path/to/model.gguf [повторов]")
    exit(1)
}
let repetitions = arguments.dropFirst().first.flatMap(Int.init) ?? 5

let loadStart = Date()
let chat = try LlamaChat(modelPath: modelPath)
print("модель загружена за \(String(format: "%.1f", Date().timeIntervalSince(loadStart))) с")

let report = try PocketBench.run(on: chat, repetitions: repetitions)
for result in report.cases {
    print(String(format: "%2d/%-2d  %@", result.passed, result.total, result.title))
    for failure in result.failures.prefix(2) {
        print("        ✗ \(failure.prefix(120))")
    }
}
print(String(format: "\nпроход %.0f%%  ·  %.1f ток/с  ·  разбор промпта %.2f с  ·  footprint %.0f МБ",
             report.passRate * 100, report.tokensPerSecond, report.averagePrefillSeconds, report.physicalFootprintMB))
