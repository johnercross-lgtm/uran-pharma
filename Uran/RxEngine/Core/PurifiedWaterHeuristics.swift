import Foundation

enum PurifiedWaterHeuristics {
    static func isPurifiedWater(_ ingredient: IngredientDraft) -> Bool {
        isPurifiedWaterCandidate(
            "\(ingredient.displayName) \(ingredient.refNameLatNom ?? "") \(ingredient.refInnKey ?? "")"
        )
    }

    static func isPurifiedWater(_ substance: ExtempSubstance) -> Bool {
        isPurifiedWaterCandidate(
            "\(substance.innKey) \(substance.nameLatNom) \(substance.nameRu)"
        )
    }

    static func isPurifiedWaterCandidate(_ raw: String) -> Bool {
        let hay = normalize(raw)
        if hay.isEmpty { return false }

        if hay == "aqua" || hay == "aquae" { return true }
        if hay == "water" || hay == "purified water" || hay == "water purified" { return true }
        if hay == "вода" || hay == "вода очищенная" || hay == "вода очищена" { return true }

        let hayNoSpaces = hay.replacingOccurrences(of: " ", with: "")

        let hasLatinAqua = hay.contains("aqua") || hay.contains("aquae")
        if hasLatinAqua && hay.contains("purificat") { return true }
        if hayNoSpaces.contains("aqpurif") { return true }

        if hay.contains("purified water") || hay.contains("water purified") { return true }

        let hasCyrillicWater = hay.contains("вода") || hay.contains("воды") || hay.contains("води")
        if hasCyrillicWater && hay.contains("очищ") { return true }
        if hay.contains("очищенная вода") || hay.contains("очищена вода") { return true }
        if hay.contains("очищеної води") || hay.contains("вода очищеної") { return true }

        return false
    }

    private static func normalize(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "[^\\p{L}\\p{N}\\s]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
