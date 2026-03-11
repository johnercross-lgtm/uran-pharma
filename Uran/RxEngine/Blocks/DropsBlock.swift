import Foundation

struct DropsBlock: RxProcessingBlock {
    static let blockId = "drops"
    let id = blockId

    func apply(context: inout RxPipelineContext) {
        let signa = context.draft.signa
        let signaSemantics = SignaUsageAnalyzer.analyze(signa: signa)
        let signaToken = signa.lowercased()
        let isOphthalmic = context.draft.isOphthalmicDrops
            || signaSemantics.isEyeRoute
            || DropsAnalysis.isOphthalmic(signa: signa)
        let isNasal = signaSemantics.isNasalRoute
            || signaToken.contains("капли в нос")
            || signaToken.contains("краплі в ніс")
            || signaToken.contains("guttae nasales")
        let isInternal = !isOphthalmic
            && !isNasal
            && !signaSemantics.isExternalRoute
            && !signaSemantics.isRinseOrGargle
            && !signaSemantics.isRectalOrVaginalRoute

        context.routeBranch = isNasal
            ? "nasal_drops"
            : (isOphthalmic ? "ophthalmic_drops" : (isInternal ? "internal_drops" : "drops"))

        let nonAqueousSolvent = NonAqueousSolventCatalog.primarySolvent(in: context.draft)
        let targetVolumeMl = DropsAnalysis.inferTargetVolumeMl(context: context)
        let burette = BuretteSystem.evaluateBurette(draft: context.draft)
        let buretteVolumeMl = burette.totalConcentrateVolumeMl
        let buretteIngredientIds = burette.matchedIngredientIds

        let hasSolidG = context.draft.ingredients.contains {
            !$0.isQS && !$0.isAd && $0.unit.rawValue == "g" && !buretteIngredientIds.contains($0.id)
        }

        let hasLiquidPhase = context.draft.ingredients.contains {
            !$0.isQS && !$0.isAd &&
            ($0.unit.rawValue == "ml" || $0.presentationKind == .solution)
        } || buretteVolumeMl > 0

        let activeIngredients = context.draft.ingredients.filter { !$0.isQS && !$0.isAd }
        let hasGlassFilterOnly = activeIngredients.contains(where: requiresGlassFilterOnly)
        let hasWarmCottonFilter = activeIngredients.contains(where: requiresWarmCottonFilter)
        let markerForcesFiltration = hasGlassFilterOnly || hasWarmCottonFilter || activeIngredients.contains(where: { $0.refFilter })
        let needsFiltration = (hasSolidG && hasLiquidPhase) || markerForcesFiltration

        if nonAqueousSolvent == nil {
            let filtrationTitle = preferredFiltrationLine(
                activeIngredients: activeIngredients,
                needsFiltration: needsFiltration
            )
            context.addStep(TechStep(
                kind: .filtration,
                title: filtrationTitle,
                isCritical: needsFiltration
            ))
        }

        var calcLines = DropsAnalysis.buildMeasurementLines(draft: context.draft)

        if nonAqueousSolvent == nil, targetVolumeMl > 0 {
            var otherLiquids = context.draft.ingredients.compactMap { ing -> Double? in
                guard !ing.isQS, !ing.isAd else { return nil }
                if isAquaPurificata(ing) { return nil }
                if buretteIngredientIds.contains(ing.id) { return nil }

                let v = DropsAnalysis.effectiveLiquidMl(ing, draft: context.draft)
                return v > 0 ? v : nil
            }
            if buretteVolumeMl > 0 {
                otherLiquids.append(buretteVolumeMl)
            }

            let solids = context.draft.ingredients.compactMap { ing -> (weight: Double, kuo: Double?)? in
                guard !ing.isQS, !ing.isAd, ing.unit.rawValue == "g", ing.amountValue > 0 else {
                    return nil
                }
                if buretteIngredientIds.contains(ing.id) { return nil }
                return (weight: ing.amountValue, kuo: ing.refKuoMlPerG)
            }

            let adResult = PharmaCalculator.calculateAdWater(
                targetVolume: targetVolumeMl,
                otherLiquids: otherLiquids,
                solids: solids,
                kuoPolicy: .adaptive
            )

            context.calculations["drops_water_to_measure_ml"] = format(adResult.amountToMeasure)
            if buretteVolumeMl > 0 {
                calcLines.append("Σ(бюреточні концентрати): \(format(buretteVolumeMl)) мл")
            }

            if adResult.needsKuo {
                calcLines.append("Враховано КУО: об'єм витіснення \(format(adResult.displacementVolume)) мл")
                context.calculations["drops_kuo_displacement_ml"] = format(adResult.displacementVolume)

                if adResult.missingKuoCount > 0 {
                    context.addIssue(
                        code: "drops.kuo.missing",
                        severity: .warning,
                        message: "Для \(adResult.missingKuoCount) твердих компонентів відсутній КУО"
                    )
                }
            } else {
                calcLines.append("КУО не застосовується (режим q.s. ad V)")
            }

            calcLines.append("Вода для відмірювання (орієнтовно): \(format(adResult.amountToMeasure)) мл")
        }

        var controlLines: [String] = []
        if isNasal {
            controlLines.append("Контроль: оцінювати за концентрацією діючих речовин; пероральний дозовий контроль не застосовується")
        } else {
            let doseCheck = DropsAnalysis.buildDoseChecks(draft: context.draft, signa: signa)
            doseCheck.issues.forEach { context.issues.append($0) }
            controlLines = doseCheck.lines
        }

        let dynamicTechLines: [String] = {
            if nonAqueousSolvent != nil {
                return [
                    "Технологія виготовлення визначається профілем неводного розчинника",
                    "Крапельний блок використовується для метрології, дозового контролю та оформлення флакона-крапельниці"
                ]
            }

            let toMeasureWater = context.calculations["drops_water_to_measure_ml"] ?? ""
            return buildDynamicTechLines(
                draft: context.draft,
                toMeasureWaterText: toMeasureWater,
                needsFiltration: needsFiltration,
                activeIngredients: activeIngredients
            )
        }()

        let needsDarkGlass = DropsAnalysis.requiresDarkGlass(draft: context.draft)
        let packaging = needsDarkGlass ? "Флакон-крапельниця з темного скла" : "Флакон-крапельниця"
        let label = isNasal ? "Краплі в ніс" : (isInternal ? "Внутрішнє" : "Зовнішнє")

        context.appendSection(title: "Розрахунки", lines: calcLines.isEmpty ? ["—"] : calcLines)
        if !controlLines.isEmpty {
            context.appendSection(title: isNasal ? "Контроль концентрації" : "Контроль доз", lines: controlLines)
        }

        context.appendSection(title: "Технологія", lines: dynamicTechLines)
        context.appendSection(title: "Оформлення", lines: [
            "Тара: \(packaging)",
            "Маркування: «\(label)»"
        ])
    }

    private func buildDynamicTechLines(
        draft: ExtempRecipeDraft,
        toMeasureWaterText: String,
        needsFiltration: Bool,
        activeIngredients: [IngredientDraft]
    ) -> [String] {

        var lines: [String] = []

        if !toMeasureWaterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("1. Підготувати підставку та відміряти \(toMeasureWaterText) мл води")
        } else {
            lines.append("1. Підготувати підставку та відміряти частину води/розчинника")
        }

        let sortedIng = draft.ingredients
            .filter { !$0.isAd && !$0.isQS }
            .sorted { priority(for: $0) < priority(for: $1) }

        for ing in sortedIng {
            lines.append("Додати \(ing.displayName) (\(format(ing.amountValue)) \(ing.unit.rawValue))")
        }

        lines.append(preferredFiltrationLine(
            activeIngredients: activeIngredients,
            needsFiltration: needsFiltration
        ))
        lines.append("Відпустити у флаконі з відповідним маркуванням")
        return lines
    }

    private func preferredFiltrationLine(
        activeIngredients: [IngredientDraft],
        needsFiltration: Bool
    ) -> String {
        if activeIngredients.contains(where: requiresGlassFilterOnly) {
            return "Профільтрувати тільки через скляний фільтр або скляну вату; паперові/ватні фільтри не використовувати"
        }
        if activeIngredients.contains(where: requiresWarmCottonFilter) {
            return "Профільтрувати теплим через пухкий ватний тампон"
        }
        return needsFiltration ? "Профільтрувати через попередньо промитий фільтр" : "Фільтрація не потрібна"
    }

    private func markerMatch(_ ing: IngredientDraft, keys: [String], values: [String]) -> Bool {
        ing.referenceHasMarkerValue(keys: keys, expectedValues: values)
            || ing.referenceContainsMarkerToken(values)
    }

    private func requiresGlassFilterOnly(_ ing: IngredientDraft) -> Bool {
        markerMatch(
            ing,
            keys: ["filter_type", "instruction_id", "process_note"],
            values: [
                "glass_filter_only",
                "glassfilteronly",
                "glass_filter",
                "no_organic_filter",
                "avoid_paper_filter"
            ]
        )
    }

    private func requiresWarmCottonFilter(_ ing: IngredientDraft) -> Bool {
        markerMatch(
            ing,
            keys: ["filter_type", "instruction_id", "process_note"],
            values: [
                "warm_cotton_filter",
                "warmcottonfilter",
                "cotton_filter_warm"
            ]
        )
    }

    private func priority(for ing: IngredientDraft) -> Int {
        if ing.unit.rawValue == "g" { return 1 }

        let type = (ing.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if type == "viscous" || type == "solvent" || type == "standardsolution" || type == "liquidstandard" { return 2 }
        if type == "alcohol" || type == "tincture" { return 3 }
        return 4
    }

    private func isAquaPurificata(_ ing: IngredientDraft) -> Bool {
        PurifiedWaterHeuristics.isPurifiedWater(ing)
    }

    private func format(_ v: Double) -> String {
        if v == floor(v) { return String(Int(v)) }
        return String(format: "%.2f", v)
    }
}
