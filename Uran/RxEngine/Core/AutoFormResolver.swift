import Foundation

enum AutoFormResolver {
    nonisolated static func inferFormMode(draft: ExtempRecipeDraft) -> FormMode {
        let signa = draft.signa.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let semantics = SignaUsageAnalyzer.analyze(signa: signa)
        let ingredients = draft.ingredients

        if hasRectalOrVaginalMarker(in: signa) {
            return .suppositories
        }

        if ingredients.contains(where: isSemisolidBaseLike) {
            return .ointments
        }

        let hasLiquidComponent = hasLiquidTarget(draft) || ingredients.contains(where: isLiquidLike)
        let hasDropsMarker = draft.isOphthalmicDrops
            || semantics.hasDropsDose
            || ingredients.contains(where: isDropUnit)

        if hasDropsMarker && hasLiquidComponent && !semantics.dropMeasurementOnly {
            return .drops
        }

        if hasLiquidComponent {
            return .solutions
        }

        return .powders
    }

    nonisolated private static func hasLiquidTarget(_ draft: ExtempRecipeDraft) -> Bool {
        let explicitUnit = draft.targetUnit?.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let adUnit = draft.ingredients.last(where: { ($0.isAd || $0.isQS) && !$0.unit.rawValue.isEmpty })?.unit.rawValue
        let resolvedUnit = (explicitUnit?.isEmpty == false ? explicitUnit : adUnit)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return resolvedUnit == "ml" || resolvedUnit == "мл"
    }

    nonisolated private static func isDropUnit(_ ing: IngredientDraft) -> Bool {
        let unit = ing.unit.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return unit == "gtt" || unit == "gtts"
    }

    nonisolated private static func normalizedHay(_ ing: IngredientDraft) -> String {
        let a = (ing.refNameLatNom ?? ing.displayName).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = (ing.refInnKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return a + " " + b
    }

    nonisolated private static func isSemisolidBaseLike(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        let type = (ing.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if type == "base" {
            return true
        }
        let markers = ["vaselin", "lanolin", "ланол", "paraffin", "petrolat", "adeps", "macrogol", "peg", "unguent"]
        return markers.contains(where: { hay.contains($0) })
    }

    nonisolated private static func isLiquidLike(_ ing: IngredientDraft) -> Bool {
        if ing.role == .solvent {
            return true
        }

        let unit = ing.unit.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if unit == "ml" || unit == "мл" || ing.presentationKind == .solution || ing.presentationKind == .standardSolution {
            return true
        }

        let type = (ing.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let physicalState = (ing.refPhysicalState ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hay = normalizedHay(ing)

        let liquidTypes: Set<String> = [
            "solv",
            "solvent",
            "buffersolution",
            "standardsolution",
            "liquidstandard",
            "tincture",
            "extract",
            "syrup",
            "juice",
            "viscous liquid",
            "viscousliquid",
            "liquid",
            "alcoholic"
        ]
        if liquidTypes.contains(type) {
            return true
        }

        if physicalState.contains("liquid") || physicalState.contains("жидк") || physicalState.contains("рідк") {
            return true
        }

        return hay.contains("tinct")
            || hay.contains("настойк")
            || hay.contains("настоянк")
            || hay.contains("extract")
            || hay.contains("sirup")
            || hay.contains("syrup")
            || hay.contains("сироп")
            || hay.contains("succus")
            || hay.contains("juice")
            || hay.contains("glycer")
            || hay.contains("glycerin")
            || hay.contains("glycerinum")
            || hay.contains("глицерин")
            || hay.contains("гліцерин")
            || hay.contains("aqua")
            || hay.contains("water")
            || hay.contains("очищ")
    }
    nonisolated private static func hasRectalOrVaginalMarker(in signa: String) -> Bool {
        signa.contains("rect")
            || signa.contains("рект")
            || signa.contains("vagin")
            || signa.contains("вагин")
            || signa.contains("supp")
            || signa.contains("супп")
    }
}
