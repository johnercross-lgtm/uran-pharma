import Foundation

struct RxFacts {
    var isLiquid: Bool
    var isDrops: Bool
    var isOphthalmic: Bool
    var isPowders: Bool
    var isSuppositories: Bool
    var isOintments: Bool
    var isNonAqueousSolution: Bool
    var nonAqueousSolvent: NonAqueousSolventType?
    var hasAlcohol: Bool
    var hasStandardSolutionAlias: Bool
    var hasVmsOrColloid: Bool
    var hasInfusionDecoctionMarkers: Bool
    var hasHerbal: Bool
    var hasTincture: Bool
    var hasExtract: Bool
    var hasElectrolytes: Bool
    var hasQSorAd: Bool
    var needsFiltration: Bool
    var solidsPercentOfTarget: Double?
    var inferredLiquidTargetMl: Double?
    var solidsMassG: Double
    var hasTriturationRisk: Bool
}

struct RxFactsAnalyzer {
    func analyze(draft: ExtempRecipeDraft) -> RxFacts {
        func parsePercent(from text: String) -> Double? {
            let s = text.replacingOccurrences(of: ",", with: ".")
            guard let r = s.range(of: "(\\d{1,2}(?:\\.\\d+)?)\\s*%", options: .regularExpression) else { return nil }
            let m = String(s[r]).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(m)
        }

        let names = draft.ingredients.map { normalizedHay($0) }
        let effectiveFormMode = SignaUsageAnalyzer.effectiveFormMode(for: draft)
        let isDrops = effectiveFormMode == .drops
        let signa = draft.signa.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isOphthalmic = signa.contains("очн")
            || signa.contains("глаз")
            || signa.contains("oculo")
            || signa.contains("ophth")
            || signa.contains("eye")
        let isPowders = effectiveFormMode == .powders
        let isSuppositories = effectiveFormMode == .suppositories
        let isOintments = effectiveFormMode == .ointments
        let hasLiquidComponents = draft.ingredients.contains(where: { it in
            it.unit.rawValue == "ml"
            || it.presentationKind == .solution
            || isLiquidByReference(it)
        })
        let isLiquid = effectiveFormMode == .drops
            || effectiveFormMode == .solutions
            || hasLiquidComponents

        let nonAqueousSolvent = NonAqueousSolventCatalog.primarySolvent(in: draft)?.type
        let isNonAqueousSolution = (effectiveFormMode == .solutions || effectiveFormMode == .drops) && nonAqueousSolvent != nil
        let hasAlcohol = draft.ingredients.contains(where: isAlcoholIngredient) || nonAqueousSolvent == .ethanol

        let hasStandard = draft.standardSolutionSourceKey != nil || names.contains(where: {
            $0.contains("formalin") || $0.contains("формалин")
            || $0.contains("perhydrol") || $0.contains("пергидрол")
            || $0.contains("bur") || $0.contains("буров")
            || $0.contains("acidum hydrochlor") || $0.contains("хлористовод")
        })

        let hasVms = draft.ingredients.contains(where: { inferredDissolutionType($0) != .ordinary })

        let hasHerbal = draft.ingredients.contains(where: { isHerbalIngredient($0) })
        let hasTincture = draft.ingredients.contains(where: { refType($0) == "tincture" })
        let hasExtract = draft.ingredients.contains(where: { refType($0) == "extract" })
        let hasInfusion = draft.ingredients.contains(where: isInfusionDecoctionIngredient)

        let hasElectrolytes = draft.ingredients.contains(where: isElectrolyteIngredient)

        let target: Double? = {
            if let explicit = draft.explicitLiquidTargetMl {
                return explicit
            }
            if let legacy = draft.legacyAdOrQsLiquidTargetMl {
                return legacy
            }
            if effectiveFormMode == .solutions || effectiveFormMode == .drops {
                let measuredLiquids = draft.ingredients.compactMap { ing -> Double? in
                    guard !ing.isQS, !ing.isAd else { return nil }
                    let volume = draft.effectiveLiquidVolumeMl(for: ing)
                    return volume > 0 ? volume : nil
                }
                let hasPrimaryAqueous = draft.ingredients.contains(where: isPrimaryAqueousLiquid)
                if hasPrimaryAqueous {
                    let totalMeasured = measuredLiquids.reduce(0, +)
                    if totalMeasured > 0 {
                        return totalMeasured
                    }
                }

                let aquaCandidates = draft.ingredients.compactMap { ing -> Double? in
                    guard !ing.isQS, !ing.isAd else { return nil }
                    guard ing.unit.rawValue == "ml", ing.amountValue > 0 else { return nil }
                    guard isPrimaryAqueousLiquid(ing) else { return nil }
                    return ing.amountValue
                }
                if let inferred = aquaCandidates.max() {
                    return inferred
                }

                let solutionCandidates = draft.ingredients.compactMap { ing -> Double? in
                    guard !ing.isQS, !ing.isAd, ing.presentationKind == .solution else { return nil }
                    return draft.solutionVolumeMl(for: ing)
                }
                if let inferred = solutionCandidates.max() {
                    return inferred
                }
            }
            return nil
        }()

        let repo = StandardSolutionsRepository.shared
        let solidsG = draft.ingredients.reduce(0.0) { acc, ing in
            guard !ing.isQS, !ing.isAd else { return acc }

            let parsedPercent = draft.solutionDisplayPercent(for: ing)
                ?? parsePercent(from: ing.refNameLatNom ?? ing.displayName)
            if draft.useStandardSolutionsBlock,
               (repo.matchIngredient(ing, parsedPercent: parsedPercent) != nil
                || (draft.standardSolutionSourceKey != nil && ing.presentationKind == .solution)) {
                return acc
            }

            if let inferredMass = draft.solutionActiveMassG(for: ing), inferredMass > 0 {
                return acc + inferredMass
            }

            guard ing.unit.rawValue == "g" else { return acc }
            guard !isLiquidByReference(ing) else { return acc }

            let explicit = max(0, ing.amountValue)
            if explicit > 0 {
                return acc + explicit
            }
            return acc
        }

        let solidsPct: Double? = {
            guard let target, target > 0 else { return nil }
            return (solidsG / target) * 100.0
        }()

        let needsFiltration = isDrops
            || draft.ingredients.contains(where: { $0.presentationKind == .solution })
            || draft.ingredients.contains(where: {
                let s = normalizedHay($0)
                return s.contains("susp") || s.contains("resina")
            })

        let hasTriturationRisk: Bool = {
            guard isPowders else { return false }
            let hasSugarCarrier = draft.ingredients.contains {
                let s = normalizedHay($0)
                return s.contains("sacchar") || s.contains("lactos")
            }
            guard hasSugarCarrier else { return false }

            let n = max(1, draft.numero ?? 1)
            return draft.ingredients.contains { ing in
                guard !ing.isQS, !ing.isAd else { return false }
                let type = refType(ing)
                guard type == "act" else { return false }
                guard ing.unit.rawValue == "g", ing.amountValue > 0 else { return false }
                let perDose = ing.scope == .perDose ? ing.amountValue : (ing.amountValue / Double(n))
                return perDose > 0 && perDose < 0.05
            }
        }()

        return RxFacts(
            isLiquid: isLiquid,
            isDrops: isDrops,
            isOphthalmic: isOphthalmic,
            isPowders: isPowders,
            isSuppositories: isSuppositories,
            isOintments: isOintments,
            isNonAqueousSolution: isNonAqueousSolution,
            nonAqueousSolvent: nonAqueousSolvent,
            hasAlcohol: hasAlcohol,
            hasStandardSolutionAlias: hasStandard,
            hasVmsOrColloid: hasVms,
            hasInfusionDecoctionMarkers: hasInfusion,
            hasHerbal: hasHerbal,
            hasTincture: hasTincture,
            hasExtract: hasExtract,
            hasElectrolytes: hasElectrolytes,
            hasQSorAd: draft.ingredients.contains(where: { $0.isQS || $0.isAd }),
            needsFiltration: needsFiltration,
            solidsPercentOfTarget: solidsPct,
            inferredLiquidTargetMl: target,
            solidsMassG: solidsG,
            hasTriturationRisk: hasTriturationRisk
        )
    }

    private func normalizedHay(_ ing: IngredientDraft) -> String {
        let a = (ing.refNameLatNom ?? ing.displayName).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = (ing.refInnKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return a + " " + b
    }

    private func refType(_ ing: IngredientDraft) -> String {
        (ing.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isHerbalIngredient(_ ing: IngredientDraft) -> Bool {
        let t = refType(ing)
        if t == "herbalraw" || t == "herbalmix" { return true }

        if let ratio = ing.refHerbalRatio?.trimmingCharacters(in: .whitespacesAndNewlines), !ratio.isEmpty {
            return true
        }

        let hay = normalizedHay(ing)
        let herbalMarkers = ["herba", "folia", "flores", "flos", "radix", "rhizoma", "cortex", "fructus", "semina", "трава", "лист", "цвет", "корень", "кора", "плод", "насіння", "семена"]
        return herbalMarkers.contains(where: { hay.contains($0) })
    }

    private func isInfusionDecoctionIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        let type = refType(ing)

        if hay.contains("infus") || hay.contains("decoct") { return true }
        if hay.contains("відвар") || hay.contains("отвар") { return true }

        let hasNastiy = hay.contains("настій") || hay.contains("настой")
        let looksLikeTincture = hay.contains("настойк") || hay.contains("tinct") || type == "tincture"
        if hasNastiy && !looksLikeTincture { return true }

        if isHerbalIngredient(ing) {
            if let ratio = ing.refHerbalRatio?.trimmingCharacters(in: .whitespacesAndNewlines), !ratio.isEmpty { return true }
            if ing.refWaterTempC != nil || ing.refHeatBathMin != nil || ing.refStandMin != nil {
                return true
            }
        }

        return false
    }

    private func isLiquidByReference(_ ing: IngredientDraft) -> Bool {
        if ing.unit.rawValue == "ml" { return true }
        let t = refType(ing)
        return t == "solvent"
            || t == "buffersolution"
            || t == "standardsolution"
            || t == "tincture"
            || t == "extract"
    }

    private func isPrimaryAqueousLiquid(_ ing: IngredientDraft) -> Bool {
        if PurifiedWaterHeuristics.isPurifiedWater(ing) { return true }
        return ing.isReferenceAromaticWater
    }

    private func inferredDissolutionType(_ ing: IngredientDraft) -> DissolutionType {
        if let t = ing.refDissolutionType { return t }
        let hay = normalizedHay(ing)
        if hay.contains("protarg") { return .colloidProtargol }
        if hay.contains("collarg") { return .colloidCollargol }
        if hay.contains("ichthy") || hay.contains("іхті") { return .ichthyol }
        if hay.contains("gelatin") || hay.contains("gelatina") { return .hmcRestrictedHeat }
        if hay.contains("amylum") || hay.contains("starch") || hay.contains("крохмал") { return .hmcRestrictedHeat }
        if hay.contains("methylcell") || hay.contains("метилцел") { return .hmcRestrictedCool }
        if hay.contains("pepsin") || hay.contains("pepsinum") { return .hmcUnrestricted }
        return .ordinary
    }

    private func isAlcoholIngredient(_ ing: IngredientDraft) -> Bool {
        NonAqueousSolventCatalog.classify(ingredient: ing) == .ethanol
    }

    private func isElectrolyteIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = normalizedHay(ing)
        return hay.contains("chlorid")
            || hay.contains("chloride")
            || hay.contains("bromid")
            || hay.contains("bromide")
            || hay.contains("iodid")
            || hay.contains("iodide")
            || hay.contains("nitrat")
            || hay.contains("nitrate")
            || hay.contains("sulfat")
            || hay.contains("sulfate")
            || hay.contains("phosphat")
            || hay.contains("phosphate")
    }
}
