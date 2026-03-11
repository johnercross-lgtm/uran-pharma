import SwiftUI

struct PpkPrettyText: View {
    let text: String

    var body: some View {
        Text(attributedText)
            .font(.system(size: 13))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedText: AttributedString {
        let lines = text.components(separatedBy: .newlines)
        var result = AttributedString()

        for (index, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                var line = AttributedString(rawLine)
                if isPrimaryHeader(trimmed) {
                    line.font = .system(size: 15, weight: .bold)
                } else if isSecondaryHeader(trimmed) {
                    line.font = .system(size: 13, weight: .semibold)
                } else if isListItem(trimmed) {
                    line.font = .system(size: 13, weight: .regular, design: .monospaced)
                } else {
                    line.font = .system(size: 13, weight: .regular)
                }
                SubstanceTokenHighlighter.apply(to: &line, source: rawLine)
                result.append(line)
            }

            if index < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }

        return result
    }

    private func isPrimaryHeader(_ line: String) -> Bool {
        line == "ППК"
            || line.hasPrefix("Зворотний бік")
            || line.hasPrefix("Лицьовий бік")
            || line == "Контроль:"
            || line == "Контроль"
    }

    private func isSecondaryHeader(_ line: String) -> Bool {
        line.hasSuffix(":")
            || line.hasPrefix("Гілка:")
            || line.hasPrefix("Блоки:")
    }

    private func isListItem(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        return first.isNumber || first == "•"
    }
}
