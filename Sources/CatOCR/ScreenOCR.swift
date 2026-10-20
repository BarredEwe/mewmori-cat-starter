import AppKit
import CoreGraphics
import Vision

public enum ScreenOCRError: Error, LocalizedError {
    case cannotLoadImage(URL)
    case cannotCreateScreenSnapshot
    case cannotCreateThumbnail

    public var errorDescription: String? {
        switch self {
        case .cannotLoadImage(let url):
            return "Не удалось открыть изображение: \(url.path)"
        case .cannotCreateScreenSnapshot:
            return "Не удалось получить снимок основного дисплея. Проверьте разрешение Screen Recording."
        case .cannotCreateThumbnail:
            return "Не удалось построить миниатюру экрана."
        }
    }
}

public struct RecognizedLine: Equatable {
    public let text: String
    /// Нормированные координаты с началом в левом верхнем углу.
    public let boundingBox: CGRect

    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

/// Дешёвый сторож перед повторным OCR из обоих докладов.
public enum ScreenThumbnail {
    public static let side = 32
    public static let tolerance = 3.0

    public static func pixels(in image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: side * side)
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw ScreenOCRError.cannotCreateThumbnail
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return pixels
    }

    public static func isSimilar(
        _ lhs: [UInt8],
        _ rhs: [UInt8],
        tolerance: Double = tolerance
    ) -> Bool {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return false }
        var sum = 0
        for index in lhs.indices {
            sum += abs(Int(lhs[index]) - Int(rhs[index]))
        }
        return Double(sum) / Double(lhs.count) <= tolerance
    }
}

public struct ScreenChangeDetector {
    private var previousThumbnail: [UInt8]?

    public init() {}

    public mutating func shouldRecognize(_ image: CGImage) throws -> Bool {
        let current = try ScreenThumbnail.pixels(in: image)
        defer { previousThumbnail = current }
        guard let previousThumbnail else { return true }
        return !ScreenThumbnail.isSimilar(previousThumbnail, current)
    }
}

/// Минимальная версия геометрического дайджеста со слайдов Podlodka.
public enum ScreenDigest {
    public static let maxCharacters = 600
    public static let maxLines = 8

    public static func make(from observations: [RecognizedLine]) -> String {
        let useful = ordered(observations)
            .filter { isUseful($0.text) }
            .prefix(maxLines)
        let heights = useful.map(\.boundingBox.height).sorted()
        let medianHeight = heights.isEmpty
            ? 0
            : (heights[(heights.count - 1) / 2] + heights[heights.count / 2]) / 2

        var remaining = maxCharacters
        var lines: [String] = []
        for observation in useful {
            let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count <= remaining else { break }
            remaining -= text.count
            let role = medianHeight > 0 && observation.boundingBox.height >= medianHeight * 1.25
                ? "heading"
                : "body"
            lines.append("  <line role=\"\(role)\">\(escaped(text))</line>")
        }

        return (["<screen_context>", "<section name=\"mainDisplay\">"]
            + lines
            + ["</section>", "</screen_context>"])
            .joined(separator: "\n")
    }

    private static let chromeLabels: Set<String> = [
        "file", "edit", "view", "window", "help", "search", "settings",
        "файл", "правка", "вид", "окно", "справка", "поиск", "настройки",
        "прокомментировать", "публикация…"
    ]

    private static func isUseful(_ value: String) -> Bool {
        let line = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.count >= 3, line.rangeOfCharacter(from: .letters) != nil else { return false }
        if chromeLabels.contains(line.lowercased()) { return false }
        let letters = line.filter(\.isLetter).count
        return Double(letters) / Double(line.count) >= 0.4
    }

    private static func ordered(_ observations: [RecognizedLine]) -> [RecognizedLine] {
        observations.sorted { lhs, rhs in
            let sameRow = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                <= max(lhs.boundingBox.height, rhs.boundingBox.height) * 0.5
            return sameRow
                ? lhs.boundingBox.minX < rhs.boundingBox.minX
                : lhs.boundingBox.minY < rhs.boundingBox.minY
        }
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

public enum ScreenOCR {
    public static func requestScreenCaptureAccess() -> Bool {
        CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
    }

    public static func recognizeText(
        in image: CGImage,
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate
    ) throws -> String {
        try recognizeLines(in: image, recognitionLevel: recognitionLevel)
            .map(\.text)
            .joined(separator: "\n")
    }

    public static func recognizeLines(
        in image: CGImage,
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate
    ) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])

        return request.results?.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return RecognizedLine(
                text: candidate.string,
                boundingBox: CGRect(
                    x: box.minX,
                    y: 1 - box.maxY,
                    width: box.width,
                    height: box.height
                )
            )
        } ?? []
    }

    public static func recognizeText(at url: URL) throws -> String {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            throw ScreenOCRError.cannotLoadImage(url)
        }
        return try recognizeText(in: cgImage)
    }

    public static func recognizeMainDisplay() throws -> String {
        try recognizeText(in: captureMainDisplay())
    }

    public static func captureMainDisplay() throws -> CGImage {
        guard let image = CGDisplayCreateImage(CGMainDisplayID()) else {
            throw ScreenOCRError.cannotCreateScreenSnapshot
        }
        return image
    }
}
