import Foundation

public enum ScreenObservation {
    public static func message(from recognizedText: String) -> String {
        guard let firstLine = recognizedText
            .split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty })
        else {
            return "На экране текста не вижу."
        }

        return "Вижу: \(String(firstLine.prefix(56)))"
    }
}
