import Foundation

struct OphthalmicDropsBlock: RxProcessingBlock {
    static let blockId = "ophthalmic_drops"
    let id = blockId

    private struct IsoResult {
        let naclG: Double
        let notes: [String]
        let issues: [RxIssue]
    }

    func apply(context: inout RxPipelineContext) {
        guard context.facts.isDrops else { return }

        context.routeBranch = "ophthalmic_drops"

        let targetVolumeMl = DropsAnalysis.inferTargetVolumeMl(context: context)
        let burette = BuretteSystem.evaluateBurette(draft: context.draft)
        let buretteVolumeMl = burette.totalConcentrateVolumeMl
        let buretteIngredientIds = burette.matchedIngredientIds

        let hasSolidG = context.draft.ingredients.contains {
            !$0.isQS && !$0.isAd &&
            $0.unit.rawValue == "g" &&
            $0.amountValue > 0 &&
            !buretteIngredientIds.contains($0.id)
        }

        let hasLiquidPhase = context.draft.ingredients.contains {
            !$0.isQS && !$0.isAd &&
            DropsAnalysis.effectiveLiquidMl($0, draft: context.draft) > 0
        } || buretteVolumeMl > 0

        let activeIngredients = context.draft.ingredients.filter { !$0.isQS && !$0.isAd }
        let hasGlassFilterOnly = activeIngredients.contains(where: requiresGlassFilterOnly)
        let hasWarmCottonFilter = activeIngredients.contains(where: requiresWarmCottonFilter)
        let markerForcesFiltration = hasGlassFilterOnly || hasWarmCottonFilter || activeIngredients.contains(where: { $0.refFilter })
        let needsFiltration = (hasSolidG && hasLiquidPhase) || markerForcesFiltration
        let filtrationLine = preferredFiltrationLine(
            activeIngredients: activeIngredients,
            needsFiltration: needsFiltration
        )

        context.addStep(TechStep(
            kind: .filtration,
            title: filtrationLine,
            notes: needsFiltration ? "Провести фільтрацію асептично." : "Не потрібна за складом.",
            isCritical: needsFiltration
        ))

        context.addStep(TechStep(
            kind: .sterilization,
            title: "Стерилізація очних крапель",
            notes: "120°C, 8–15 хв (за сумісністю складу).",
            isCritical: true
        ))

        var calcLines: [String] = []

        if targetVolumeMl > 0 {
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
                guard !ing.isQS,
                      !ing.isAd,
                      ing.unit.rawValue == "g",
                      ing.amountValue > 0
                else { return nil }
                if buretteIngredientIds.contains(ing.id) { return nil }

                return (weight: ing.amountValue, kuo: ing.refKuoMlPerG)
            }

            let ad = PharmaCalculator.calculateAdWater(
                targetVolume: targetVolumeMl,
                otherLiquids: otherLiquids,
                solids: solids,
                kuoPolicy: .adaptive
            )

            context.calculations["ophthalmic_water_to_measure_ml"] = format(ad.amountToMeasure)
            if buretteVolumeMl > 0 {
                calcLines.append("Σ(бюреточні концентрати): \(format(buretteVolumeMl)) мл")
            }

            if ad.needsKuo {
                calcLines.append("Враховано КУО: витіснення \(format(ad.displacementVolume)) мл")
                context.calculations["ophthalmic_kuo_displacement_ml"] = format(ad.displacementVolume)
                if ad.missingKuoCount > 0 {
                    context.addIssue(
                        code: "ophthalmic.kuo.missing",
                        severity: .warning,
                        message: "Відсутній КУО для \(ad.missingKuoCount) компонентів — розрахунок приблизний"
                    )
                }
            }

            calcLines.append("Вода для відмірювання: \(format(ad.amountToMeasure)) мл")
        }

        if targetVolumeMl > 0 {
            let iso = calculateIsotonicNaCl(draft: context.draft, targetVolumeMl: targetVolumeMl)
            iso.notes.forEach { calcLines.append($0) }
            iso.issues.forEach { context.issues.append($0) }

            if iso.naclG > 0.0009 {
                calcLines.append("Додати NaCl: \(String(format: "%.3f", iso.naclG)) g")
                context.calculations["ophthalmic_isotonic_nacl_g"] = String(format: "%.3f", iso.naclG)
            }
        }

        let techLines = buildTechLines(
            draft: context.draft,
            toMeasureWaterText: context.calculations["ophthalmic_water_to_measure_ml"] ?? "",
            needsFiltration: needsFiltration,
            activeIngredients: activeIngredients
        )

        let needsDark = DropsAnalysis.requiresDarkGlass(draft: context.draft)
        let packaging = needsDark
            ? "Стерильний флакон-крапельниця (оранжеве скло)"
            : "Стерильний флакон-крапельниця"

        context.appendSection(title: "Розрахунки", lines: calcLines)
        context.appendSection(title: "Технологія", lines: techLines)
        context.appendSection(title: "Оформлення", lines: [
            "Тара: \(packaging)",
            "Маркування: «Очні краплі. Стерильно.»",
            "Не торкатися наконечником ока."
        ])
    }

    private func calculateIsotonicNaCl(
        draft: ExtempRecipeDraft,
        targetVolumeMl: Double
    ) -> IsoResult {

        let naclRequired = 0.009 * targetVolumeMl
        let explicitNaClMass = draft.ingredients
            .filter { !$0.isQS && !$0.isAd && isExplicitNatriiChloridum($0) }
            .compactMap(massInGrams)
            .reduce(0.0, +)
        if explicitNaClMass > 0, abs(explicitNaClMass - naclRequired) <= 0.01 {
            return IsoResult(
                naclG: 0,
                notes: [
                    "Ізотонування (0.9% NaCl): потрібно \(String(format: "%.3f", naclRequired)) g",
                    "Ізотонічність уже забезпечена рецептом (NaCl \(String(format: "%.3f", explicitNaClMass)) g на \(format(targetVolumeMl)) ml)"
                ],
                issues: []
            )
        }

        var sumNaClEq: Double = 0
        var missing: [String] = []

        for ing in draft.ingredients where !ing.isQS && !ing.isAd {
            guard let massG = massInGrams(ing), massG > 0 else { continue }

            if isExplicitNatriiChloridum(ing) {
                // Explicit NaCl directly contributes as NaCl-equivalent mass.
                sumNaClEq += massG
                continue
            }

            if let e = ing.refEFactorNaCl, e > 0 {
                sumNaClEq += e * massG
            } else {
                missing.append(ing.displayName)
            }
        }

        let need = max(0, naclRequired - sumNaClEq)

        var notes: [String] = [
            "Ізотонування (0.9% NaCl): потрібно \(String(format: "%.3f", naclRequired)) g",
            "Внесок речовин (E_Factor): \(String(format: "%.3f", sumNaClEq)) g"
        ]

        var issues: [RxIssue] = []

        if !missing.isEmpty {
            let msg = "Немає E_Factor для: \(missing.joined(separator: ", "))"
            notes.append("⚠ \(msg)")
            issues.append(RxIssue(
                code: "ophthalmic.e.missing",
                severity: .warning,
                message: msg
            ))
        }

        return IsoResult(naclG: need, notes: notes, issues: issues)
    }

    private func isAquaPurificata(_ ing: IngredientDraft) -> Bool {
        PurifiedWaterHeuristics.isPurifiedWater(ing)
    }

    private func isExplicitNatriiChloridum(_ ing: IngredientDraft) -> Bool {
        let hay = [
            ing.displayName,
            ing.refNameLatNom ?? "",
            ing.refNameLatGen ?? "",
            ing.refInnKey ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        return hay.contains("natrii chlorid")
            || hay.contains("natrii chloridi")
            || hay.contains("sodium chlorid")
            || hay.contains("натрію хлорид")
            || hay.contains("натрия хлорид")
    }

    private func massInGrams(_ ing: IngredientDraft) -> Double? {
        let unit = ing.unit.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ing.amountValue > 0 else { return nil }
        switch unit {
        case "g", "гр":
            return ing.amountValue
        case "mg", "мг":
            return ing.amountValue / 1000.0
        case "mcg", "мкг", "µg":
            return ing.amountValue / 1_000_000.0
        case "kg", "кг":
            return ing.amountValue * 1000.0
        default:
            return nil
        }
    }

    private func buildTechLines(
        draft: ExtempRecipeDraft,
        toMeasureWaterText: String,
        needsFiltration: Bool,
        activeIngredients: [IngredientDraft]
    ) -> [String] {

        var lines: [String] = []
        var i = 1

        if !toMeasureWaterText.isEmpty {
            lines.append("\(i). Відміряти \(toMeasureWaterText) мл води")
            i += 1
        }

        for ing in draft.ingredients where !ing.isAd && !ing.isQS {
            lines.append("\(i). Додати \(ing.displayName)")
            i += 1
        }

        lines.append("\(i). \(preferredFiltrationLine(activeIngredients: activeIngredients, needsFiltration: needsFiltration))")
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
        return needsFiltration ? "Профільтрувати асептично через попередньо промитий фільтр" : "Фільтрація не потрібна"
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

    private func format(_ v: Double) -> String {
        if v == floor(v) { return String(Int(v)) }
        return String(format: "%.2f", v)
    }
}
