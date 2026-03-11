import Foundation

enum WaterSolubilityHeuristics {
    static func hasExplicitWaterSolubility(_ solubility: String?) -> Bool {
        let normalized = normalizedSolubility(solubility)
        guard !normalized.isEmpty else { return false }

        if waterSolubleMarkers.contains(where: normalized.contains) {
            return true
        }

        guard let ratio = waterRatioDenominator(in: normalized) else { return false }
        return ratio <= 50
    }

    static func isWaterInsolubleOrSparinglySoluble(_ solubility: String?) -> Bool {
        let normalized = normalizedSolubility(solubility)
        guard !normalized.isEmpty else { return false }
        if hasExplicitWaterSolubility(normalized) { return false }

        if waterInsolubleMarkers.contains(where: normalized.contains) {
            return true
        }

        guard let ratio = waterRatioDenominator(in: normalized) else { return false }
        return ratio >= 100
    }

    static func waterRatioDenominator(_ solubility: String?) -> Double? {
        let normalized = normalizedSolubility(solubility)
        guard !normalized.isEmpty else { return nil }
        return waterRatioDenominator(in: normalized)
    }

    static func normalizedSolubility(_ solubility: String?) -> String {
        (solubility ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func waterRatioDenominator(in normalized: String) -> Double? {
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        guard let match = ratioRegex.firstMatch(in: normalized, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: normalized)
        else {
            return nil
        }

        if containsOtherSolventMarkers(normalized) && !containsWaterMarkers(normalized) {
            return nil
        }

        let value = normalized[valueRange].replacingOccurrences(of: ",", with: ".")
        return Double(value)
    }

    private static func containsWaterMarkers(_ normalized: String) -> Bool {
        normalized.contains("вод")
            || normalized.contains("water")
    }

    private static func containsOtherSolventMarkers(_ normalized: String) -> Bool {
        otherSolventMarkers.contains(where: normalized.contains)
    }

    private static let ratioRegex = try! NSRegularExpression(
        pattern: #"1\s*:\s*([0-9]+(?:[.,][0-9]+)?)"#,
        options: []
    )

    private static let waterSolubleMarkers: [String] = [
        "розчинний у воді",
        "розчинна у воді",
        "легко розчинний у воді",
        "легко розчинна у воді",
        "дуже легко розчинний у воді",
        "дуже легко розчинна у воді",
        "повільно розчинний у воді",
        "повільно розчинна у воді",
        "змішується з водою",
        "змішується з водою у всіх співвідношеннях",
        "смешивается с водой",
        "смешивается с водой во всех соотношениях",
        "растворим в воде",
        "легко растворим в воде",
        "очень легко растворим в воде",
        "soluble in water",
        "freely soluble in water",
        "very soluble in water",
        "slowly soluble in water",
        "miscible with water",
        "water soluble"
    ]

    private static let waterInsolubleMarkers: [String] = [
        "нерозчинний у воді",
        "нерозчинна у воді",
        "практично нерозчинний у воді",
        "практично нерозчинна у воді",
        "малорозчинний у воді",
        "малорозчинна у воді",
        "погано розчинний у воді",
        "погано розчинна у воді",
        "дуже мало розчинний у воді",
        "дуже мало розчинна у воді",
        "нерастворим в воде",
        "практически нерастворим в воде",
        "малорастворим в воде",
        "плохо растворим в воде",
        "очень мало растворим в воде",
        "insoluble in water",
        "practically insoluble in water",
        "sparingly soluble in water",
        "slightly soluble in water",
        "very slightly soluble in water",
        "almost insoluble in water"
    ]

    private static let otherSolventMarkers: [String] = [
        "спирт",
        "alcohol",
        "ethanol",
        "гліцерин",
        "glycerin",
        "glycerol",
        "ефір",
        "ether",
        "хлороформ",
        "chloroform",
        "acetone",
        "ацетон",
        "oil",
        "oleum",
        "олія",
        "масл"
    ]
}
