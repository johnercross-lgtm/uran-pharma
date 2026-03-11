import Foundation

enum LatinDeclension {
    private static let exceptions: [String: String] = [
        "aqua": "aquae",
        "spiritus": "spiritus",
        "sulfur": "sulfuris"
    ]

    static func toGenitive(_ text: String, extraRules: [LatinSuffixRule] = []) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return trimmed }

        if trimmed.contains("\"") || trimmed.contains("«") || trimmed.contains("»") {
            return trimmed
        }

        let sorted = extraRules.sorted { $0.suffixFrom.count > $1.suffixFrom.count }

        guard let re = try? NSRegularExpression(pattern: "\\p{L}+", options: []) else {
            return trimmed
        }

        var result = trimmed
        let fullRange = NSRange(result.startIndex..<result.endIndex, in: result)
        let matches = re.matches(in: result, options: [], range: fullRange)
        if matches.isEmpty { return trimmed }

        for m in matches.reversed() {
            guard let r = Range(m.range(at: 0), in: result) else { continue }
            let word = String(result[r])
            let replaced = declineWordToGenitive(word, extraRulesSorted: sorted)
            result.replaceSubrange(r, with: replaced)
        }

        return result
    }

    private static func declineWordToGenitive(_ word: String, extraRulesSorted: [LatinSuffixRule]) -> String {
        let lower = word.lowercased()
        if let ex = exceptions[lower] {
            return applyCasePattern(from: word, to: ex)
        }

        for rule in extraRulesSorted {
            let from = rule.suffixFrom.lowercased()
            if !from.isEmpty, lower.hasSuffix(from) {
                let cut = word.dropLast(from.count)
                let replaced = String(cut) + rule.suffixTo
                return replaced
            }
        }

        if lower.hasSuffix("a") {
            return String(word.dropLast(1)) + "ae"
        }

        if lower.hasSuffix("um") {
            return String(word.dropLast(2)) + "i"
        }

        if lower.hasSuffix("on") {
            return String(word.dropLast(2)) + "i"
        }

        if lower.hasSuffix("us") {
            return String(word.dropLast(2)) + "i"
        }

        if lower.hasSuffix("as") {
            return String(word.dropLast(2)) + "atis"
        }

        if lower.hasSuffix("is") {
            return String(word.dropLast(2)) + "idis"
        }

        if lower.hasSuffix("ex") {
            return String(word.dropLast(2)) + "icis"
        }

        if lower.hasSuffix("or") {
            return String(word.dropLast(2)) + "oris"
        }

        if lower.hasSuffix("o") {
            return String(word.dropLast(1)) + "onis"
        }

        if lower.hasSuffix("ine") {
            return String(word.dropLast(3)) + "ini"
        }

        if lower.hasSuffix("en") {
            return String(word.dropLast(2)) + "eni"
        }

        if lower.hasSuffix("ol") {
            return String(word.dropLast(2)) + "oli"
        }

        return word
    }

    private static func applyCasePattern(from original: String, to replacementLower: String) -> String {
        guard let first = original.first else { return replacementLower }
        if first.isUppercase {
            return replacementLower.prefix(1).uppercased() + replacementLower.dropFirst()
        }
        return replacementLower
    }
}
