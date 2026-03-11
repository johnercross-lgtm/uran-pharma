import Foundation

enum StrongPreparationMethod: Hashable, Codable, Sendable {
    case directWeighing
    case trituration(ratio: Int)
    case dissolveFirst
    case dissolveInMinimalVolume(volumeMl: Double)
}

struct StrongDoseValidation: Hashable, Codable, Sendable {
    let ingredientId: UUID
    let ingredientName: String
    let perDoseG: Double?
    let perDayG: Double?
    let perDoseLimitG: Double?
    let perDayLimitG: Double?
    let frequencyPerDay: Int?
    let exceedsPerDose: Bool
    let exceedsPerDay: Bool
    let overrideAccepted: Bool
    let requiresNumericAndTextDose: Bool
}

struct StrongControlResult: Hashable, Codable, Sendable {
    let ingredientId: UUID
    let ingredientName: String
    let method: StrongPreparationMethod
    let doseValidation: StrongDoseValidation
    let storage: String
    let packaging: [String]
    let requiredLabels: [String]
    let mixingInstructions: [String]
    let ppkNotes: [String]
    let physicalWarnings: [String]
    let blockingWarnings: [String]
}

enum StrongControl {
    static let microDoseThresholdG = 0.05
    static let minimumDoseMassG = 0.3
    static let internalPrecision = 0.000001
    static let defaultDiluent = "Saccharum lactis"

    static func containsListB(draft: ExtempRecipeDraft) -> Bool {
        draft.ingredients.contains(where: { !$0.isAd && !$0.isQS && $0.isReferenceListB })
    }

    static func resolve(draft: ExtempRecipeDraft) -> (results: [StrongControlResult], powderTechnology: PowderTechnologyResult?) {
        var effectiveDraft = draft
        effectiveDraft.formMode = SignaUsageAnalyzer.effectiveFormMode(for: effectiveDraft)

        let listBIngredients = effectiveDraft.ingredients.filter { !$0.isAd && !$0.isQS && $0.isReferenceListB }
        guard !listBIngredients.isEmpty else { return ([], nil) }

        let powderTechnology = resolvePowderTechnology(draft: effectiveDraft, listBIngredients: listBIngredients)
        let results = listBIngredients.map { ingredient in
            buildResult(
                ingredient: ingredient,
                draft: effectiveDraft,
                powderTechnology: powderTechnology,
                hasListA: PoisonControl.containsListA(draft: effectiveDraft)
            )
        }

        return (results, powderTechnology)
    }

    private static func buildResult(
        ingredient: IngredientDraft,
        draft: ExtempRecipeDraft,
        powderTechnology: PowderTechnologyResult?,
        hasListA: Bool
    ) -> StrongControlResult {
        let name = displayName(ingredient)
        let effectiveForm = SignaUsageAnalyzer.effectiveFormMode(for: draft)
        let method = resolvePreparationMethod(ingredient: ingredient, draft: draft)
        let doseValidation = validateDose(ingredient: ingredient, draft: draft)
        let physicalValidation = validatePhysicalProperties(ingredient: ingredient, draft: draft)
        let storage = "Окремо, шафа \"Б\" (Heroica)"

        var packaging = physicalValidation.packaging
        let requiredLabels = ["Зберігати в недоступному для дітей місці"]
        var instructions: [String] = []

        switch effectiveForm {
        case .powders:
            if let powderTechnology, powderTechnology.requiresPoreRubbing {
                let fillerName = powderTechnology.fillerIngredientName ?? defaultDiluent
                instructions.append("Спочатку затерти пори ступки частиною \(fillerName)")
                if let plan = powderTechnology.triturationPlans.first(where: { $0.ingredientId == ingredient.id }),
                   let ratio = plan.ratio
                {
                    instructions.append("Внести Trituratio \(name) 1:\(ratio) у затерту ступку")
                } else {
                    instructions.append("Внести \(name) у затерту ступку")
                }
                instructions.append("Додати решту наповнювача методом геометричного розведення")
            } else {
                instructions.append("Затерти пори ступки невеликою кількістю індиферентного наповнювача")
                instructions.append("Внести \(name) та змішувати методом геометричного розведення")
            }
        case .solutions, .drops:
            instructions.append(contentsOf: liquidMixingInstructions(
                ingredient: ingredient,
                draft: draft,
                ingredientName: name,
                hasListA: hasListA
            ))
        case .ointments:
            if WaterSolubilityHeuristics.hasExplicitWaterSolubility(ingredient.refSolubility) {
                instructions.append("Розчинити \(name) у мінімальному об’ємі очищеної води")
            } else {
                instructions.append("Ретельно розтерти \(name) з частиною основи")
            }
            instructions.append("Ввести у мазеву основу методом геометричного розведення")
        case .suppositories:
            instructions.append("Ретельно розтерти \(name) з частиною основи")
            instructions.append("Ввести у супозиторну масу при постійному перемішуванні")
        case .auto:
            instructions.append("Застосувати технологію фактичної лікарської форми")
        }

        var ppkNotes: [String] = [
            doseValidation.requiresNumericAndTextDose
                ? "Перевірено дози сильнодіючої речовини"
                : "Для зовнішнього застосування контроль ВРД/ВСД не застосовується; контролюється концентрація",
            "Зберігання: \(storage)",
            "Маркування штангласу: червоний шрифт на білому фоні"
        ]
        if packaging.contains("Вощений/парафінований папір") {
            ppkNotes.append("Через гігроскопічність потрібен вощений/парафінований папір")
        }
        if packaging.contains("Оранжеве скло / темний пакет") {
            ppkNotes.append("Світлочутлива речовина: потрібен захист від світла")
        }
        ppkNotes.append(contentsOf: physicalValidation.notes)

        if packaging.isEmpty {
            packaging = defaultPackaging(for: effectiveForm)
        }

        return StrongControlResult(
            ingredientId: ingredient.id,
            ingredientName: name,
            method: method,
            doseValidation: doseValidation,
            storage: storage,
            packaging: packaging,
            requiredLabels: requiredLabels,
            mixingInstructions: instructions,
            ppkNotes: ppkNotes,
            physicalWarnings: physicalValidation.warnings,
            blockingWarnings: physicalValidation.blockingWarnings
        )
    }

    private static func resolvePowderTechnology(
        draft: ExtempRecipeDraft,
        listBIngredients: [IngredientDraft]
    ) -> PowderTechnologyResult? {
        guard SignaUsageAnalyzer.effectiveFormMode(for: draft) == .powders else { return nil }

        let dosesCount = max(1, draft.numero ?? 1)
        let plans = listBIngredients.map { ingredient in
            resolveTrituration(ingredient: ingredient, draft: draft, dosesCount: dosesCount)
        }
        let planByIngredientId = Dictionary(uniqueKeysWithValues: plans.map { ($0.ingredientId, $0) })

        let carrierIngredients = draft.ingredients.filter { ingredient in
            !ingredient.isAd
                && !ingredient.isQS
                && ingredient.unit.rawValue == "g"
                && ingredient.amountValue > 0
                && isCompatibleDefaultDiluentCarrier(ingredient)
        }

        let originalFillerMass = roundInternal(carrierIngredients.reduce(0.0) { partial, ingredient in
            partial + resolvedTotalMassG(for: ingredient, draft: draft, dosesCount: dosesCount)
        })
        let requiredPlans = plans.filter(\.required)
        let requiredTriturationDiluentMass = roundInternal(requiredPlans.reduce(0.0) { $0 + max(0, $1.totalTriturationMass - $1.totalActiveMass) })

        var remainingReplacement = requiredTriturationDiluentMass
        var totalPowderBeforeAutoFill = 0.0

        for ingredient in draft.ingredients {
            guard !ingredient.isAd, !ingredient.isQS else { continue }
            guard ingredient.unit.rawValue == "g", ingredient.amountValue > 0 else { continue }

            let totalMass = resolvedTotalMassG(for: ingredient, draft: draft, dosesCount: dosesCount)
            if let plan = planByIngredientId[ingredient.id], plan.required {
                totalPowderBeforeAutoFill += plan.totalTriturationMass
                continue
            }

            if isCompatibleDefaultDiluentCarrier(ingredient), remainingReplacement > 0 {
                let reduction = min(totalMass, remainingReplacement)
                totalPowderBeforeAutoFill += max(0, totalMass - reduction)
                remainingReplacement = roundInternal(remainingReplacement - reduction)
                continue
            }

            totalPowderBeforeAutoFill += totalMass
        }

        totalPowderBeforeAutoFill = roundInternal(totalPowderBeforeAutoFill)
        let requiredTotalMass = roundInternal(max(totalPowderBeforeAutoFill, minimumDoseMassG * Double(dosesCount)))
        let fillerAdded = roundInternal(max(0, requiredTotalMass - totalPowderBeforeAutoFill))
        let totalPowderMass = roundInternal(totalPowderBeforeAutoFill + fillerAdded)
        let doseMass = roundInternal(totalPowderMass / Double(dosesCount))
        let allowedDeviationPercent = PowdersCalculator.allowedDeviationPercentPowder(perDoseG: doseMass)
        let lowerDeviationMass = roundInternal(doseMass * (1.0 - allowedDeviationPercent / 100.0))
        let upperDeviationMass = roundInternal(doseMass * (1.0 + allowedDeviationPercent / 100.0))
        let correctedFillerMass = carrierIngredients.isEmpty
            ? nil
            : roundInternal(max(0, originalFillerMass - requiredTriturationDiluentMass) + fillerAdded)
        let totalDiluentMass = roundInternal((correctedFillerMass ?? fillerAdded) + requiredTriturationDiluentMass)
        let balancedTotal = roundInternal(doseMass * Double(dosesCount))
        let roundingCorrection = roundInternal(totalPowderMass - balancedTotal)
        let fillerIngredient = carrierIngredients.first

        return PowderTechnologyResult(
            dosesCount: dosesCount,
            triturationPlans: requiredPlans,
            totalActiveMass: roundInternal(plans.reduce(0.0) { $0 + $1.totalActiveMass }),
            correctedFillerMass: correctedFillerMass,
            originalFillerMass: carrierIngredients.isEmpty ? nil : originalFillerMass,
            fillerIngredientName: fillerIngredient.map { displayName($0) },
            fillerIngredientId: fillerIngredient?.id,
            totalDiluentMass: totalDiluentMass,
            totalPowderMass: totalPowderMass,
            doseMass: doseMass,
            fillerAdded: fillerAdded,
            roundingCorrection: roundingCorrection,
            allowedDeviationPercent: allowedDeviationPercent,
            lowerDeviationMass: lowerDeviationMass,
            upperDeviationMass: upperDeviationMass,
            requiresPoreRubbing: !listBIngredients.isEmpty
        )
    }

    private static func resolvePreparationMethod(ingredient: IngredientDraft, draft: ExtempRecipeDraft) -> StrongPreparationMethod {
        switch SignaUsageAnalyzer.effectiveFormMode(for: draft) {
        case .powders:
            let dosesCount = max(1, draft.numero ?? 1)
            let plan = resolveTrituration(ingredient: ingredient, draft: draft, dosesCount: dosesCount)
            if let ratio = plan.ratio {
                return .trituration(ratio: ratio)
            }
            return .directWeighing
        case .solutions, .drops:
            return .dissolveFirst
        case .ointments:
            if WaterSolubilityHeuristics.hasExplicitWaterSolubility(ingredient.refSolubility) {
                let totalMassG = resolvedTotalMassG(for: ingredient, draft: draft, dosesCount: max(1, draft.numero ?? 1))
                return .dissolveInMinimalVolume(volumeMl: roundInternal(max(0.1, totalMassG)))
            }
            return .directWeighing
        case .suppositories, .auto:
            return .directWeighing
        }
    }

    private static func resolveTrituration(
        ingredient: IngredientDraft,
        draft: ExtempRecipeDraft,
        dosesCount: Int
    ) -> TriturationPlan {
        let totalActiveMass = roundInternal(resolvedTotalMassG(for: ingredient, draft: draft, dosesCount: dosesCount))
        let requires = SignaUsageAnalyzer.effectiveFormMode(for: draft) == .powders
            && (totalActiveMass > 0 && totalActiveMass < microDoseThresholdG)
        guard requires else {
            return TriturationPlan(
                ingredientId: ingredient.id,
                ingredientName: displayName(ingredient),
                required: false,
                ratio: nil,
                totalActiveMass: roundInternal(totalActiveMass),
                totalTriturationMass: roundInternal(totalActiveMass),
                triturationPerDose: roundInternal(totalActiveMass / Double(max(1, dosesCount))),
                diluent: defaultDiluent
            )
        }

        let totalTriturationMass = roundInternal(totalActiveMass * 10.0)
        return TriturationPlan(
            ingredientId: ingredient.id,
            ingredientName: displayName(ingredient),
            required: true,
            ratio: 10,
            totalActiveMass: roundInternal(totalActiveMass),
            totalTriturationMass: totalTriturationMass,
            triturationPerDose: roundInternal(totalTriturationMass / Double(max(1, dosesCount))),
            diluent: defaultDiluent
        )
    }

    private static func validateDose(ingredient: IngredientDraft, draft: ExtempRecipeDraft) -> StrongDoseValidation {
        let effectiveForm = SignaUsageAnalyzer.effectiveFormMode(for: draft)
        if shouldUseConcentrationControlOnly(ingredient: ingredient, draft: draft, effectiveForm: effectiveForm) {
            return StrongDoseValidation(
                ingredientId: ingredient.id,
                ingredientName: displayName(ingredient),
                perDoseG: nil,
                perDayG: nil,
                perDoseLimitG: nil,
                perDayLimitG: nil,
                frequencyPerDay: nil,
                exceedsPerDose: false,
                exceedsPerDay: false,
                overrideAccepted: false,
                requiresNumericAndTextDose: false
            )
        }

        let frequency = parseFrequency(from: draft.signa)
        let perDose = resolvedPerDoseMassG(for: ingredient, draft: draft, effectiveForm: effectiveForm)
        let perDay = perDose.flatMap { dose in
            frequency.map { roundInternal(dose * Double($0)) }
        }
        let perDoseLimit = resolvedPerDoseLimit(ingredient: ingredient, ageYears: draft.patientAgeYears)
        let perDayLimit = resolvedPerDayLimit(ingredient: ingredient, ageYears: draft.patientAgeYears)
        let exceedsPerDose = perDoseLimit.map { (perDose ?? 0) > $0 } ?? false
        let exceedsPerDay = perDayLimit.map { (perDay ?? 0) > $0 } ?? false
        let overrideAccepted = (exceedsPerDose || exceedsPerDay) && signaHasAuthorizedOverride(draft.signa)

        return StrongDoseValidation(
            ingredientId: ingredient.id,
            ingredientName: displayName(ingredient),
            perDoseG: perDose.map { roundInternal($0) },
            perDayG: perDay.map { roundInternal($0) },
            perDoseLimitG: perDoseLimit.map { roundInternal($0) },
            perDayLimitG: perDayLimit.map { roundInternal($0) },
            frequencyPerDay: frequency,
            exceedsPerDose: exceedsPerDose,
            exceedsPerDay: exceedsPerDay,
            overrideAccepted: overrideAccepted,
            requiresNumericAndTextDose: true
        )
    }

    private static func validatePhysicalProperties(
        ingredient: IngredientDraft,
        draft: ExtempRecipeDraft
    ) -> (packaging: [String], warnings: [String], notes: [String], blockingWarnings: [String]) {
        let effectiveForm = SignaUsageAnalyzer.effectiveFormMode(for: draft)
        let solventType = NonAqueousSolventCatalog.primarySolvent(in: draft)?.type
        var packaging = defaultPackaging(for: effectiveForm)
        var warnings: [String] = []
        var notes: [String] = []
        var blockingWarnings: [String] = []

        if effectiveForm == .powders, isHygroscopic(ingredient) {
            packaging.append("Вощений/парафінований папір")
            warnings.append("Гігроскопічна речовина: потрібен вощений/парафінований папір")
        }

        if isLightSensitive(ingredient) {
            packaging.append("Оранжеве скло / темний пакет")
            warnings.append("Світлочутлива речовина: потрібен захист від світла")
        }

        if isThermolabile(ingredient) {
            notes.append("Не нагрівати вище 40°C")
        }

        if (effectiveForm == .solutions || effectiveForm == .drops),
           let issue = solubilityBlockingIssue(for: ingredient, draft: draft)
        {
            blockingWarnings.append(issue)
        }

        if solventType == .ethanol {
            packaging.append("Щільно закоркований скляний флакон")
            notes.append("Спиртову систему готують у сухому флаконі без нагрівання")
            if isVolatileAlcoholSolute(ingredient) {
                notes.append("Летка речовина: мінімізувати контакт із повітрям")
            }
        }

        return (deduplicated(packaging), warnings, deduplicated(notes), blockingWarnings)
    }

    private static func defaultPackaging(for form: FormMode) -> [String] {
        switch form {
        case .powders:
            return ["Паперові капсули"]
        case .solutions, .drops:
            return ["Скляний флакон відповідної місткості"]
        case .ointments:
            return ["Банка або туба відповідної місткості"]
        case .suppositories:
            return ["Контурне пакування / вощені капсули"]
        case .auto:
            return []
        }
    }

    private static func solubilityBlockingIssue(for ingredient: IngredientDraft, draft: ExtempRecipeDraft) -> String? {
        let totalVolumeMl = max(
            0,
            draft.explicitLiquidTargetMl
                ?? draft.legacyAdOrQsLiquidTargetMl
                ?? draft.ingredients.reduce(0.0) { partial, current in
                    if current.isAd || current.isQS { return partial }
                    return partial + effectiveLiquidMl(current, draft: draft)
                }
        )
        let totalMassG = inferActiveMassG(for: ingredient, draft: draft)
        guard totalVolumeMl > 0, totalMassG > 0 else { return nil }

        let concentration = totalMassG / totalVolumeMl
        let normalized = WaterSolubilityHeuristics.normalizedSolubility(ingredient.refSolubility)
        if normalized.isEmpty { return nil }

        if WaterSolubilityHeuristics.isWaterInsolubleOrSparinglySoluble(normalized) {
            if let denominator = waterRatioDenominator(in: normalized) {
                let limitConcentration = 1.0 / denominator
                if concentration > limitConcentration {
                    return "Речовина не розчиниться у заданій концентрації, потрібен інший розчинник або зміна лікарської форми"
                }
            } else {
                return "Речовина не розчиниться у заданій концентрації, потрібен інший розчинник або зміна лікарської форми"
            }
        }

        if let denominator = waterRatioDenominator(in: normalized) {
            let limitConcentration = 1.0 / denominator
            if concentration > limitConcentration {
                return "Речовина не розчиниться у заданій концентрації, потрібен інший розчинник або зміна лікарської форми"
            }
        }

        return nil
    }

    private static func waterRatioDenominator(in normalized: String) -> Double? {
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        guard let match = ratioRegex.firstMatch(in: normalized, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: normalized)
        else {
            return nil
        }

        let value = normalized[valueRange].replacingOccurrences(of: ",", with: ".")
        return Double(value)
    }

    private static func isHygroscopic(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHaystack(for: ingredient)
        return hay.contains("гігроскоп") || hay.contains("гигроскоп") || hay.contains("hygroscop")
    }

    private static func isLightSensitive(_ ingredient: IngredientDraft) -> Bool {
        ingredient.isReferenceLightSensitive
            || ingredient.referenceHasMarkerValue(
                keys: ["light_sensitive", "instruction_id", "process_note", "storage"],
                expectedValues: [
                    "lightprotected",
                    "protectfromlight",
                    "light_sensitive",
                    "amberglass",
                    "darkglass",
                    "темнескло",
                    "захищеновідсвітла"
                ]
            )
            || ingredient.referenceContainsMarkerToken([
                "lightprotected",
                "light_sensitive",
                "amberglass",
                "darkglass"
            ])
    }

    private static func isThermolabile(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHaystack(for: ingredient)
        return hay.contains("не нагрівати")
            || hay.contains("не нагревать")
            || hay.contains("термолаб")
            || hay.contains("t > 40")
            || hay.contains(">40")
            || hay.contains("40°")
            || hay.contains("40c")
    }

    private static func normalizedHaystack(for ingredient: IngredientDraft) -> String {
        [
            ingredient.refNameLatNom,
            ingredient.refNameLatGen,
            ingredient.displayName,
            ingredient.refStorage,
            ingredient.refInteractionNotes,
            ingredient.refOintmentNote,
            ingredient.refPrepMethod,
            ingredient.refPharmActivity
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .joined(separator: " ")
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func signaHasAuthorizedOverride(_ signa: String) -> Bool {
        let trimmed = signa.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.contains("!")
    }

    private static func shouldUseConcentrationControlOnly(
        ingredient: IngredientDraft,
        draft: ExtempRecipeDraft,
        effectiveForm: FormMode
    ) -> Bool {
        guard effectiveForm == .solutions || effectiveForm == .drops else { return false }
        if NonAqueousSolventCatalog.concentrationControlProfile(for: ingredient)?.isConcentrationControlOnly == true {
            return true
        }
        let semantics = SignaUsageAnalyzer.analyze(signa: draft.signa)
        let s = semantics.normalizedSigna
        let hasEarOrNoseRoute = semantics.isNasalRoute
            || s.contains("вух")
            || s.contains("уха")
            || s.contains("ear")
            || s.contains("otic")
            || s.contains("нос")
        let hasExternalSmearMarker = s.contains("змащ")
            || s.contains("смаз")
            || s.contains("мазати")
            || s.contains("смазыват")
        if semantics.isExternalRoute {
            return true
        }
        return hasEarOrNoseRoute || hasExternalSmearMarker
    }

    private static func resolvedPerDoseMassG(
        for ingredient: IngredientDraft,
        draft: ExtempRecipeDraft,
        effectiveForm: FormMode
    ) -> Double? {
        let dosesCount = max(1, draft.numero ?? 1)
        let signaSemantics = SignaUsageAnalyzer.analyze(signa: draft.signa)
        switch effectiveForm {
        case .powders, .suppositories:
            let total = resolvedTotalMassG(for: ingredient, draft: draft, dosesCount: dosesCount)
            guard total > 0 else { return nil }
            return roundInternal(total / Double(dosesCount))
        case .solutions:
            if signaSemantics.hasDropsDose {
                return resolvedPerDoseMassByDrops(for: ingredient, draft: draft)
            }
            guard let intakeMl = parseSingleLiquidDoseMl(from: draft.signa), intakeMl > 0 else { return nil }
            let totalVolume = max(0, draft.explicitLiquidTargetMl ?? draft.legacyAdOrQsLiquidTargetMl ?? draft.ingredients.reduce(0.0) { $0 + effectiveLiquidMl($1, draft: draft) })
            guard totalVolume > 0 else { return nil }
            let totalMass = inferActiveMassG(for: ingredient, draft: draft)
            guard totalMass > 0 else { return nil }
            return roundInternal(totalMass * intakeMl / totalVolume)
        case .drops:
            return resolvedPerDoseMassByDrops(for: ingredient, draft: draft)
        case .ointments, .auto:
            return nil
        }
    }

    private static func resolvedPerDoseMassByDrops(
        for ingredient: IngredientDraft,
        draft: ExtempRecipeDraft
    ) -> Double? {
        guard let dropsPerIntake = parseDropsPerDose(from: draft.signa), dropsPerIntake > 0 else { return nil }
        let totalMass = inferActiveMassG(for: ingredient, draft: draft)
        var totalDrops = draft.ingredients.reduce(0.0) { partial, current in
            if current.isAd || current.isQS { return partial }
            let volume = effectiveLiquidMl(current, draft: draft)
            guard volume > 0, let resolution = DropsAnalysis.resolvedDropsPerMl(for: current, draft: draft) else { return partial }
            return partial + (volume * resolution.value)
        }
        if totalDrops <= 0,
           let totalVolume = resolvedTotalVolumeMlForDropsDoseControl(draft: draft),
           totalVolume > 0,
           let primary = NonAqueousSolventCatalog.primarySolvent(in: draft)
        {
            let ethanolStrength = primary.type == .ethanol
                ? NonAqueousSolventCatalog.requestedEthanolStrength(from: primary.ingredient)
                : nil
            if let gttsPerMl = NonAqueousSolventCatalog.standardDropsPerMl(for: primary.type, ethanolStrength: ethanolStrength),
               gttsPerMl > 0 {
                totalDrops = totalVolume * gttsPerMl
            }
        }
        guard totalMass > 0, totalDrops > 0 else { return nil }
        let doses = max(1.0, floor(totalDrops / dropsPerIntake))
        return roundInternal(totalMass / doses)
    }

    private static func resolvedTotalVolumeMlForDropsDoseControl(draft: ExtempRecipeDraft) -> Double? {
        if let explicit = draft.explicitLiquidTargetMl, explicit > 0 {
            return explicit
        }
        if let legacy = draft.legacyAdOrQsLiquidTargetMl, legacy > 0 {
            return legacy
        }

        let measuredMl = draft.ingredients.reduce(0.0) { partial, ingredient in
            if ingredient.isAd || ingredient.isQS { return partial }
            return partial + effectiveLiquidMl(ingredient, draft: draft)
        }
        if measuredMl > 0 {
            return measuredMl
        }

        guard let primary = NonAqueousSolventCatalog.primarySolvent(in: draft),
              primary.type.isViscous
        else { return nil }

        let density = primary.type == .glycerin
            ? 1.25
            : NonAqueousSolventCatalog.density(for: primary.type, fallback: primary.ingredient?.refDensity)
        guard let density, density > 0 else { return nil }

        let totalMassG = draft.ingredients.reduce(0.0) { partial, ingredient in
            guard !ingredient.isAd, !ingredient.isQS else { return partial }
            guard let mass = ingredientMassGForVolumeEstimate(ingredient, draft: draft, primarySolvent: primary) else { return partial }
            return partial + mass
        }
        guard totalMassG > 0 else { return nil }
        return totalMassG / density
    }

    private static func ingredientMassGForVolumeEstimate(
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
            if PurifiedWaterHeuristics.isPurifiedWater(ingredient) {
                return ingredient.amountValue
            }
        }

        let inferred = draft.inferredActiveMassG(for: ingredient)
        return inferred > 0 ? inferred : nil
    }

    private static func inferActiveMassG(for ingredient: IngredientDraft, draft: ExtempRecipeDraft) -> Double {
        if ingredient.unit.rawValue == "g", ingredient.amountValue > 0 {
            let effectiveForm = SignaUsageAnalyzer.effectiveFormMode(for: draft)
            switch ingredient.scope {
            case .perDose where effectiveForm == .powders || effectiveForm == .suppositories:
                return roundInternal(ingredient.amountValue * Double(max(1, draft.numero ?? 1)))
            default:
                return roundInternal(ingredient.amountValue)
            }
        }
        let inferred = draft.inferredActiveMassG(for: ingredient)
        guard inferred > 0 else { return 0 }
        return roundInternal(inferred)
    }

    private static func resolvedTotalMassG(
        for ingredient: IngredientDraft,
        draft: ExtempRecipeDraft,
        dosesCount: Int
    ) -> Double {
        guard ingredient.unit.rawValue == "g", ingredient.amountValue > 0 else { return 0 }
        switch ingredient.scope {
        case .perDose:
            return roundInternal(ingredient.amountValue * Double(dosesCount))
        case .total:
            return roundInternal(ingredient.amountValue)
        case .auto:
            return draft.powderMassMode == .dispensa
                ? roundInternal(ingredient.amountValue * Double(dosesCount))
                : roundInternal(ingredient.amountValue)
        }
    }

    private static func effectiveLiquidMl(_ ingredient: IngredientDraft, draft: ExtempRecipeDraft) -> Double {
        draft.effectiveLiquidVolumeMl(for: ingredient)
    }

    private static func resolvedPerDoseLimit(ingredient: IngredientDraft, ageYears: Int?) -> Double? {
        if let ageYears {
            if ageYears < 1, let value = ingredient.refVrdChild0_1, value > 0 { return value }
            if ageYears >= 1, ageYears <= 6, let value = ingredient.refVrdChild1_6, value > 0 { return value }
            if ageYears > 6, ageYears <= 14, let value = ingredient.refVrdChild7_14, value > 0 { return value }
            if ageYears <= 14, let value = ingredient.refPedsVrdG, value > 0 { return value }
        }
        if let value = ingredient.refVrdG, value > 0 { return value }
        return nil
    }

    private static func resolvedPerDayLimit(ingredient: IngredientDraft, ageYears: Int?) -> Double? {
        if let ageYears, ageYears <= 14, let value = ingredient.refPedsRdG, value > 0 {
            return value
        }
        if let value = ingredient.refVsdG, value > 0 { return value }
        return nil
    }

    private static func parseFrequency(from signa: String) -> Int? {
        SignaFrequencyParser.frequencyPerDay(from: signa)
    }

    private static func parseSingleLiquidDoseMl(from signa: String) -> Double? {
        let s = signa.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }

        let mlPatterns = [
            "(\\d+(?:[\\.,]\\d+)?)\\s*ml",
            "(\\d+(?:[\\.,]\\d+)?)\\s*мл"
        ]
        for pattern in mlPatterns {
            guard let range = s.range(of: pattern, options: .regularExpression) else { continue }
            let match = String(s[range])
            guard let numRange = match.range(of: "\\d+(?:[\\.,]\\d+)?", options: .regularExpression) else { continue }
            return Double(String(match[numRange]).replacingOccurrences(of: ",", with: "."))
        }

        if s.contains("чайн") || s.contains("teaspoon") { return 5 }
        if s.contains("дес") || s.contains("dessert") { return 10 }
        if s.contains("стол") || s.contains("tablespoon") { return 15 }
        return nil
    }

    private static func parseDropsPerDose(from signa: String) -> Double? {
        let s = signa.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }

        let patterns = [
            "(\\d+(?:[\\.,]\\d+)?)\\s*(?:кап\\.|капель|капля|капли|кап)",
            "(\\d+(?:[\\.,]\\d+)?)\\s*(?:к\\.|к)\\b",
            "(\\d+(?:[\\.,]\\d+)?)\\s*(?:gtts\\.|gtts|gtt\\.|gtt|guttae)"
        ]
        for pattern in patterns {
            guard let range = s.range(of: pattern, options: .regularExpression) else { continue }
            let match = String(s[range])
            guard let numRange = match.range(of: "\\d+(?:[\\.,]\\d+)?", options: .regularExpression) else { continue }
            return Double(String(match[numRange]).replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    private static func displayName(_ ingredient: IngredientDraft) -> String {
        let name = (ingredient.refNameLatNom ?? ingredient.displayName).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Subst." : name
    }

    private static func liquidMixingInstructions(
        ingredient: IngredientDraft,
        draft: ExtempRecipeDraft,
        ingredientName: String,
        hasListA: Bool
    ) -> [String] {
        let solventType = NonAqueousSolventCatalog.primarySolvent(in: draft)?.type
        let leadInstruction = hasListA
            ? "Розчинити \(ingredientName) після речовин Списку А, але до інших компонентів"
            : "Розчинити \(ingredientName) на ранньому етапі"

        switch solventType {
        case .ethanol:
            var lines = [
                "Відміряти спирт у сухий флакон",
                leadInstruction + " безпосередньо у спирті"
            ]
            if hasEutecticPartner(for: ingredient, in: draft) {
                lines.append("\(ingredientName) не змішувати насухо з евтектичним партнером; вносити по черзі прямо у спирт")
            }
            if isVolatileAlcoholSolute(ingredient) {
                lines.append("Працювати без нагрівання, швидко і з мінімальним контактом із повітрям")
            }
            lines.append("Спиртовий розчин не фільтрувати звичайно; за потреби лише процідити")
            return lines
        case .ether, .chloroform, .volatileOther, .fattyOil, .mineralOil, .glycerin, .vinylin, .viscousOther:
            return [
                "Внести \(ingredientName) у частину неводного розчинника",
                leadInstruction,
                "Довести неводним розчинником до кінцевої маси/об'єму за технологією"
            ]
        case .none:
            return [
                "Відміряти первинний розчинник",
                hasListA
                    ? "Розчинити \(ingredientName) після речовин Списку А, але до сиропів або настойок"
                    : "Розчинити \(ingredientName) першим у первинному розчиннику",
                "Процідити розчин перед додаванням настойок або сиропів"
            ]
        }
    }

    private static func isVolatileAlcoholSolute(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHaystack(for: ingredient)
        return hay.contains("menthol")
            || hay.contains("ментол")
            || hay.contains("thymol")
            || hay.contains("тимол")
            || hay.contains("camphor")
            || hay.contains("камфор")
    }

    private static func hasEutecticPartner(for ingredient: IngredientDraft, in draft: ExtempRecipeDraft) -> Bool {
        let ingredientName = normalizedHaystack(for: ingredient)
        guard !ingredientName.isEmpty else { return false }

        let matchingPairs: [[String]] = [
            ["menthol", "thymol"],
            ["menthol", "camphor"],
            ["menthol", "chloral"],
            ["thymol", "camphor"],
            ["thymol", "chloral"],
            ["camphor", "chloral"],
            ["ментол", "тимол"],
            ["ментол", "камфор"],
            ["ментол", "хлорал"],
            ["тимол", "камфор"],
            ["тимол", "хлорал"],
            ["камфор", "хлорал"]
        ]

        return matchingPairs.contains { pair in
            let ingredientMatchesPair = pair.contains { ingredientName.contains($0) }
            guard ingredientMatchesPair else { return false }

            return pair.allSatisfy { marker in
                if ingredientName.contains(marker) {
                    return true
                }
                return draft.ingredients.contains { candidate in
                    guard candidate.id != ingredient.id, !candidate.isAd, !candidate.isQS else { return false }
                    return normalizedHaystack(for: candidate).contains(marker)
                }
            }
        }
    }

    private static func isCompatibleDefaultDiluentCarrier(_ ingredient: IngredientDraft) -> Bool {
        let hay = [
            ingredient.refNameLatNom,
            ingredient.refInnKey,
            ingredient.displayName
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .joined(separator: " ")

        return hay.contains("sacchar")
            || hay.contains("lactos")
            || hay.contains("amylum")
            || hay.contains("starch")
    }

    private static func roundInternal(_ value: Double) -> Double {
        (value / internalPrecision).rounded() * internalPrecision
    }

    private static let ratioRegex = try! NSRegularExpression(
        pattern: #"1\s*:\s*([0-9]+(?:[.,][0-9]+)?)"#,
        options: []
    )
}
