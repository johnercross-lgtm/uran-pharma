import Foundation

enum OintmentBaseClass: String {
    case hydrophobic = "hydrophobic"
    case absorption = "absorption"
    case emulsionWO = "emulsionW/O"
    case emulsionOW = "emulsionO/W"
    case unknown = "unknown"
}

enum OintmentSolubilityHint {
    case water
    case oil
    case ethanol
    case mixed
    case insoluble
    case unknown
}

struct OintmentIngredientGroups {
    var waterSoluble: [IngredientDraft]
    var oilSoluble: [IngredientDraft]
    var ethanolSoluble: [IngredientDraft]
    var insoluble: [IngredientDraft]
    var mixed: [IngredientDraft]
    var unknown: [IngredientDraft]
}

struct OintmentPulpRecommendation {
    let ingredientName: String
    let ingredientMassG: Double
    let kvGPer100G: Double?
    let wettingMassG: Double?
}

struct OintmentsCalculationResult {
    let totalMassG: Double
    let hadMlApproximation: Bool

    let vaselinG: Double
    let paraffinG: Double
    let oilsG: Double
    let lanolinAnhydG: Double
    let lanolinHydrG: Double
    let pegG: Double
    let glycerinG: Double
    let aquaG: Double

    let baseClass: OintmentBaseClass
    let isOphthalmic: Bool

    let waterNeededG: Double
    let baseWaterCapacityG: Double
    let suggestedExtraLanolinAnhydG: Double
    let waterPhasePresent: Bool

    let eutecticCandidates: [IngredientDraft]
    let hasVolatiles: Bool
    let groups: OintmentIngredientGroups
    let insolubleMassG: Double
    let pulpRecommendations: [OintmentPulpRecommendation]

    let hasAcid: Bool
    let hasCarbonate: Bool

    let targetMassG: Double?
    let targetMassDeltaG: Double?
}

enum OintmentsCalculator {
    private enum WaterCapacity {
        static let vaseline: Double = 0.02
        static let oil: Double = 0.05
        static let lanolinAnhyd: Double = 1.50
        static let lanolinHydrExtra: Double = 0.30
    }

    private enum Limits {
        static let waterPhasePresentWarn: Double = 0.01
    }

    static func calculate(draft: ExtempRecipeDraft) -> OintmentsCalculationResult {
        let signa = draft.signa.lowercased()
        let isOphthalmic = signa.contains("оч") || signa.contains("eye") || signa.contains("ophth")

        var totalMassG: Double = 0
        var hadMlApproximation = false

        for ing in draft.ingredients where !ing.isQS && !ing.isAd {
            if ing.unit.rawValue == "g" {
                totalMassG += max(0, ing.amountValue)
            } else if ing.unit.rawValue == "ml" {
                totalMassG += max(0, ing.amountValue)
                hadMlApproximation = true
            }
        }

        let vaselinG = sumMass(draft.ingredients, markers: ["vaselin", "вазелин"])
        let paraffinG = sumMass(draft.ingredients, markers: ["paraffin", "парафин"])
        let oilsG = sumMass(draft.ingredients, markers: ["oleum", "oil", "олія", "масло"])
        let lanolinAnhydG = sumMass(draft.ingredients, markers: ["lanolin", "ланол"], required: ["anhyd"])
        let lanolinHydrG = sumMass(draft.ingredients, markers: ["lanolin", "ланол"], required: ["hydric"])
        let pegG = sumMass(draft.ingredients, markers: ["peg", "macrogol", "макрогол", "пэг", "полиэтиленглик"])
        let glycerinG = sumMass(draft.ingredients, markers: ["glycer", "гліцерин", "глицерин"])
        let aquaG = sumMass(draft.ingredients, markers: ["aqua", "water", "вода", "очищ"])

        let baseClass = classifyBase(
            vaselinG: vaselinG,
            paraffinG: paraffinG,
            oilsG: oilsG,
            lanolinAnhydG: lanolinAnhydG,
            lanolinHydrG: lanolinHydrG,
            pegG: pegG,
            glycerinG: glycerinG,
            aquaG: aquaG
        )

        let waterNeededG = draft.ingredients.reduce(0.0) { acc, ing in
            guard !ing.isQS, !ing.isAd, ing.unit.rawValue == "g", ing.amountValue > 0 else { return acc }
            let kv = ing.refKvGPer100G ?? 0
            if kv <= 0 { return acc }
            return acc + ing.amountValue * kv / 100.0
        }

        let baseWaterCapacityG =
            vaselinG * WaterCapacity.vaseline +
            oilsG * WaterCapacity.oil +
            lanolinAnhydG * WaterCapacity.lanolinAnhyd +
            lanolinHydrG * WaterCapacity.lanolinHydrExtra

        var suggestedExtraLanolinAnhydG: Double = 0
        if waterNeededG > 0, waterNeededG > baseWaterCapacityG {
            let deficit = waterNeededG - baseWaterCapacityG
            suggestedExtraLanolinAnhydG = deficit / WaterCapacity.lanolinAnhyd
        }

        let waterPhasePresent =
            (waterNeededG > Limits.waterPhasePresentWarn) ||
            (aquaG > Limits.waterPhasePresentWarn)

        let eutecticMarkers = ["menthol", "camphor", "chloral", "phenol", "thymol", "resorcin"]
        let volatileMarkers = ["menthol", "camphor", "ether", "aether", "chloroform", "chloral", "eucalypt", "terpen"]

        let eutecticCandidates = draft.ingredients.filter {
            guard !$0.isQS, !$0.isAd, $0.unit.rawValue == "g", $0.amountValue > 0 else { return false }
            let hay = normalizedHay($0)
            return eutecticMarkers.contains(where: { hay.contains($0) })
        }

        let hasVolatiles = draft.ingredients.contains {
            let hay = normalizedHay($0)
            return volatileMarkers.contains(where: { hay.contains($0) })
        }

        let actives = draft.ingredients.filter {
            guard !$0.isQS, !$0.isAd, $0.amountValue > 0 else { return false }
            let type = ($0.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return type != "base"
        }

        var waterSoluble: [IngredientDraft] = []
        var oilSoluble: [IngredientDraft] = []
        var ethanolSoluble: [IngredientDraft] = []
        var insoluble: [IngredientDraft] = []
        var mixed: [IngredientDraft] = []
        var unknown: [IngredientDraft] = []

        for ing in actives {
            switch solubilityHint(text: ing.refSolubility) {
            case .water:
                waterSoluble.append(ing)
            case .oil:
                oilSoluble.append(ing)
            case .ethanol:
                ethanolSoluble.append(ing)
            case .insoluble:
                insoluble.append(ing)
            case .mixed:
                mixed.append(ing)
            case .unknown:
                unknown.append(ing)
            }
        }

        let insolubleMassG = insoluble.reduce(0.0) { acc, ing in
            guard ing.unit.rawValue == "g" else { return acc }
            return acc + max(0, ing.amountValue)
        }

        let pulpRecommendations: [OintmentPulpRecommendation] = insoluble.compactMap { ing in
            guard ing.unit.rawValue == "g", ing.amountValue > 0 else { return nil }
            let kv = ing.refKvGPer100G
            let wetting: Double?
            if let kv, kv > 0 {
                wetting = ing.amountValue * kv / 100.0
            } else {
                wetting = nil
            }
            return OintmentPulpRecommendation(
                ingredientName: ing.displayName,
                ingredientMassG: ing.amountValue,
                kvGPer100G: (kv ?? 0) > 0 ? kv : nil,
                wettingMassG: wetting
            )
        }

        let hasAcid = actives.contains {
            let hay = normalizedHay($0)
            return hay.contains("acid") || hay.contains("acidum") || hay.contains("кисл")
        }
        let hasCarbonate = actives.contains {
            let hay = normalizedHay($0)
            return hay.contains("carbonat") || hay.contains("bicarbonat") || hay.contains("карбон") || hay.contains("гидрокарб")
        }

        let targetMassG: Double? = {
            guard draft.targetUnit?.rawValue == "g", let target = draft.targetValue, target > 0 else {
                return nil
            }
            return target
        }()

        let targetMassDeltaG: Double? = targetMassG.map { abs(totalMassG - $0) }

        return OintmentsCalculationResult(
            totalMassG: totalMassG,
            hadMlApproximation: hadMlApproximation,
            vaselinG: vaselinG,
            paraffinG: paraffinG,
            oilsG: oilsG,
            lanolinAnhydG: lanolinAnhydG,
            lanolinHydrG: lanolinHydrG,
            pegG: pegG,
            glycerinG: glycerinG,
            aquaG: aquaG,
            baseClass: baseClass,
            isOphthalmic: isOphthalmic,
            waterNeededG: waterNeededG,
            baseWaterCapacityG: baseWaterCapacityG,
            suggestedExtraLanolinAnhydG: suggestedExtraLanolinAnhydG,
            waterPhasePresent: waterPhasePresent,
            eutecticCandidates: eutecticCandidates,
            hasVolatiles: hasVolatiles,
            groups: OintmentIngredientGroups(
                waterSoluble: waterSoluble,
                oilSoluble: oilSoluble,
                ethanolSoluble: ethanolSoluble,
                insoluble: insoluble,
                mixed: mixed,
                unknown: unknown
            ),
            insolubleMassG: insolubleMassG,
            pulpRecommendations: pulpRecommendations,
            hasAcid: hasAcid,
            hasCarbonate: hasCarbonate,
            targetMassG: targetMassG,
            targetMassDeltaG: targetMassDeltaG
        )
    }

    static func suggestPackaging(
        isOphthalmic: Bool,
        signa: String,
        baseClass: OintmentBaseClass
    ) -> String {
        if isOphthalmic { return "стерильну тубу" }
        if signa.contains("втират") || signa.contains("наруж") { return "банку або тубу" }
        if baseClass == .emulsionOW { return "банку (крем)" }
        return "банку або тубу"
    }

    private static func classifyBase(
        vaselinG: Double,
        paraffinG: Double,
        oilsG: Double,
        lanolinAnhydG: Double,
        lanolinHydrG: Double,
        pegG: Double,
        glycerinG: Double,
        aquaG: Double
    ) -> OintmentBaseClass {
        if (pegG > 0 || glycerinG > 0) && aquaG > 0 {
            return .emulsionOW
        }

        if lanolinAnhydG > 0 && (vaselinG + oilsG + paraffinG) > 0 {
            if aquaG > 0 || glycerinG > 0 || lanolinHydrG > 0 {
                return .emulsionWO
            }
            return .absorption
        }

        if (vaselinG + oilsG + paraffinG) > 0 {
            return .hydrophobic
        }

        return .unknown
    }

    private static func solubilityHint(text: String?) -> OintmentSolubilityHint {
        let s = (text ?? "").lowercased()
        if s.isEmpty { return .unknown }

        if s.contains("insol") || s.contains("нерозч") || s.contains("практично не") {
            return .insoluble
        }

        let water = s.contains("water") || s.contains("вод") || s.contains("aqua")
        let oil = s.contains("oil") || s.contains("oleum") || s.contains("жир") || s.contains("масл")
        let ethanol = s.contains("ethanol") || s.contains("spirit") || s.contains("алког") || s.contains("спирт")

        let count = [water, oil, ethanol].filter { $0 }.count
        if count >= 2 { return .mixed }
        if water { return .water }
        if oil { return .oil }
        if ethanol { return .ethanol }

        if s.contains("solub") || s.contains("розчин") { return .mixed }

        return .unknown
    }

    private static func sumMass(
        _ ingredients: [IngredientDraft],
        markers: [String],
        required: [String] = []
    ) -> Double {
        ingredients.reduce(0.0) { acc, ing in
            guard !ing.isQS, !ing.isAd, ing.unit.rawValue == "g", ing.amountValue > 0 else {
                return acc
            }

            let hay = normalizedHay(ing)
            let hasMarker = markers.contains(where: { hay.contains($0) })
            if !hasMarker { return acc }
            if !required.isEmpty, !required.allSatisfy({ hay.contains($0) }) { return acc }
            return acc + ing.amountValue
        }
    }

    private static func normalizedHay(_ ing: IngredientDraft) -> String {
        let a = (ing.refNameLatNom ?? ing.displayName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let b = (ing.refInnKey ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return a + " " + b
    }
}
