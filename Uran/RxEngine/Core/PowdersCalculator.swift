import Foundation

struct PowderComponentResult: Identifiable, Hashable {
    let id: UUID
    let name: String
    let totalG: Double
    let perDoseG: Double
    let isSugarCarrier: Bool
    let isActive: Bool
    let isColoring: Bool
}

struct PowdersCalculationResult: Hashable {
    let n: Int
    let mode: PowderMassMode
    let components: [PowderComponentResult]
    let nonAdMassG: Double
    let adBaseName: String?
    let adTargetTotalG: Double?
    let adFillerG: Double?
    let autoFillG: Double
    let totalMassG: Double
    let perDoseG: Double
    let tinyActivesTotalG: Double
    let triturationSugarNeedG: Double
    let sugarCarrierTotalG: Double
    let canBuildTrituration: Bool
    let allowedDeviationPercent: Double
}

enum PowdersCalculator {
    static func calculate(draft: ExtempRecipeDraft) -> PowdersCalculationResult {
        let n = max(1, draft.numero ?? 1)
        let mode = draft.powderMassMode

        let components: [PowderComponentResult] = draft.ingredients.compactMap { ing in
            guard !ing.isQS, !ing.isAd else { return nil }
            guard ing.unit.rawValue == "g" else { return nil }
            let raw = max(0, ing.amountValue)
            guard raw > 0 else { return nil }

            let total = resolvedTotalMassG(rawValue: raw, scope: ing.scope, n: n, mode: mode)
            let perDose = total / Double(n)
            let hay = normalizedHay(ing)

            return PowderComponentResult(
                id: ing.id,
                name: ing.displayName.isEmpty ? "Subst." : ing.displayName,
                totalG: total,
                perDoseG: perDose,
                isSugarCarrier: hay.contains("sacchar") || hay.contains("lactos"),
                isActive: (ing.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "act",
                isColoring: hay.contains("methyl")
                    || hay.contains("aethacrid")
                    || hay.contains("brilliant")
                    || hay.contains("rifamp")
            )
        }

        let nonAdMassG = components.reduce(0.0) { $0 + $1.totalG }

        let adBase = draft.ingredients.first(where: {
            ($0.isAd || $0.isQS) && $0.unit.rawValue == "g" && $0.amountValue > 0
        })
        let adBaseName: String? = adBase?.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? adBase?.displayName
            : nil

        let adTargetTotalG: Double? = adBase.map { ad in
            resolvedTotalMassG(rawValue: max(0, ad.amountValue), scope: ad.scope, n: n, mode: mode)
        }

        let adFillerG: Double? = adTargetTotalG.map { $0 - nonAdMassG }

        var totalMassG: Double
        var autoFillG: Double = 0

        if let adTargetTotalG, let adFillerG, adFillerG >= 0 {
            totalMassG = adTargetTotalG
        } else {
            totalMassG = nonAdMassG
            let minTotalG = 0.3 * Double(n)
            if totalMassG > 0, totalMassG < minTotalG {
                autoFillG = minTotalG - totalMassG
                totalMassG = minTotalG
            }
        }

        let perDoseG = totalMassG / Double(n)

        let sugarCarrierTotalG = components.filter(\.isSugarCarrier).reduce(0.0) { $0 + $1.totalG }
        let tinyActives = components.filter { $0.isActive && $0.perDoseG > 0 && $0.perDoseG < 0.05 }
        let tinyActivesTotalG = tinyActives.reduce(0.0) { $0 + $1.totalG }
        let triturationSugarNeedG = tinyActivesTotalG * 9.0
        let canBuildTrituration = tinyActivesTotalG > 0 && sugarCarrierTotalG >= triturationSugarNeedG

        return PowdersCalculationResult(
            n: n,
            mode: mode,
            components: components,
            nonAdMassG: nonAdMassG,
            adBaseName: adBaseName,
            adTargetTotalG: adTargetTotalG,
            adFillerG: adFillerG,
            autoFillG: autoFillG,
            totalMassG: totalMassG,
            perDoseG: perDoseG,
            tinyActivesTotalG: tinyActivesTotalG,
            triturationSugarNeedG: triturationSugarNeedG,
            sugarCarrierTotalG: sugarCarrierTotalG,
            canBuildTrituration: canBuildTrituration,
            allowedDeviationPercent: allowedDeviationPercentPowder(perDoseG: perDoseG)
        )
    }

    private static func resolvedTotalMassG(
        rawValue: Double,
        scope: AmountScope,
        n: Int,
        mode: PowderMassMode
    ) -> Double {
        switch scope {
        case .perDose:
            return rawValue * Double(n)
        case .total:
            return rawValue
        case .auto:
            return mode == .dispensa ? (rawValue * Double(n)) : rawValue
        }
    }

    private static func normalizedHay(_ ing: IngredientDraft) -> String {
        let a = (ing.refNameLatNom ?? ing.displayName).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = (ing.refInnKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return a + " " + b
    }

    static func allowedDeviationPercentPowder(perDoseG: Double) -> Double {
        if perDoseG <= 0.1 { return 15 }
        if perDoseG < 0.3 { return 10 }
        if perDoseG <= 1.0 { return 5 }
        if perDoseG <= 10.0 { return 3 }
        return 2
    }
}
