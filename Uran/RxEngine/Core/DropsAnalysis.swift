import Foundation

struct DropsDoseAnalysisResult {
    var lines: [String]
    var issues: [RxIssue]
}

enum DropsAnalysis {
    struct DropsPerMlResolution {
        let value: Double
        let sourceDescription: String
        let isApproximate: Bool
    }

    static func inferTargetVolumeMl(context: RxPipelineContext) -> Double {
        if let target = context.facts.inferredLiquidTargetMl, target > 0 {
            return target
        }

        let sum = context.draft.ingredients.reduce(0.0) { acc, ing in
            if ing.isQS || ing.isAd { return acc }
            return acc + effectiveLiquidMl(ing, draft: context.draft)
        }

        return max(0, sum)
    }

    static func effectiveLiquidMl(_ ing: IngredientDraft, draft: ExtempRecipeDraft) -> Double {
        draft.effectiveLiquidVolumeMl(for: ing)
    }

    static func isOphthalmic(signa: String) -> Bool {
        let s = signa.lowercased()
        return s.contains("очн") ||
            s.contains("глаз") ||
            s.contains("oculo") ||
            s.contains("ophth") ||
            s.contains("eye")
    }

    static func requiresDarkGlass(draft: ExtempRecipeDraft) -> Bool {
        let relevantIngredients = draft.ingredients.filter { !$0.isAd && !$0.isQS }

        if relevantIngredients.contains(where: { $0.isReferenceListA }) { return true }
        if relevantIngredients.contains(where: { ingredient in isPhenolFamily(ingredient) }) { return true }
        if relevantIngredients.contains(where: { ingredient in isGlycerinIngredient(ingredient) }) { return true }
        if let primary = NonAqueousSolventCatalog.primarySolvent(in: draft), primary.type == .glycerin {
            return true
        }
        return relevantIngredients.contains { ing in
            if isStableHalideWithoutExplicitPhotolability(ing) {
                return false
            }
            if ing.isReferenceLightSensitive { return true }
            return markerMatch(
                ingredient: ing,
                keys: ["light_sensitive", "instruction_id", "process_note", "storage"],
                values: [
                    "lightprotected",
                    "protectfromlight",
                    "light_sensitive",
                    "amberglass",
                    "darkglass",
                    "темнескло",
                    "захищеновідсвітла"
                ]
            )
        }
    }

    static func buildMeasurementLines(draft: ExtempRecipeDraft) -> [String] {
        let dropsCalculator = DropsCalculator()
        return draft.ingredients.compactMap { ing in
            guard !ing.isQS, !ing.isAd, ing.unit.rawValue == "ml", ing.amountValue > 0 else { return nil }
            guard let resolution = resolvedDropsPerMl(for: ing, draft: draft) else { return nil }
            let drops = (try? dropsCalculator.drops(fromMl: ing.amountValue, dropsPerMl: resolution.value)) ?? 0
            let qualifier = resolution.isApproximate ? " приблизно" : ""
            return "\(ing.displayName): \(format(ing.amountValue)) ml ≈ \(format(drops)) gtt (\(format(resolution.value)) gtt/ml, \(resolution.sourceDescription)\(qualifier))"
        }
    }

    static func buildDoseChecks(draft: ExtempRecipeDraft, signa: String) -> DropsDoseAnalysisResult {
        guard let dropsPerDose = parseDropsPerDose(from: signa), dropsPerDose > 0 else {
            return DropsDoseAnalysisResult(
                lines: ["⚠ Не знайдено 'капель за прийом' у Signa — контроль доз для крапель неповний"],
                issues: []
            )
        }

        guard let volumeResolution = resolvedTotalVolumeMlForDrops(draft: draft),
              volumeResolution.volumeMl > 0
        else {
            return DropsDoseAnalysisResult(
                lines: ["⚠ Не вдалося визначити загальний об’єм (ml) для крапель"],
                issues: []
            )
        }
        let totalVolumeMl = volumeResolution.volumeMl

        var approximateSources: [String] = []
        var totalDrops = draft.ingredients.reduce(0.0) { acc, ing in
            if ing.isQS || ing.isAd { return acc }

            let v = effectiveLiquidMl(ing, draft: draft)
            guard v > 0 else { return acc }

            guard let resolution = resolvedDropsPerMl(for: ing, draft: draft) else { return acc }
            if resolution.isApproximate {
                approximateSources.append("\(ing.displayName) (\(resolution.sourceDescription))")
            }
            return acc + (v * resolution.value)
        }

        if totalDrops <= 0,
           let primary = NonAqueousSolventCatalog.primarySolvent(in: draft)
        {
            let ethanolStrength = primary.type == .ethanol
                ? NonAqueousSolventCatalog.requestedEthanolStrength(from: primary.ingredient)
                : nil
            if let gtts = NonAqueousSolventCatalog.standardDropsPerMl(for: primary.type, ethanolStrength: ethanolStrength),
               gtts > 0
            {
                totalDrops = totalVolumeMl * gtts
                approximateSources.append("загальний об'єм (таблиця крапель для \(primary.type.rawValue))")
            }
        }

        let doses = max(1.0, floor(totalDrops / dropsPerDose))
        let frequency = parseFrequency(from: signa)
        let dailyIntakes = max(1.0, dropsPerDose * Double(max(1, frequency)))
        let treatmentDays = max(1.0, floor(totalDrops / dailyIntakes))

        var lines: [String] = []
        var issues: [RxIssue] = []

        lines.append("Капель за прийом: \(format(dropsPerDose)) gtt")
        if volumeResolution.note == nil {
            lines.append("Загальний об’єм: \(format(totalVolumeMl)) ml")
        } else {
            lines.append("Загальний об’єм (розрахунково): ≈ \(format(totalVolumeMl)) ml")
        }
        if let note = volumeResolution.note, !note.isEmpty {
            lines.append(note)
        }
        lines.append("Орієнтовна кількість разових прийомів: \(format(doses))")
        lines.append("Кратність прийому: \(frequency) р/добу")
        lines.append("Орієнтовна тривалість: \(format(treatmentDays)) діб")

        if !approximateSources.isEmpty {
            let msg = "Для частини рідин використано табличні/наближені gtts/ml: \(approximateSources.joined(separator: ", "))"
            lines.append("⚠ \(msg)")
            issues.append(RxIssue(code: "drops.gtts.missing", severity: .warning, message: msg))
        }

        let baselineLinesCount = lines.count

        for ing in draft.ingredients {
            if ing.isQS || ing.isAd { continue }

            let type = (ing.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let hasRegistryRestriction = ing.isReferenceListB || ing.refIsNarcotic
            let hasTypeRestriction = type == "poison" || type == "strong" || type == "lista" || type == "listb"
            let doseLimit = resolvedPerDoseLimit(ingredient: ing, ageYears: draft.patientAgeYears)
            let dayLimit = resolvedPerDayLimit(ingredient: ing, ageYears: draft.patientAgeYears)
            let hasAnyLimit = doseLimit != nil || dayLimit != nil
            guard hasRegistryRestriction || hasTypeRestriction || hasAnyLimit else { continue }

            let ingMassG = draft.inferredActiveMassG(for: ing)

            guard ingMassG > 0 else { continue }

            let perDoseG = ingMassG / doses
            let perDayG = perDoseG * Double(frequency)

            var restrictionTags: [String] = []
            if ing.isReferenceListA { restrictionTags.append("List A") }
            if ing.isReferenceListB { restrictionTags.append("List B") }
            if ing.refIsNarcotic { restrictionTags.append("Narcotic") }
            let tagText = restrictionTags.isEmpty ? "" : " [\(restrictionTags.joined(separator: ", "))]"

            lines.append("— \(ing.displayName)\(tagText): на 1 прийом \(String(format: "%.4f", perDoseG)) g; на добу \(String(format: "%.4f", perDayG)) g")

            if let doseLimit, perDoseG > doseLimit.value {
                let msg = "ПЕРЕВИЩЕННЯ ВРД (\(doseLimit.label)) для \(ing.displayName): \(String(format: "%.4f", perDoseG)) > \(format(doseLimit.value))"
                lines.append("❌ \(msg)")
                issues.append(RxIssue(code: "drops.vrd.exceeded.\(ing.id)", severity: .blocking, message: msg))
            }

            if let dayLimit, perDayG > dayLimit.value {
                let msg = "ПЕРЕВИЩЕННЯ ВСД (\(dayLimit.label)) для \(ing.displayName): \(String(format: "%.4f", perDayG)) > \(format(dayLimit.value))"
                lines.append("❌ \(msg)")
                issues.append(RxIssue(code: "drops.vsd.exceeded.\(ing.id)", severity: .blocking, message: msg))
            }
        }

        if lines.count == baselineLinesCount {
            lines.append("ℹ У складі не виявлено речовин з обмеженнями або в довіднику бракує даних для дозового контролю")
        }

        return DropsDoseAnalysisResult(lines: lines, issues: issues)
    }

    private static func resolvedPerDoseLimit(ingredient ing: IngredientDraft, ageYears: Int?) -> (value: Double, label: String)? {
        if let ageYears {
            if ageYears < 1, let v = ing.refVrdChild0_1, v > 0 { return (v, "0–1 рік") }
            if ageYears >= 1, ageYears <= 6, let v = ing.refVrdChild1_6, v > 0 { return (v, "1–6 років") }
            if ageYears > 6, ageYears <= 14, let v = ing.refVrdChild7_14, v > 0 { return (v, "7–14 років") }
            if ageYears <= 14, let v = ing.refPedsVrdG, v > 0 { return (v, "дитяча") }
        }
        if let v = ing.refVrdG, v > 0 { return (v, "доросла") }
        return nil
    }

    private static func resolvedPerDayLimit(ingredient ing: IngredientDraft, ageYears: Int?) -> (value: Double, label: String)? {
        if let ageYears, ageYears <= 14, let v = ing.refPedsRdG, v > 0 {
            return (v, "дитяча")
        }
        if let v = ing.refVsdG, v > 0 { return (v, "доросла") }
        return nil
    }

    private static func parseFrequency(from signa: String) -> Int {
        SignaFrequencyParser.frequencyPerDay(from: signa) ?? 1
    }

    private static func parseDropsPerDose(from signa: String) -> Double? {
        let s = signa.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return nil }

        let patterns: [String] = [
            "(\\d+(?:[\\.,]\\d+)?)\\s*(?:кап\\.|капель|капля|капли|кап)",
            "(\\d+(?:[\\.,]\\d+)?)\\s*(?:к\\.|к)\\b",
            "(\\d+(?:[\\.,]\\d+)?)\\s*(?:gtts\\.|gtts|gtt\\.|gtt|guttae)"
        ]

        for p in patterns {
            if let r = s.range(of: p, options: .regularExpression) {
                let m = String(s[r])
                if let numRange = m.range(of: "\\d+(?:[\\.,]\\d+)?", options: .regularExpression) {
                    let raw = String(m[numRange]).replacingOccurrences(of: ",", with: ".")
                    return Double(raw)
                }
            }
        }

        return nil
    }

    static func resolvedDropsPerMl(for ingredient: IngredientDraft, draft: ExtempRecipeDraft) -> DropsPerMlResolution? {
        if let gtts = ingredient.refGttsPerMl, gtts > 0 {
            return DropsPerMlResolution(value: gtts, sourceDescription: "довідник речовини", isApproximate: false)
        }

        if let profile = NonAqueousSolventCatalog.concentrationControlProfile(for: ingredient),
           let override = profile.dropsPerMlOverride,
           override > 0
        {
            return DropsPerMlResolution(
                value: override,
                sourceDescription: "профіль офіцинального/антисептичного розчину (\(profile.title))",
                isApproximate: false
            )
        }

        if isTinctureIngredient(ingredient) {
            return DropsPerMlResolution(
                value: 60,
                sourceDescription: "стандарт для настойок (спиртова система)",
                isApproximate: false
            )
        }

        if PurifiedWaterHeuristics.isPurifiedWater(ingredient) {
            return DropsPerMlResolution(
                value: DropsCalculator.defaultStandardDropsPerMlWater,
                sourceDescription: "стандарт води",
                isApproximate: false
            )
        }

        if let solvent = NonAqueousSolventCatalog.primarySolvent(in: draft) {
            let ethanolStrength = solvent.type == .ethanol
                ? NonAqueousSolventCatalog.requestedEthanolStrength(from: solvent.ingredient)
                : nil
            if let gtts = NonAqueousSolventCatalog.standardDropsPerMl(for: solvent.type, ethanolStrength: ethanolStrength) {
                let source = solvent.type == .ethanol
                    ? "таблиця крапель для спирту \(ethanolStrength ?? 90)%"
                    : "таблиця крапель для \(solvent.type.rawValue)"
                return DropsPerMlResolution(value: gtts, sourceDescription: source, isApproximate: false)
            }
        }

        return DropsPerMlResolution(
            value: DropsCalculator.defaultStandardDropsPerMlWater,
            sourceDescription: "водний стандарт за відсутності довідника",
            isApproximate: true
        )
    }

    private static func resolvedTotalVolumeMlForDrops(draft: ExtempRecipeDraft) -> (volumeMl: Double, note: String?)? {
        if let explicit = draft.explicitLiquidTargetMl, explicit > 0 {
            return (explicit, nil)
        }
        if let legacy = draft.legacyAdOrQsLiquidTargetMl, legacy > 0 {
            return (legacy, nil)
        }

        let measuredMl = draft.ingredients.reduce(0.0) { acc, ing in
            if ing.isQS || ing.isAd { return acc }
            return acc + effectiveLiquidMl(ing, draft: draft)
        }
        if measuredMl > 0 {
            return (measuredMl, nil)
        }

        guard let primary = NonAqueousSolventCatalog.primarySolvent(in: draft),
              primary.type.isViscous
        else { return nil }

        let density = primary.type == .glycerin
            ? 1.25
            : NonAqueousSolventCatalog.density(for: primary.type, fallback: primary.ingredient?.refDensity)
        guard let density, density > 0 else { return nil }

        let totalMassG = draft.ingredients.reduce(0.0) { acc, ing in
            guard !ing.isQS, !ing.isAd else { return acc }
            guard let mass = ingredientMassG(ing, draft: draft, primarySolvent: primary) else { return acc }
            return acc + mass
        }
        guard totalMassG > 0 else { return nil }

        let estimatedMl = totalMassG / density
        let note = "Неводна в'язка система: V(орієнтовний) = m/ρ = \(format(totalMassG))/\(format(density)) = \(format(estimatedMl)) ml"
        return (estimatedMl, note)
    }

    private static func ingredientMassG(
        _ ingredient: IngredientDraft,
        draft: ExtempRecipeDraft,
        primarySolvent: (ingredient: IngredientDraft?, type: NonAqueousSolventType)?
    ) -> Double? {
        guard ingredient.amountValue > 0 else { return nil }
        let unit = ingredient.unit.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if unit == "g" || unit == "г" {
            return ingredient.amountValue
        }

        if unit == "ml" || unit == "мл" {
            if let density = ingredient.refDensity, density > 0 {
                return ingredient.amountValue * density
            }
            if let primarySolvent,
               primarySolvent.ingredient?.id == ingredient.id
            {
                if primarySolvent.type == .glycerin {
                    return ingredient.amountValue * 1.25
                }
                if let density = NonAqueousSolventCatalog.density(
                    for: primarySolvent.type,
                    fallback: primarySolvent.ingredient?.refDensity
                ), density > 0 {
                    return ingredient.amountValue * density
                }
            }
            if isGlycerinIngredient(ingredient) {
                return ingredient.amountValue * 1.25
            }
            if PurifiedWaterHeuristics.isPurifiedWater(ingredient) {
                return ingredient.amountValue
            }
        }

        let inferred = draft.inferredActiveMassG(for: ingredient)
        return inferred > 0 ? inferred : nil
    }

    private static func format(_ v: Double) -> String {
        if v == floor(v) { return String(Int(v)) }
        return String(format: "%.2f", v)
    }

    private static func isPhenolFamily(_ ingredient: IngredientDraft) -> Bool {
        let hay = [
            ingredient.displayName,
            ingredient.refNameLatNom ?? "",
            ingredient.refInnKey ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
        return hay.contains("phenol")
            || hay.contains("phenolum")
            || hay.contains("acidum carbol")
            || hay.contains("acidi carbol")
            || hay.contains("карбол")
            || hay.contains("фенол")
    }

    private static func isGlycerinIngredient(_ ingredient: IngredientDraft) -> Bool {
        let hay = [
            ingredient.displayName,
            ingredient.refNameLatNom ?? "",
            ingredient.refInnKey ?? "",
            ingredient.refSolventType ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
        return hay.contains("glycer")
            || hay.contains("glycerin")
            || hay.contains("glycerinum")
            || hay.contains("гліцерин")
            || hay.contains("глицерин")
    }

    private static func isTinctureIngredient(_ ingredient: IngredientDraft) -> Bool {
        if ingredient.rpPrefix == .tincture { return true }
        let hay = [
            ingredient.displayName,
            ingredient.refNameLatNom ?? "",
            ingredient.refInnKey ?? "",
            ingredient.refType ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
        return hay.contains("tinct")
            || hay.contains("настойк")
            || hay.contains("настоянк")
    }

    private static func isStableHalideWithoutExplicitPhotolability(_ ingredient: IngredientDraft) -> Bool {
        let hay = [
            ingredient.displayName,
            ingredient.refNameLatNom ?? "",
            ingredient.refInnKey ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
        let hasBromide = hay.contains("natrii bromid")
            || hay.contains("kalii bromid")
            || hay.contains("sodium bromide")
            || hay.contains("potassium bromide")
            || hay.contains("натрия бромид")
            || hay.contains("натрію бромід")
            || hay.contains("калия бромид")
            || hay.contains("калію бромід")
        let hasHydrobromide = hay.contains("hydrobromid")
            || hay.contains("гидробромид")
            || hay.contains("гідробромід")
        return hasBromide && !hasHydrobromide
    }

    private static func markerMatch(ingredient: IngredientDraft, keys: [String], values: [String]) -> Bool {
        ingredient.referenceHasMarkerValue(keys: keys, expectedValues: values)
            || ingredient.referenceContainsMarkerToken(values)
    }
}
