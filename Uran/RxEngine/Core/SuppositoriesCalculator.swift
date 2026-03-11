import Foundation

struct SuppositoryActiveResult: Hashable {
    let name: String
    let totalG: Double
    let eFactor: Double
    let usedFallback: Bool
    let displacedBaseG: Double
}

struct SuppositoriesCalculationResult: Hashable {
    let n: Int
    let moldMassPerSuppG: Double
    let usedDefaultMoldMass: Bool
    let targetTotalG: Double
    let actives: [SuppositoryActiveResult]
    let activesTotalG: Double
    let displacedBaseTotalG: Double
    let baseNeededG: Double
    let hasNegativeBase: Bool
    let fallbackCount: Int
    let baseIngredientName: String?
}

enum SuppositoriesCalculator {
    static func calculate(draft: ExtempRecipeDraft) -> SuppositoriesCalculationResult {
        let n = max(1, draft.numero ?? 1)
        let moldMassPerSuppG = resolvedMoldMass(from: draft)
        let usedDefaultMoldMass = !((draft.targetUnit?.rawValue == "g") && ((draft.targetValue ?? 0) > 0))
        let targetTotalG = moldMassPerSuppG * Double(n)

        let actives: [SuppositoryActiveResult] = draft.ingredients.compactMap { ing in
            guard !ing.isQS, !ing.isAd, ing.unit.rawValue == "g" else { return nil }
            let raw = max(0, ing.amountValue)
            guard raw > 0 else { return nil }

            let total: Double = {
                switch ing.scope {
                case .perDose: return raw * Double(n)
                case .auto, .total: return raw
                }
            }()
            guard total > 0 else { return nil }

            let eFactor: Double
            let usedFallback: Bool
            if let v = ing.refEFactor, v > 0 {
                eFactor = v
                usedFallback = false
            } else {
                eFactor = fallbackEFactor(for: ing)
                usedFallback = true
            }

            return SuppositoryActiveResult(
                name: ing.displayName.isEmpty ? "Subst." : ing.displayName,
                totalG: total,
                eFactor: eFactor,
                usedFallback: usedFallback,
                displacedBaseG: total * eFactor
            )
        }

        let activesTotalG = actives.reduce(0.0) { $0 + $1.totalG }
        let displacedBaseTotalG = actives.reduce(0.0) { $0 + $1.displacedBaseG }
        let baseNeededG = targetTotalG - displacedBaseTotalG
        let hasNegativeBase = baseNeededG < 0
        let fallbackCount = actives.filter(\.usedFallback).count

        let baseIngredientName = draft.ingredients.first(where: {
            ($0.isQS || $0.isAd)
        })?.displayName

        return SuppositoriesCalculationResult(
            n: n,
            moldMassPerSuppG: moldMassPerSuppG,
            usedDefaultMoldMass: usedDefaultMoldMass,
            targetTotalG: targetTotalG,
            actives: actives,
            activesTotalG: activesTotalG,
            displacedBaseTotalG: displacedBaseTotalG,
            baseNeededG: baseNeededG,
            hasNegativeBase: hasNegativeBase,
            fallbackCount: fallbackCount,
            baseIngredientName: baseIngredientName
        )
    }

    private static func resolvedMoldMass(from draft: ExtempRecipeDraft) -> Double {
        if let target = draft.targetValue, target > 0, draft.targetUnit?.rawValue == "g" {
            return target
        }
        return 3.0
    }

    private static func fallbackEFactor(for ing: IngredientDraft) -> Double {
        let hay = ((ing.refInnKey ?? "") + " " + (ing.refNameLatNom ?? ing.displayName)).lowercased()
        if hay.contains("extract") { return 0.7 }
        let heavyKeys = ["zinci", "bismuthi", "hydrargyri", "argenti", "cupri", "plumbi", "ferri"]
        if heavyKeys.contains(where: { hay.contains($0) }) { return 0.2 }
        return 0.8
    }
}
