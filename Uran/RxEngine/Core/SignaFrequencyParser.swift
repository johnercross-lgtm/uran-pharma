import Foundation

enum SignaFrequencyParser {
    static func frequencyPerDay(from signa: String) -> Int? {
        let normalized = normalize(signa)
        guard !normalized.isEmpty else { return nil }

        // Numeric expressions: "3 р в день", "3 раза в день", "3 р/д", "3 times daily".
        let numericPatterns: [String] = [
            #"(\d+)\s*(?:раз(?:а|и)?|р\.?)\s*(?:в|на|/)?\s*(?:д(?:ень|ня)?|доб(?:у|а)?|сут(?:к(?:и|у)|ки)?)"#,
            #"(\d+)\s*р\.?\s*/\s*д(?:\.|об(?:у|а)?)?"#,
            #"(\d+)\s*(?:times?|x)\s*(?:a|per)?\s*(?:day|daily)"#
        ]
        for pattern in numericPatterns {
            if let value = firstCapturedInt(in: normalized, pattern: pattern) {
                return max(1, value)
            }
        }

        // Word expressions: "тричі на добу", "двічі в день", "once/twice/thrice daily".
        let wordPatterns: [(pattern: String, value: Int)] = [
            (#"\bодин(?:\s+раз)?\s*(?:в|на)?\s*(?:д(?:ень|ня)?|доб(?:у|а)?)\b"#, 1),
            (#"\bдвічі\s*(?:в|на)?\s*(?:д(?:ень|ня)?|доб(?:у|а)?)\b"#, 2),
            (#"\bтричі\s*(?:в|на)?\s*(?:д(?:ень|ня)?|доб(?:у|а)?)\b"#, 3),
            (#"\bonce\s*(?:a|per)?\s*(?:day|daily)\b"#, 1),
            (#"\btwice\s*(?:a|per)?\s*(?:day|daily)\b"#, 2),
            (#"\bthrice\s*(?:a|per)?\s*(?:day|daily)\b"#, 3)
        ]
        for item in wordPatterns {
            if normalized.range(of: item.pattern, options: .regularExpression) != nil {
                return item.value
            }
        }

        return nil
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "ʼ", with: "'")
            .replacingOccurrences(of: "’", with: "'")
    }

    private static func firstCapturedInt(in source: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, options: [], range: range), match.numberOfRanges >= 2 else {
            return nil
        }
        let capture = match.range(at: 1)
        guard capture.location != NSNotFound, let textRange = Range(capture, in: source) else { return nil }
        return Int(source[textRange])
    }
}
