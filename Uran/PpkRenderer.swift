import Foundation

struct PpkRenderer {
    private struct IodideComplexOrderPreparation {
        let waterMl: Double
        let iodideIds: Set<UUID>
        let iodineIds: Set<UUID>
        let hasExplicitWater: Bool
        let hasIodideSolutionCarrier: Bool
        let solventIngredientId: UUID?
    }

    private struct SpecialPpkTemplate {
        let backSide: [PpkSection]
        let faceSide: [PpkSection]
        let control: [PpkSection]
    }

    func renderPpk(
        draft: ExtempRecipeDraft,
        plan: TechPlan,
        issues: [RxIssue],
        sections: [PpkSection] = [],
        routeBranch: String? = nil,
        activatedBlocks: [String] = [],
        powderTechnology: PowderTechnologyResult? = nil
    ) -> String {
        let document = buildDocument(
            draft: draft,
            plan: plan,
            issues: issues,
            sections: sections,
            routeBranch: routeBranch,
            activatedBlocks: activatedBlocks,
            powderTechnology: powderTechnology
        )

        var lines: [String] = ["ППК"]

        if let routeBranch, !routeBranch.isEmpty {
            lines.append("Гілка: \(routeBranch)")
        }
        if !activatedBlocks.isEmpty {
            lines.append("Блоки: \(activatedBlocks.joined(separator: ", "))")
        }

        appendSide(title: "Зворотний бік (до виготовлення)", sections: document.backSide, to: &lines)
        appendSide(title: "Лицьовий бік (після виготовлення)", sections: document.faceSide, to: &lines)
        appendSide(title: "Контроль", sections: document.control, to: &lines)

        return lines.joined(separator: "\n")
    }

    func buildDocument(
        draft: ExtempRecipeDraft,
        plan: TechPlan,
        issues: [RxIssue],
        sections: [PpkSection] = [],
        routeBranch: String? = nil,
        activatedBlocks _: [String] = [],
        powderTechnology: PowderTechnologyResult? = nil
    ) -> PpkDocument {
        let technologyOrder = buildTechnologyOrder(draft: draft, routeBranch: routeBranch, powderTechnology: powderTechnology)
        let specialTemplate = specialPpkTemplate(draft: draft)
        let backSide = (specialTemplate?.backSide ?? [])
            + buildBackSide(draft: draft, sections: sections, powderTechnology: powderTechnology)
        let faceSide = (specialTemplate?.faceSide ?? [])
            + buildFaceSide(draft: draft, plan: plan, technologyOrder: technologyOrder, powderTechnology: powderTechnology)

        var mergedIssues = deduplicatedIssues(issues)
        var control = (specialTemplate?.control ?? [])
            + buildControl(draft: draft, issues: mergedIssues, sections: sections)
        let autoIssues = autoValidateGeneratedPpk(
            draft: draft,
            backSide: backSide,
            faceSide: faceSide,
            control: control
        )
        if !autoIssues.isEmpty {
            mergedIssues = deduplicatedIssues(mergedIssues + autoIssues)
            control = (specialTemplate?.control ?? [])
                + buildControl(draft: draft, issues: mergedIssues, sections: sections)
        }

        return PpkDocument(
            backSide: backSide,
            faceSide: faceSide,
            control: control,
            technologyOrder: technologyOrder
        )
    }

    private func buildBackSide(
        draft: ExtempRecipeDraft,
        sections: [PpkSection],
        powderTechnology _: PowderTechnologyResult?
    ) -> [PpkSection] {
        var out: [PpkSection] = []

        let inputLines = backInputLines(draft: draft)
        if !inputLines.isEmpty {
            out.append(PpkSection(title: "Вихідні дані", lines: inputLines))
        }

        let normalizationLines = normalizationLines(draft: draft)
        if !normalizationLines.isEmpty {
            out.append(PpkSection(title: "Нормалізація", lines: normalizationLines))
        }

        let calculationLines = sectionsForBackCalculations(sections: sections)
        if !calculationLines.isEmpty {
            out.append(PpkSection(title: "Математичне обґрунтування", lines: calculationLines))
        }

        let stabilityLines = sectionsForBackStability(sections: sections)
        if !stabilityLines.isEmpty {
            out.append(PpkSection(title: "Стабільність", lines: stabilityLines))
        }

        let safetyLines = sectionsForBackSafety(sections: sections)
        if !safetyLines.isEmpty {
            out.append(PpkSection(title: "Допоміжні розрахунки / безпека", lines: safetyLines))
        }

        let supportLines = sectionsForBackSupport(sections: sections)
        if !supportLines.isEmpty {
            out.append(PpkSection(title: "Технологічне обґрунтування", lines: supportLines))
        }

        return out
    }

    private func buildFaceSide(
        draft: ExtempRecipeDraft,
        plan: TechPlan,
        technologyOrder: [TechnologyOrderItem],
        powderTechnology: PowderTechnologyResult?
    ) -> [PpkSection] {
        var out: [PpkSection] = []

        let headerLines = faceHeaderLines(draft: draft)
        if !headerLines.isEmpty {
            out.append(PpkSection(title: "Шапка", lines: headerLines))
        }

        let orderLines = technologyOrder.map { item in
            let amountPart = ([item.amountText, item.unitText].filter { !$0.isEmpty }).joined(separator: " ")
            let notePart = item.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if amountPart.isEmpty {
                return notePart.isEmpty
                    ? "\(item.stepIndex). \(item.ingredientName)"
                    : "\(item.stepIndex). \(item.ingredientName) — \(notePart)"
            }
            return notePart.isEmpty
                ? "\(item.stepIndex). \(item.ingredientName) \(amountPart)"
                : "\(item.stepIndex). \(item.ingredientName) \(amountPart) — \(notePart)"
        }
        if !orderLines.isEmpty {
            out.append(PpkSection(title: "Порядок внесення (TechnologyOrder)", lines: orderLines))
        }

        let operationLines = plan.steps.enumerated().map { idx, step in
            let note = (step.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return note.isEmpty ? "\(idx + 1). \(step.title)" : "\(idx + 1). \(step.title) (\(note))"
        }
        if !operationLines.isEmpty {
            out.append(PpkSection(title: "Ключові операції", lines: operationLines))
        }

        let summaryLines = faceSummaryLines(draft: draft, powderTechnology: powderTechnology)
        if !summaryLines.isEmpty {
            out.append(PpkSection(title: "Підсумок", lines: summaryLines))
        }

        return out
    }

    private func buildControl(
        draft: ExtempRecipeDraft,
        issues: [RxIssue],
        sections: [PpkSection]
    ) -> [PpkSection] {
        var out: [PpkSection] = []

        let qualityLines = explicitSectionLines(sections: sections, matchingAnyOf: ["контроль якості"])
        let synthesizedQuality = qualityLines.isEmpty ? defaultQualityLines(draft: draft) : qualityLines
        if !synthesizedQuality.isEmpty {
            out.append(PpkSection(title: "Фізичний контроль", lines: synthesizedQuality))
        }

        let packagingLines = explicitSectionLines(sections: sections, matchingAnyOf: ["упаковка", "маркування", "оформлення", "зберігання"])
        let rawPackaging = packagingLines.isEmpty ? defaultPackagingLines(draft: draft) : packagingLines
        let sanitizedPackaging = sanitizeStorageClaimsWithoutEvidence(
            rawPackaging,
            draft: draft
        )
        let synthesizedPackaging = harmonizePackagingLines(
            sanitizedPackaging,
            draft: draft
        )
        if !synthesizedPackaging.isEmpty {
            out.append(PpkSection(title: "Оформлення та зберігання", lines: synthesizedPackaging))
        }

        let poisonControlLines = flattenSections(
            sections.filter { normalizedTitle($0.title) == "контроль списку а" }
        )
        if !poisonControlLines.isEmpty {
            out.append(PpkSection(title: "Контроль списку А", lines: poisonControlLines))
        }

        let strongControlLines = flattenSections(
            sections.filter { normalizedTitle($0.title) == "контроль списку б" }
        )
        if !strongControlLines.isEmpty {
            out.append(PpkSection(title: "Контроль списку Б", lines: strongControlLines))
        }

        let warningLines = issues
            .filter { $0.severity == .warning || $0.severity == .blocking }
            .map { "• [\($0.severity.rawValue)] \($0.message)" }
        if !warningLines.isEmpty {
            out.append(PpkSection(title: "Зауваження", lines: warningLines))
        }

        return out
    }

    private func specialPpkTemplate(draft: ExtempRecipeDraft) -> SpecialPpkTemplate? {
        if isLugolGlycerinScenario(draft) {
            return lugolGlycerinTemplate(draft: draft)
        }
        if isHydrophobicSulfurSuspensionScenario(draft) {
            return sulfurSuspensionTemplate(draft: draft)
        }
        if isCastorEmulsionScenario(draft) {
            return castorEmulsionTemplate(draft: draft)
        }
        if isMentholCamphorEutecticScenario(draft) {
            return mentholCamphorEutecticTemplate(draft: draft)
        }
        return nil
    }

    private func isLugolGlycerinScenario(_ draft: ExtempRecipeDraft) -> Bool {
        let active = draft.ingredients.filter { !$0.isAd && !$0.isQS }
        guard active.contains(where: isIodineComponent),
              active.contains(where: isIodideComponent)
        else { return false }
        return active.contains(where: isGlycerinMarker)
            || NonAqueousSolventCatalog.primarySolvent(in: draft)?.type == .glycerin
    }

    private func isHydrophobicSulfurSuspensionScenario(_ draft: ExtempRecipeDraft) -> Bool {
        let hasSulfur = draft.ingredients.contains(where: isSulfurComponent)
        guard hasSulfur else { return false }
        let hasWater = draft.ingredients.contains(where: PurifiedWaterHeuristics.isPurifiedWater)
        let hasOil = draft.ingredients.contains(where: isOilMarker)
        return hasWater && !hasOil
    }

    private func isCastorEmulsionScenario(_ draft: ExtempRecipeDraft) -> Bool {
        let hasCastorOil = draft.ingredients.contains(where: isCastorOilComponent)
        guard hasCastorOil else { return false }
        return draft.ingredients.contains(where: PurifiedWaterHeuristics.isPurifiedWater)
    }

    private func isMentholCamphorEutecticScenario(_ draft: ExtempRecipeDraft) -> Bool {
        let active = draft.ingredients.filter { !$0.isAd && !$0.isQS }
        let hasMenthol = active.contains(where: isMentholComponent)
        let hasCamphor = active.contains(where: isCamphorComponent)
        guard hasMenthol && hasCamphor else { return false }
        let signa = draft.signa.lowercased()
        return signa.contains("зуб") || signa.contains("ротов")
            || signa.contains("dental")
            || SignaUsageAnalyzer.effectiveFormMode(for: draft) == .drops
    }

    private func lugolGlycerinTemplate(draft: ExtempRecipeDraft) -> SpecialPpkTemplate {
        let active = draft.ingredients.filter { !$0.isAd && !$0.isQS }
        let iodineMass = active.filter(isIodineComponent).compactMap(ingredientMassG).reduce(0, +)
        let iodideMass = active.filter(isIodideComponent).compactMap(ingredientMassG).reduce(0, +)
        let explicitWaterMl = active.filter { PurifiedWaterHeuristics.isPurifiedWater($0) }.compactMap { ingredient in
            if ingredient.unit.rawValue == "ml", ingredient.amountValue > 0 { return ingredient.amountValue }
            return nil
        }.reduce(0.0, +)

        let iodineG = iodineMass > 0 ? iodineMass : 1.0
        let iodideG = iodideMass > 0 ? iodideMass : 2.0
        let waterMl = explicitWaterMl > 0 ? explicitWaterMl : 3.0
        let glycerinMass: Double = {
            let glycerin = active.filter(isGlycerinMarker).compactMap(ingredientMassG).reduce(0, +)
            if glycerin > 0 { return glycerin }
            return max(0, 100.0 - iodineG - iodideG - waterMl)
        }()
        let totalMass = iodineG + iodideG + waterMl + glycerinMass

        let back = [
            PpkSection(
                title: "ППК: Solutio Lugoli cum Glycerino",
                lines: [
                    "Тригер Complex Formation: Iodum + Kalii iodidum -> обов'язкове попереднє комплексоутворення (KI3).",
                    "Тригер Solvent Mixture: Aqua purificata + Glycerinum -> основний компонент Glycerinum, метод масовий."
                ]
            ),
            PpkSection(
                title: "Вихідні дані (Склад за Фармакопеєю)",
                lines: [
                    "Iodum — \(formatAmount(iodineG)) g",
                    "Kalii iodidum — \(formatAmount(iodideG)) g",
                    "Aqua purificata — \(formatAmount(waterMl)) ml",
                    "Glycerinum — \(formatAmount(glycerinMass)) g"
                ]
            ),
            PpkSection(
                title: "Математичне обґрунтування",
                lines: [
                    "Метод: масовий (ваговий).",
                    "M_total = \(formatAmount(iodineG)) + \(formatAmount(iodideG)) + \(formatAmount(waterMl)) + \(formatAmount(glycerinMass)) = \(formatAmount(totalMass)) g.",
                    "Йод практично нерозчинний у воді та гліцерині. Розчинення проводять через комплекс KI3 у концентрованому розчині Kalii iodidum.",
                    "Воду для розчинення KI брати у мінімальній кількості: не менше 1:1.5 до маси KI."
                ]
            ),
            PpkSection(
                title: "Допоміжні розрахунки / безпека",
                lines: [
                    "Iodum: летка, забарвлююча речовина; працювати швидко, у рукавичках.",
                    "Контроль доз: зовнішнє застосування, ВРД/ВСД не проводиться.",
                    "Glycerinum відважувати безпосередньо у тарований флакон темного скла."
                ]
            ),
            PpkSection(
                title: "Технологічне обґрунтування",
                lines: [
                    "Форма — істинний розчин; через світлочутливість йоду та гігроскопічність гліцерину виготовлення проводити без нагрівання або з мінімальним підігрівом.",
                    "Звичайний флакон заборонено: тільки темне (оранжеве) скло."
                ]
            )
        ]

        let face = [
            PpkSection(
                title: "Порядок внесення (TechnologyOrder)",
                lines: [
                    "1. Aqua purificata \(formatAmount(waterMl)) ml — у підставку.",
                    "2. Kalii iodidum \(formatAmount(iodideG)) g — розчинити у воді (концентрований розчин).",
                    "3. Iodum \(formatAmount(iodineG)) g — додати до розчину KI, перемішати до повного розчинення.",
                    "4. Glycerinum \(formatAmount(glycerinMass)) g — у тарований флакон темного скла; перенести концентрат та довести до кінцевої маси."
                ]
            ),
            PpkSection(
                title: "Ключові операції",
                lines: [
                    "Підготувати флакон оранжевого скла.",
                    "Розчинити KI у мінімальній кількості води (тригер Complex Formation).",
                    "Додати йод до насиченого розчину KI.",
                    "Змішати концентрат із гліцерином у флаконі відпуску."
                ]
            )
        ]

        let control = [
            PpkSection(
                title: "Контроль (Люголь)",
                lines: [
                    "Фізичний контроль: однорідність, відсутність кристалів йоду.",
                    "Оформлення: флакон оранжевого скла, щільна пробка.",
                    "Маркування: «Зовнішнє», «Зберігати в прохолодному та захищеному від світла місці», «Берегти від дітей»."
                ]
            )
        ]

        return SpecialPpkTemplate(backSide: back, faceSide: face, control: control)
    }

    private func sulfurSuspensionTemplate(draft: ExtempRecipeDraft) -> SpecialPpkTemplate {
        let sulfurMass = draft.ingredients.filter(isSulfurComponent).compactMap(ingredientMassG).reduce(0, +)
        let sulfurG = sulfurMass > 0 ? sulfurMass : 2.0
        let glycerinMass = draft.ingredients.filter(isGlycerinMarker).compactMap(ingredientMassG).reduce(0, +)
        let glycerinG = glycerinMass > 0 ? glycerinMass : sulfurG * 0.5
        let targetMl = inferredTargetValue(from: draft) ?? 100.0
        let waterMl = max(0, targetMl - sulfurG - glycerinG)

        let back = [
            PpkSection(
                title: "Математичне обґрунтування (Suspensio Sulfuris)",
                lines: [
                    "Sulfur praecipitatum — \(formatAmount(sulfurG)) g",
                    "Glycerinum — \(formatAmount(glycerinG)) g (змочувач за правилом Дерягіна: 0.5 x m речовини)",
                    "Aqua purificata — \(formatAmount(waterMl)) ml",
                    "М_total ≈ \(formatAmount(sulfurG + glycerinG + waterMl)) g"
                ]
            )
        ]

        let face = [
            PpkSection(
                title: "Ключові операції (Гідрофобна суспензія)",
                lines: [
                    "1. У ступку помістити Sulfur praecipitatum.",
                    "2. Додати Glycerinum і ретельно розтерти до однорідної кашки.",
                    "3. Поступово додавати Aqua purificata порціями, розтираючи після кожного додавання.",
                    "4. Перенести у флакон; етикетка: «Перед вживанням збовтувати»."
                ]
            )
        ]

        let control = [
            PpkSection(
                title: "Контроль (Суспензія сірки)",
                lines: [
                    "Однорідність після збовтування, відсутність грубих грудок.",
                    "Маркування: «Перед вживанням збовтувати»."
                ]
            )
        ]
        return SpecialPpkTemplate(backSide: back, faceSide: face, control: control)
    }

    private func castorEmulsionTemplate(draft: ExtempRecipeDraft) -> SpecialPpkTemplate {
        let oilMass = draft.ingredients.filter(isCastorOilComponent).compactMap(ingredientMassG).reduce(0, +)
        let oilG = oilMass > 0 ? oilMass : 10.0
        let gelatosaMass = draft.ingredients.filter(isGelatosaComponent).compactMap(ingredientMassG).reduce(0, +)
        let gelatosaG = gelatosaMass > 0 ? gelatosaMass : oilG / 2.0
        let corpusWaterMl = gelatosaG * 1.5
        let targetMl = inferredTargetValue(from: draft) ?? 100.0
        let restWaterMl = max(0, targetMl - oilG - gelatosaG - corpusWaterMl)

        let back = [
            PpkSection(
                title: "Математичне обґрунтування (Emulsio oleosa)",
                lines: [
                    "Oleum Ricini — \(formatAmount(oilG)) g",
                    "Gelatosa — \(formatAmount(gelatosaG)) g (емульгатор = 1/2 маси олії)",
                    "Aqua purificata для корпусу — \(formatAmount(corpusWaterMl)) ml (1.5 x m емульгатора)",
                    "Aqua purificata решта — \(formatAmount(restWaterMl)) ml",
                    "М_total ≈ \(formatAmount(oilG + gelatosaG + corpusWaterMl + restWaterMl)) g"
                ]
            )
        ]

        let face = [
            PpkSection(
                title: "Ключові операції (Олійна емульсія)",
                lines: [
                    "1. Gelatosa + вода для корпусу: дати набрякнути.",
                    "2. Додати Oleum Ricini і розтирати до утворення корпусу емульсії (характерний «тріск»).",
                    "3. Поступово додати решту води при безперервному перемішуванні.",
                    "4. Етикетка: «Перед вживанням збовтувати», «Зберігати у прохолодному місці»."
                ]
            )
        ]

        let control = [
            PpkSection(
                title: "Контроль (Емульсія)",
                lines: [
                    "Однорідність емульсії, відсутність швидкого розшарування.",
                    "Маркування: «Перед вживанням збовтувати»."
                ]
            )
        ]
        return SpecialPpkTemplate(backSide: back, faceSide: face, control: control)
    }

    private func mentholCamphorEutecticTemplate(draft: ExtempRecipeDraft) -> SpecialPpkTemplate {
        let mentholG = draft.ingredients.filter(isMentholComponent).compactMap(ingredientMassG).reduce(0, +)
        let camphorG = draft.ingredients.filter(isCamphorComponent).compactMap(ingredientMassG).reduce(0, +)
        let alcoholMl = inferredTargetValue(from: draft) ?? 10.0

        let back = [
            PpkSection(
                title: "Математичне обґрунтування (Еутектична суміш)",
                lines: [
                    "Mentholum — \(formatAmount(mentholG > 0 ? mentholG : 3.1)) g",
                    "Camphora — \(formatAmount(camphorG > 0 ? camphorG : 6.4)) g",
                    "Alcohol aethylicus 95% — ad \(formatAmount(alcoholMl)) ml",
                    "Проблема: ментол + камфора утворюють евтектику (зрідження без додавання розчинника)."
                ]
            )
        ]

        let face = [
            PpkSection(
                title: "Ключові операції (Еутектика Mentholum + Camphora)",
                lines: [
                    "1. У сухий флакон темного скла помістити Mentholum і Camphora.",
                    "2. Інтенсивно збовтувати/витримати до повного зрідження суміші.",
                    "3. Лише після утворення рідкої евтектики додати спирт/настойку.",
                    "4. Якщо додати спирт одразу до порошків, розчинення суттєво сповільнюється."
                ]
            )
        ]

        let control = [
            PpkSection(
                title: "Контроль (Еутектичні краплі)",
                lines: [
                    "Повна відсутність кристалів ментолу/камфори перед введенням спирту.",
                    "Тара: темне скло, щільна закупорка."
                ]
            )
        ]
        return SpecialPpkTemplate(backSide: back, faceSide: face, control: control)
    }

    private func backInputLines(draft: ExtempRecipeDraft) -> [String] {
        var lines: [String] = []
        lines.append("Форма: \(ppkFormTitle(for: SignaUsageAnalyzer.effectiveFormMode(for: draft)))")

        if let targetValue = draft.normalizedTargetValue {
            let unit = (draft.resolvedTargetUnit?.rawValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let label = unit == "ml" ? "V_total" : "M_total"
            lines.append("\(label): \(formatAmount(targetValue)) \(unit)")
        } else if let inferred = inferredTargetValue(from: draft) {
            lines.append("V_total: \(formatAmount(inferred)) ml (виведено з рецепта)")
        }

        for ingredient in draft.ingredients {
            let name = latinIngredientName(ingredient)
            lines.append("• \(name) — \(ingredientAmountText(ingredient, draft: draft))")
        }
        return lines
    }

    private func ppkFormTitle(for mode: FormMode) -> String {
        switch mode {
        case .solutions:
            return "Розчин"
        case .drops:
            return "Краплі"
        case .powders:
            return "Порошки"
        case .ointments:
            return "Мазь"
        case .suppositories:
            return "Супозиторії"
        case .auto:
            return "Екстемпоральна форма"
        }
    }

    private func normalizationLines(draft: ExtempRecipeDraft) -> [String] {
        var lines: [String] = []
        let repo = StandardSolutionsRepository.shared

        func parsePercent(from text: String) -> Double? {
            let s = text.replacingOccurrences(of: ",", with: ".")
            guard let r = s.range(of: "(\\d{1,2}(?:\\.\\d+)?)\\s*%", options: .regularExpression) else { return nil }
            let m = String(s[r]).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(m)
        }

        if let solutionIngredient = draft.ingredients.first(where: { $0.presentationKind == .solution }),
           let volume = draft.solutionVolumeMl(for: solutionIngredient) ?? inferredTargetValue(from: draft),
           volume > 0 {
            let parsedPercent = draft.solutionDisplayPercent(for: solutionIngredient)
                ?? parsePercent(from: solutionIngredient.refNameLatNom ?? solutionIngredient.displayName)
            if draft.useStandardSolutionsBlock,
               (repo.matchIngredient(solutionIngredient, parsedPercent: parsedPercent) != nil
                || draft.standardSolutionSourceKey != nil) {
                lines.append("Стандартний фармакопейний розчин: розрахунок виконується за формулою розведення X = V·B/A")
                if let source = draft.selectedStandardSolution(repo: repo) {
                    lines.append("Обраний вихідний розчин: \(source.chemicalName)")
                }
                if let stock = draft.standardSolutionManualStockMl,
                   let water = draft.standardSolutionManualWaterMl,
                   stock > 0 || water > 0 {
                    lines.append("Ручний режим: стандартний розчин \(formatAmount(stock)) ml + вода \(formatAmount(water)) ml")
                }
            } else if draft.solutionPercentRepresentsSolventStrength(for: solutionIngredient),
                      let percent = draft.solutionDisplayPercent(for: solutionIngredient) {
                lines.append("Міцність спирту: \(formatAmount(percent))%; об'єм розчинника = \(formatAmount(volume)) ml")
            } else if let percent = draft.solutionActivePercent(for: solutionIngredient) {
                let mass = percent * volume / 100.0
                lines.append("Sol.%: \(formatAmount(percent))%; розрахункова маса сухої речовини = \(formatAmount(mass)) g на \(formatAmount(volume)) ml")
            }
        }

        let standardSolutions = draft.ingredients.filter { $0.presentationKind == .standardSolution }
        if !standardSolutions.isEmpty {
            let items = standardSolutions.map { latinIngredientName($0) }.joined(separator: ", ")
            lines.append("Стандартні/концентровані розчини враховуються як готові об'єми: \(items)")
        }

        if draft.useBuretteSystem {
            lines.append("Бюреточна система активна: концентрати враховуються у ΣV_other_liquids")
        }

        if draft.ingredients.contains(where: { $0.isQS || $0.isAd }) {
            lines.append("ad/q.s.: кінцевий об'єм/масу доводять наприкінці виготовлення")
        }

        return lines
    }

    private func sectionsForBackCalculations(sections: [PpkSection]) -> [String] {
        flattenSections(
            sections.filter { section in
                let key = normalizedTitle(section.title)
                return key.contains("розрах")
                    || key.contains("бюрет")
            }
        )
    }

    private func sectionsForBackStability(sections: [PpkSection]) -> [String] {
        flattenSections(
            sections.filter { section in
                let key = normalizedTitle(section.title)
                return key.contains("стабіль")
            }
        )
    }

    private func sectionsForBackSafety(sections: [PpkSection]) -> [String] {
        flattenSections(
            sections.filter { section in
                let key = normalizedTitle(section.title)
                return key.contains("контроль доз")
                    || key.contains("доз")
            }
        )
    }

    private func sectionsForBackSupport(sections: [PpkSection]) -> [String] {
        flattenSections(
            sections.filter { section in
                let key = normalizedTitle(section.title)
                return key.contains("логіка")
                    || key.contains("технологія виготовлення")
                    || key.contains("технологія списку а")
                    || key.contains("технологія списку б")
            }
        )
    }

    private func faceHeaderLines(draft: ExtempRecipeDraft) -> [String] {
        var lines: [String] = []
        lines.append("Дата: \(formatDate(Date()))")

        let rxNumber = draft.rxNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rxNumber.isEmpty {
            lines.append("№ рецепта: \(rxNumber)")
        }

        let patient = draft.patientName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !patient.isEmpty {
            lines.append("Пацієнт: \(patient)")
        }

        return lines
    }

    private func faceSummaryLines(draft: ExtempRecipeDraft, powderTechnology: PowderTechnologyResult?) -> [String] {
        var lines: [String] = []
        let effectiveFormMode = SignaUsageAnalyzer.effectiveFormMode(for: draft)

        if let powderTechnology, effectiveFormMode == .powders {
            lines.append("M_final: ____ / очікувано \(formatAmount(powderTechnology.totalPowderMass)) g")
        } else if let targetValue = draft.normalizedTargetValue {
            let unit = (draft.resolvedTargetUnit?.rawValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let label = unit == "ml" ? "V_final" : "M_final"
            lines.append("\(label): ____ / очікувано \(formatAmount(targetValue)) \(unit)")
        } else if let inferred = inferredTargetValue(from: draft) {
            lines.append("V_final: ____ / очікувано \(formatAmount(inferred)) ml")
        } else {
            lines.append("V_final / M_final: ____")
        }

        if let n = draft.numero, n > 0 {
            lines.append("n_doses: \(n)")
        }

        lines.append("Підписи: виготовив ____ / перевірив ____ / відпустив ____")
        if draft.ingredients.contains(where: { !$0.isAd && !$0.isQS && $0.isReferenceListA }) {
            lines.append("Список А: обов'язкові два підписи за виготовлення (виготовив + перевірив)")
        }
        return lines
    }

    private func buildTechnologyOrder(
        draft: ExtempRecipeDraft,
        routeBranch: String?,
        powderTechnology: PowderTechnologyResult?
    ) -> [TechnologyOrderItem] {
        if let officinalAlcoholOrder = officinalAlcoholTechnologyOrder(draft: draft) {
            return officinalAlcoholOrder
        }

        let effectiveFormMode = SignaUsageAnalyzer.effectiveFormMode(for: draft)
        if let powderTechnology,
           effectiveFormMode == .powders,
           powderTechnology.requiresPoreRubbing
        {
            if draft.ingredients.contains(where: { !$0.isAd && !$0.isQS && $0.isReferenceListA }) {
                return buildListAPowderTechnologyOrder(draft: draft, powderTechnology: powderTechnology)
            }
            if draft.ingredients.contains(where: { !$0.isAd && !$0.isQS && $0.isReferenceListB }) {
                return buildListBPowderTechnologyOrder(draft: draft, powderTechnology: powderTechnology)
            }
        }
        if isLiquidLike(draft: draft, routeBranch: routeBranch) {
            return buildLiquidTechnologyOrder(draft: draft)
        }

        return buildDefaultTechnologyOrder(draft: draft)
    }

    private func buildLiquidTechnologyOrder(draft: ExtempRecipeDraft) -> [TechnologyOrderItem] {
        if let expanded = expandedSingleAqueousSolutionTechnologyOrder(draft: draft) {
            return applyGlobalPrimarySolventStaging(to: expanded, draft: draft)
        }

        let burette = BuretteSystem.evaluateBurette(draft: draft)
        if draft.useBuretteSystem, !burette.items.isEmpty {
            return buildBuretteTechnologyOrder(draft: draft, burette: burette)
        }

        let iodidePrep = iodideComplexOrderPreparation(draft: draft)
        var ranked: [(ingredient: IngredientDraft, stage: Int, substage: Int, note: String)] = []

        let activeIngredients = draft.ingredients.filter { !$0.isQS }
        for ingredient in activeIngredients {
            let classification = classifyLiquidOrder(
                ingredient: ingredient,
                draft: draft,
                iodidePrep: iodidePrep
            )
            ranked.append((
                ingredient: ingredient,
                stage: classification.stage,
                substage: classification.substage,
                note: classification.note
            ))
        }

        ranked.sort { lhs, rhs in
            if lhs.stage != rhs.stage { return lhs.stage < rhs.stage }
            if lhs.substage != rhs.substage { return lhs.substage < rhs.substage }

            let leftSafety = safetyPriority(lhs.ingredient)
            let rightSafety = safetyPriority(rhs.ingredient)
            if leftSafety != rightSafety { return leftSafety < rightSafety }

            return latinIngredientName(lhs.ingredient) < latinIngredientName(rhs.ingredient)
        }

        var items = ranked.enumerated().map { index, item in
            return TechnologyOrderItem(
                stepIndex: index + 1,
                ingredientId: item.ingredient.id,
                ingredientName: latinIngredientName(item.ingredient),
                amountText: ingredientAmountValueText(item.ingredient, draft: draft),
                unitText: ingredientAmountUnitText(item.ingredient, draft: draft),
                note: item.note,
                source: .ingredient,
                stage: .other
            )
        }

        if let iodidePrep, iodidePrep.waterMl > 0 {
            let insertIndex = items.firstIndex { item in
                guard let ingredientId = item.ingredientId else { return false }
                return iodidePrep.iodideIds.contains(ingredientId)
            } ?? 0

            let waterItem = TechnologyOrderItem(
                stepIndex: 0,
                ingredientId: nil,
                ingredientName: "Aqua purificata",
                amountText: formatAmount(iodidePrep.waterMl),
                unitText: "ml",
                note: iodidePrep.hasExplicitWater
                    ? "додатково для попереднього розчинення йодиду та утворення комплексу"
                    : "для попереднього розчинення йодиду та утворення комплексу"
            )
            items.insert(waterItem, at: insertIndex)
        }

        addIsotonizingNaClItemIfNeeded(items: &items, draft: draft)

        for index in items.indices {
            items[index].stepIndex = index + 1
        }
        return applyGlobalPrimarySolventStaging(to: items, draft: draft)
    }

    private func buildBuretteTechnologyOrder(
        draft: ExtempRecipeDraft,
        burette: BuretteSystem.Result
    ) -> [TechnologyOrderItem] {
        var items: [TechnologyOrderItem] = []
        let validConcentrates = burette.items
            .filter { $0.concentrateVolumeMl > 0 && $0.soluteMassG > 0 }
            .sorted { $0.concentrate.titleRu < $1.concentrate.titleRu }

        let excludedSolutionId = inferredTargetSolutionIngredientId(in: draft)
        let otherLiquids: [(ingredient: IngredientDraft, volumeMl: Double)] = draft.ingredients.compactMap { ingredient in
            guard !ingredient.isAd, !ingredient.isQS else { return nil }
            if burette.matchedIngredientIds.contains(ingredient.id) { return nil }
            if let excludedSolutionId, ingredient.id == excludedSolutionId { return nil }
            if PurifiedWaterHeuristics.isPurifiedWater(ingredient) { return nil }

            let volume = draft.effectiveLiquidVolumeMl(for: ingredient)
            guard volume > 0 else { return nil }
            return (ingredient: ingredient, volumeMl: volume)
        }
        .sorted { latinIngredientName($0.ingredient) < latinIngredientName($1.ingredient) }

        if let targetVolume = inferredTargetValue(from: draft), targetVolume > 0 {
            let concentratesMl = validConcentrates.reduce(0.0) { $0 + $1.concentrateVolumeMl }
            let additivesMl = otherLiquids.reduce(0.0) { $0 + $1.volumeMl }
            let waterMl = targetVolume - concentratesMl - additivesMl

            if waterMl > 0 {
                let solventIngredient = draft.ingredients.last(where: {
                    PurifiedWaterHeuristics.isPurifiedWater($0) && ($0.isAd || $0.isQS || $0.unit.rawValue == "ml")
                })

                items.append(
                    TechnologyOrderItem(
                        stepIndex: 0,
                        ingredientId: solventIngredient?.id,
                        ingredientName: "Aqua purificata",
                        amountText: formatAmount(waterMl),
                        unitText: "ml",
                        note: "довести ad до \(formatAmount(targetVolume)) ml",
                        volumeMl: waterMl,
                        source: .inferredWater,
                        stage: .solvent
                    )
                )
            }
        }

        for concentrateItem in validConcentrates {
            let canonical = buretteCanonicalLatinName(concentrate: concentrateItem.concentrate)
            let title = canonical.map { "Sol. \($0) \(formatAmount(concentrateItem.concentrate.concentrationPercent))%" }
                ?? concentrateItem.concentrate.titleRu
            items.append(
                TechnologyOrderItem(
                    stepIndex: 0,
                    ingredientId: nil,
                    ingredientName: title,
                    amountText: formatAmount(concentrateItem.concentrateVolumeMl),
                    unitText: "ml",
                    note: "бюреточний концентрат (\(concentrateItem.concentrate.ratioTitle))",
                    volumeMl: concentrateItem.concentrateVolumeMl,
                    massG: concentrateItem.soluteMassG,
                    source: .burette,
                    stage: .concentrates
                )
            )
        }

        for additive in otherLiquids {
            items.append(
                TechnologyOrderItem(
                    stepIndex: 0,
                    ingredientId: additive.ingredient.id,
                    ingredientName: latinIngredientName(additive.ingredient),
                    amountText: formatAmount(additive.volumeMl),
                    unitText: "ml",
                    note: "додатковий рідкий компонент",
                    volumeMl: additive.volumeMl,
                    source: .ingredient,
                    stage: .additives
                )
            )
        }

        return reindexedTechnologyOrder(items)
    }

    private func applyGlobalPrimarySolventStaging(
        to items: [TechnologyOrderItem],
        draft: ExtempRecipeDraft
    ) -> [TechnologyOrderItem] {
        guard SignaUsageAnalyzer.effectiveFormMode(for: draft) == .solutions
            || SignaUsageAnalyzer.effectiveFormMode(for: draft) == .drops
        else {
            return reindexedTechnologyOrder(items)
        }
        guard !items.isEmpty else { return items }
        if items.contains(where: { $0.ingredientName.contains("(pars I)") || $0.ingredientName.contains("(pars II)") }) {
            return reindexedTechnologyOrder(items)
        }
        guard let solventIngredient = primarySolventIngredientForStaging(draft: draft) else {
            return reindexedTechnologyOrder(items)
        }
        guard items.contains(where: { $0.ingredientId == solventIngredient.id }) else {
            return reindexedTechnologyOrder(items)
        }

        var staged = items.filter { $0.ingredientId != solventIngredient.id }
        let hasListAActives = draft.ingredients.contains {
            !$0.isQS && !$0.isAd && $0.isReferenceListA
        }
        let startNote: String = {
            if let nonAqueous = NonAqueousSolventCatalog.primarySolvent(in: draft),
               nonAqueous.ingredient?.id == solventIngredient.id,
               nonAqueous.type == .glycerin {
                return "тарувати сухий флакон темного скла; внести частину розчинника для початкового розчинення"
            }
            return "внести частину розчинника на початку; у ній послідовно вводити речовини за технологією"
        }()
        let finishNote: String = {
            if let nonAqueous = NonAqueousSolventCatalog.primarySolvent(in: draft),
               nonAqueous.ingredient?.id == solventIngredient.id,
               usesNonAqueousMassTarget(draft: draft, solventIngredient: solventIngredient) {
                return "додати решту розчинника; довести до кінцевої маси та перемішати до однорідності"
            }
            if NonAqueousSolventCatalog.primarySolvent(in: draft) == nil,
               let targetVolume = inferredTargetValue(from: draft),
               targetVolume > 0 {
                return "додати решту розчинника; довести до \(formatAmount(targetVolume)) ml та перемішати до однорідності"
            }
            return "додати решту розчинника; довести до кінцевого об'єму/маси та перемішати до однорідності"
        }()

        let firstItem = TechnologyOrderItem(
            stepIndex: 1,
            ingredientId: solventIngredient.id,
            ingredientName: "\(latinIngredientName(solventIngredient)) (pars I)",
            amountText: "частина",
            unitText: "",
            note: startNote
        )
        let lastItem = TechnologyOrderItem(
            stepIndex: 0,
            ingredientId: solventIngredient.id,
            ingredientName: "\(latinIngredientName(solventIngredient)) (pars II)",
            amountText: "решта",
            unitText: "",
            note: finishNote
        )

        if hasListAActives {
            staged = staged.map { item in
                guard let id = item.ingredientId,
                      let ingredient = draft.ingredients.first(where: { $0.id == id }),
                      ingredient.isReferenceListA
                else { return item }
                var tagged = item
                let current = tagged.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let listANote = (isLiquidIngredient(ingredient) && !isSilverNitrateIngredient(ingredient))
                    ? "Список А: відміряти окремо у мірному посуді (на терезах не зважувати)"
                    : "Список А: відважити окремо на спеціальних терезах"
                if !current.lowercased().contains("список а") {
                    tagged.note = current.isEmpty
                        ? listANote
                        : "\(listANote); \(current)"
                }
                return tagged
            }
        }

        if let nonAqueous = NonAqueousSolventCatalog.primarySolvent(in: draft),
           nonAqueous.ingredient?.id == solventIngredient.id,
           nonAqueous.type == .glycerin
        {
            let hardIngredientIds: Set<UUID> = Set(
                draft.ingredients.compactMap { ingredient in
                    guard !ingredient.isAd, !ingredient.isQS else { return nil }
                    guard ingredient.id != solventIngredient.id else { return nil }
                    return isHardlySoluble(ingredient) ? ingredient.id : nil
                }
            )

            if !hardIngredientIds.isEmpty {
                let hardFirst = staged.filter { item in
                    guard let id = item.ingredientId else { return false }
                    return hardIngredientIds.contains(id)
                }
                let others = staged.filter { item in
                    guard let id = item.ingredientId else { return true }
                    return !hardIngredientIds.contains(id)
                }

                let solventCombined = TechnologyOrderItem(
                    stepIndex: 0,
                    ingredientId: solventIngredient.id,
                    ingredientName: latinIngredientName(solventIngredient),
                    amountText: ingredientAmountValueText(solventIngredient, draft: draft),
                    unitText: ingredientAmountUnitText(solventIngredient, draft: draft),
                    note: "частину використати для розтирання у ступці; суспензію перенести у флакон і змити залишком розчинника до повної навішки"
                )

                var finalItems: [TechnologyOrderItem] = []
                finalItems.append(contentsOf: hardFirst)
                finalItems.append(solventCombined)
                finalItems.append(contentsOf: others)
                return reindexedTechnologyOrder(finalItems)
            }
        }

        var finalItems = [firstItem]
        finalItems.append(contentsOf: staged)
        finalItems.append(lastItem)
        return reindexedTechnologyOrder(finalItems)
    }

    private func primarySolventIngredientForStaging(draft: ExtempRecipeDraft) -> IngredientDraft? {
        if let nonAqueous = NonAqueousSolventCatalog.primarySolvent(in: draft)?.ingredient {
            return nonAqueous
        }
        let aqueousCandidates = draft.ingredients.filter { ingredient in
            !ingredient.isQS && isPrimarySolvent(ingredient)
        }
        if let byAmount = aqueousCandidates.max(by: { lhs, rhs in
            lhs.amountValue < rhs.amountValue
        }) {
            return byAmount
        }
        return nil
    }

    private func reindexedTechnologyOrder(_ items: [TechnologyOrderItem]) -> [TechnologyOrderItem] {
        var output = items
        for index in output.indices {
            output[index].stepIndex = index + 1
        }
        return output
    }

    private func buildDefaultTechnologyOrder(draft: ExtempRecipeDraft) -> [TechnologyOrderItem] {
        let ordered = draft.ingredients
            .filter { !$0.isQS }
            .sorted { lhs, rhs in
                if lhs.isAd != rhs.isAd { return !lhs.isAd && rhs.isAd }
                return latinIngredientName(lhs) < latinIngredientName(rhs)
            }

        return ordered.enumerated().map { index, ingredient in
            TechnologyOrderItem(
                stepIndex: index + 1,
                ingredientId: ingredient.id,
                ingredientName: latinIngredientName(ingredient),
                amountText: ingredientAmountValueText(ingredient, draft: draft),
                unitText: ingredientAmountUnitText(ingredient, draft: draft),
                note: ingredient.isAd ? "довести наприкінці до кінцевої маси/об'єму" : nil
            )
        }
    }

    private func buildListAPowderTechnologyOrder(
        draft: ExtempRecipeDraft,
        powderTechnology: PowderTechnologyResult
    ) -> [TechnologyOrderItem] {
        let fillerName = powderTechnology.fillerIngredientName ?? "Sacchari lactis"
        let triturationPlan = powderTechnology.triturationPlans.first
        let ratioText = triturationPlan?.ratio.map { "1:\($0)" } ?? "1:10"
        let triturationName = triturationPlan.map { "Trituratio \($0.ingredientName) \(ratioText)" } ?? "Trituratio"

        var items: [TechnologyOrderItem] = []
        if let fillerMass = powderTechnology.correctedFillerMass {
            items.append(
                TechnologyOrderItem(
                    stepIndex: 1,
                    ingredientId: powderTechnology.fillerIngredientId,
                    ingredientName: fillerName,
                    amountText: formatAmount(fillerMass),
                    unitText: "g",
                    note: "частину використати для затирання пор ступки"
                )
            )
        }

        if let triturationPlan {
            items.append(
                TechnologyOrderItem(
                    stepIndex: items.count + 1,
                    ingredientId: triturationPlan.ingredientId,
                    ingredientName: triturationName,
                    amountText: formatAmount(triturationPlan.totalTriturationMass),
                    unitText: "g",
                    note: "внести в середину"
                )
            )
        }

        items.append(
            TechnologyOrderItem(
                stepIndex: items.count + 1,
                ingredientId: powderTechnology.fillerIngredientId,
                ingredientName: "Misce, divide in partes aequales N \(max(1, draft.numero ?? powderTechnology.dosesCount))",
                amountText: "",
                unitText: "",
                note: "додати решту \(fillerName) методом геометричного розведення"
            )
        )

        return items
    }

    private func buildListBPowderTechnologyOrder(
        draft: ExtempRecipeDraft,
        powderTechnology: PowderTechnologyResult
    ) -> [TechnologyOrderItem] {
        let fillerName = powderTechnology.fillerIngredientName ?? "Sacchari lactis"
        let restrictedIngredients = draft.ingredients.filter { !$0.isAd && !$0.isQS && $0.isReferenceListB }
        let plansById = Dictionary(uniqueKeysWithValues: powderTechnology.triturationPlans.map { ($0.ingredientId, $0) })
        var items: [TechnologyOrderItem] = []

        if let fillerMass = powderTechnology.correctedFillerMass {
            items.append(
                TechnologyOrderItem(
                    stepIndex: 1,
                    ingredientId: powderTechnology.fillerIngredientId,
                    ingredientName: fillerName,
                    amountText: formatAmount(fillerMass),
                    unitText: "g",
                    note: "частину використати для затирання пор ступки"
                )
            )
        }

        for ingredient in restrictedIngredients {
            if let plan = plansById[ingredient.id], let ratio = plan.ratio {
                items.append(
                    TechnologyOrderItem(
                        stepIndex: items.count + 1,
                        ingredientId: ingredient.id,
                        ingredientName: "Trituratio \(latinIngredientName(ingredient)) 1:\(ratio)",
                        amountText: formatAmount(plan.totalTriturationMass),
                        unitText: "g",
                        note: "внести у затерту ступку"
                    )
                )
            } else {
                items.append(
                    TechnologyOrderItem(
                        stepIndex: items.count + 1,
                        ingredientId: ingredient.id,
                        ingredientName: latinIngredientName(ingredient),
                        amountText: ingredientAmountValueText(ingredient, draft: draft),
                        unitText: ingredientAmountUnitText(ingredient, draft: draft),
                        note: "внести після затирання пор ступки"
                    )
                )
            }
        }

        items.append(
            TechnologyOrderItem(
                stepIndex: items.count + 1,
                ingredientId: powderTechnology.fillerIngredientId,
                ingredientName: "Misce, divide in partes aequales N \(max(1, draft.numero ?? powderTechnology.dosesCount))",
                amountText: "",
                unitText: "",
                note: "додати решту \(fillerName) методом геометричного розведення"
            )
        )

        return items
    }

    private func classifyLiquidOrder(
        ingredient: IngredientDraft,
        draft: ExtempRecipeDraft,
        iodidePrep: IodideComplexOrderPreparation?
    ) -> (stage: Int, substage: Int, note: String) {
        let primaryNonAqueous = NonAqueousSolventCatalog.primarySolvent(in: draft)
        let hasPhenolInFattyOil = hasPhenolFamilyInFattyOilSolution(draft)

        if let primaryNonAqueous,
           primaryNonAqueous.ingredient?.id == ingredient.id
        {
            let usesFinalMassTarget = usesNonAqueousMassTarget(draft: draft, solventIngredient: ingredient)
            switch primaryNonAqueous.type {
            case .ethanol:
                if let officinal = NonAqueousSolventCatalog.officinalAlcoholSolution(for: ingredient) {
                    return (45, 0, "офіцинальний спиртовий розчин: використовувати Spiritus aethylici \(formatAmount(Double(officinal.ethanolStrength)))% ad кінцевого об'єму; воду не додавати")
                }
                return (45, 0, "спочатку підготувати спирт потрібної міцності окремо; потім додати його до речовин у сухий флакон")
            case .ether:
                return (45, 0, "додати після внесення речовин; не нагрівати, уникати вогню")
            case .fattyOil, .mineralOil, .glycerin, .vinylin, .viscousOther:
                if let iodidePrep,
                   iodidePrep.solventIngredientId == ingredient.id
                {
                    return (40, 0, "додати після повного розчинення йоду в розчині йодиду")
                }
                if primaryNonAqueous.type == .fattyOil, hasPhenolInFattyOil {
                    return (0, 0, "спочатку відважити олію (усю або більшу частину) у сухий тарований флакон; потім додати фенол")
                }
                if primaryNonAqueous.type == .glycerin {
                    if usesFinalMassTarget {
                        return (45, 0, "тарувати сухий флакон темного скла; гліцерин відважувати у флакон, доведення виконати наприкінці до кінцевої маси")
                    }
                    return (0, 0, "тарувати сухий флакон темного скла; гліцерин відважувати безпосередньо у флакон (без мірного циліндра)")
                }
                if usesFinalMassTarget {
                    return (45, 0, "додати після відважування речовин; доведення виконати наприкінці")
                }
                return (0, 0, "відважити або відміряти точну кількість як неводний розчинник; без додаткового доведення")
            default:
                return usesFinalMassTarget
                    ? (45, 0, "додати після відважування речовин; доведення виконати наприкінці")
                    : (45, 0, "додати після відважування речовин у точній кількості")
            }
        }

        if isPrimarySolvent(ingredient),
           inferredPurifiedWaterAmounts(draft: draft)[ingredient.id] != nil
        {
            let note = containsAlcoholicTinctureLike(draft)
                ? "відміряти фактичний розрахований об'єм як первинний розчинник; настойки внести окремо у відпускний флакон"
                : "взяти фактичний розрахований об'єм як первинний розчинник"
            return (0, 0, note)
        }

        if ingredient.isAd || ingredient.isQS {
            return (80, 0, "довести ad до кінцевого об'єму наприкінці")
        }

        if isPrimarySolvent(ingredient) {
            if isAromaticWater(ingredient) && shouldAddAromaticWaterAfterFiltration(ingredient, draft: draft) {
                return (55, 0, "додати після проціджування; не нагрівати, паперовий фільтр не використовувати")
            }
            let note = ingredient.isAd
                ? "використати частину розчинника; рештою довести ad наприкінці"
                : isAromaticWater(ingredient)
                    ? "використати як ароматний розчинник без нагрівання; проціджувати лише через вату"
                : inferredPurifiedWaterAmounts(draft: draft)[ingredient.id] != nil
                    ? "взяти фактичний розрахований об'єм як первинний розчинник"
                    : "взяти як первинний розчинник"
            return (0, 0, note)
        }

        if let iodidePrep {
            if iodidePrep.iodideIds.contains(ingredient.id) {
                if ingredient.presentationKind == .solution {
                    return (0, safetyPriority(ingredient), "використати частину розчину йодиду (орієнтир \(formatAmount(iodidePrep.waterMl)) ml) для попереднього комплексоутворення з йодом")
                }
                if iodidePrep.hasExplicitWater {
                    if iodidePrep.waterMl > 0 {
                        return (0, safetyPriority(ingredient), "розчинити у частині вже відміряної Aqua purificata (\(formatAmount(iodidePrep.waterMl)) ml орієнтовно), сформувати концентрований розчин йодиду")
                    }
                    return (0, safetyPriority(ingredient), "розчинити у відміряній Aqua purificata, сформувати концентрований розчин йодиду")
                }
                let isGlycerinLugol = primaryNonAqueous?.type == .glycerin
                if isGlycerinLugol {
                    return (0, safetyPriority(ingredient), "розчинити у Aqua purificata \(formatAmount(iodidePrep.waterMl)) ml (мінімум 1:1.5 до маси йодиду), сформувати концентрат")
                }
                return (0, safetyPriority(ingredient), "розчинити у Aqua purificata \(formatAmount(iodidePrep.waterMl)) ml, сформувати концентрований розчин йодиду")
            }
            if iodidePrep.iodineIds.contains(ingredient.id) {
                if iodidePrep.hasIodideSolutionCarrier {
                    return (10, safetyPriority(ingredient), "додати до відібраної частини розчину йодиду і розчинити до утворення комплексу KI3; без металевих інструментів")
                }
                return (10, safetyPriority(ingredient), "додати до концентрату йодиду і розчинити до утворення комплексу KI3; без металевих інструментів")
            }
        }

        if hasPhenolInFattyOil, isPhenolFamily(ingredient) {
            return (10, safetyPriority(ingredient), "додати у вже відважену олію; працювати в рукавичках")
        }

        if isAcidifier(ingredient) {
            return (5, 0, "внести до ферменту/чутливих ВМС; сформувати потрібне середовище")
        }

        if isBuretteConcentrateCandidate(ingredient, draft: draft) {
            return (10, 0, "внести як готовий концентрований розчин")
        }

        if isProtectedColloid(ingredient) || isVmsIngredient(ingredient) {
            return (40, 0, colloidOrVmsNote(for: ingredient))
        }

        if isViscousLiquid(ingredient) {
            if primaryNonAqueous?.ingredient?.id == ingredient.id {
                return (0, 0, "як основний в'язкий розчинник вводиться на стадії розчинення, а не після фільтрації")
            }
            return (60, 0, "ввести після фільтрації")
        }

        if isLateAddedReadyLiquid(ingredient) {
            return (65, 0, "додати після проціджування у відпускний флакон")
        }

        if requiresPremixWithMixture(ingredient) {
            return (68, 0, "попередньо змішати 1:1-1:2 з частиною готової мікстури, потім внести")
        }

        if isVolatileAqueousLiquid(ingredient) {
            return (70, 0, "додати в кінці без інтенсивного збовтування; щільно закоркувати")
        }

        if isVolatileLiquid(ingredient) {
            return (70, 0, "внести в останню чергу у відпускний флакон")
        }

        if let markerDrivenNote = markerDrivenLiquidDissolutionNote(for: ingredient) {
            return (20, safetyPriority(ingredient), markerDrivenNote)
        }

        if isHardlySoluble(ingredient) {
            return (20, safetyPriority(ingredient), "розчиняти першочергово / окремо")
        }

        if isEasySoluble(ingredient) {
            if shouldUseSimpleAqueousDissolutionNote(for: ingredient, draft: draft) {
                return (30, safetyPriority(ingredient), "розчинити у частині очищеної води")
            }
            return (30, safetyPriority(ingredient), "вносити у робочому порядку після повного розчинення попередніх компонентів")
        }

        return (35, safetyPriority(ingredient), defaultLiquidNote(for: ingredient))
    }

    private func shouldUseSimpleAqueousDissolutionNote(
        for ingredient: IngredientDraft,
        draft: ExtempRecipeDraft
    ) -> Bool {
        guard NonAqueousSolventCatalog.primarySolvent(in: draft) == nil else { return false }
        guard draft.ingredients.contains(where: { $0.isAd || $0.isQS }) else { return false }
        let nonSolventActives = draft.ingredients.filter { candidate in
            !candidate.isAd && !candidate.isQS && !isPrimarySolvent(candidate)
        }
        guard nonSolventActives.count == 1, nonSolventActives[0].id == ingredient.id else { return false }
        return true
    }

    private func officinalAlcoholTechnologyOrder(draft: ExtempRecipeDraft) -> [TechnologyOrderItem]? {
        guard let primaryNonAqueous = NonAqueousSolventCatalog.primarySolvent(in: draft),
              primaryNonAqueous.type == .ethanol,
              let solventIngredient = primaryNonAqueous.ingredient,
              let officinal = NonAqueousSolventCatalog.officinalAlcoholSolution(for: solventIngredient)
        else { return nil }

        let activeIngredients = draft.ingredients.filter { !$0.isQS && !$0.isAd }
        guard activeIngredients.count == 1, activeIngredients[0].id == solventIngredient.id else { return nil }
        guard let solventVolumeMl = draft.solutionVolumeMl(for: solventIngredient) ?? {
            guard solventIngredient.amountValue > 0, solventIngredient.unit.rawValue == "ml" else { return nil }
            return solventIngredient.amountValue
        }(), solventVolumeMl > 0 else { return nil }

        let activeMass = solventVolumeMl * officinal.concentrationPercent / 100.0
        return [
            TechnologyOrderItem(
                stepIndex: 1,
                ingredientId: nil,
                ingredientName: officinal.activeTitle,
                amountText: formatAmount(activeMass),
                unitText: "g",
                note: "зважити та внести у сухий флакон"
            ),
            TechnologyOrderItem(
                stepIndex: 2,
                ingredientId: solventIngredient.id,
                ingredientName: "Spiritus aethylici \(officinal.ethanolStrength)%",
                amountText: "ad \(formatAmount(solventVolumeMl))",
                unitText: "ml",
                note: "відміряти та додати до флакона; воду не додавати"
            )
        ]
    }

    private func explicitSectionLines(sections: [PpkSection], matchingAnyOf needles: [String]) -> [String] {
        flattenSections(
            sections.filter { section in
                let title = normalizedTitle(section.title)
                return needles.contains(where: { title.contains($0) })
            }
        )
    }

    private func flattenSections(_ sections: [PpkSection]) -> [String] {
        var lines: [String] = []
        for section in sections {
            if section.lines.isEmpty { continue }
            if lines.isEmpty {
                lines.append(contentsOf: section.lines)
            } else {
                lines.append("— \(section.title) —")
                lines.append(contentsOf: section.lines)
            }
        }
        return lines
    }

    private func defaultQualityLines(draft: ExtempRecipeDraft) -> [String] {
        switch SignaUsageAnalyzer.effectiveFormMode(for: draft) {
        case .solutions, .drops:
            if containsSuspensionMarker(draft) {
                return ["Однорідність після збовтування", "Відсутність грубих агрегатів", "Редиспергованість осаду"]
            }
            if containsEmulsionMarker(draft) {
                return ["Однорідність емульсії", "Відсутність швидкого розшарування", "Відповідність кольору і запаху"]
            }
            return ["Прозорість або допустима опалесценція", "Відсутність механічних включень", "Відповідність кольору та запаху"]
        case .powders:
            return ["Однорідність порошкової суміші", "Рівномірність дозування", "Відсутність сторонніх включень"]
        case .ointments:
            return ["Однорідність мазі", "Відсутність крупинок і піщанистості", "Відповідність кольору та запаху"]
        case .suppositories:
            return ["Однорідність маси", "Цілісність та правильна форма", "Відсутність тріщин і розшарування"]
        case .auto:
            return ["Візуальний контроль однорідності", "Відповідність органолептичних ознак"]
        }
    }

    private func defaultPackagingLines(draft: ExtempRecipeDraft) -> [String] {
        var lines: [String] = []
        let effectiveFormMode = SignaUsageAnalyzer.effectiveFormMode(for: draft)
        let hasEthacridine = draft.ingredients.contains(where: isEthacridineIngredient)
        let hasBoricAcid = draft.ingredients.contains(where: isBoricAcidIngredient)
        let hasFuracilin = draft.ingredients.contains(where: isFuracilinIngredient)
        let hasExplicitStorageRules = hasExplicitStorageRequirement(draft)

        if effectiveFormMode == .solutions || effectiveFormMode == .drops {
            if containsPhenolFamily(draft) {
                lines.append("Упаковка: флакон з темного (оранжевого) скла")
                lines.append("Етикетка: «ЯД»")
                lines.append("Етикетка: «Берегти від світла»")
                lines.append("Оформити сигнатурою (рожева смуга)")
                lines.append("Флакон опечатати (сургучем/пломбою)")
            } else if containsAmberGlassMarker(draft) || hasEthacridine {
                lines.append("Упаковка: флакон з темного (оранжевого) скла")
                lines.append("Етикетка: «Берегти від світла»")
            } else if hasExplicitStorageRules, containsAromaticOrVolatileMarker(draft) {
                lines.append("Упаковка: флакон з темного скла")
            } else {
                lines.append("Упаковка: флакон відповідного об'єму")
            }
            if containsSuspensionMarker(draft) || containsEmulsionMarker(draft) {
                lines.append("Етикетка: «Перед вживанням збовтувати»")
            }
            if containsLightSensitiveMarker(draft), !containsAmberGlassMarker(draft), !hasEthacridine {
                lines.append("Етикетка: «Берегти від світла»; тара з темного скла")
            }
            if hasExplicitStorageRules, containsAromaticWaterMarker(draft) {
                lines.append("Технологія: ароматні води враховувати як готові водні системи 1:1000; не нагрівати")
                lines.append("Зберігання: CoolPlace (8-15°C)")
                lines.append("За сильної мутності при відновленні концентрату допустимий змочений водою паперовий фільтр")
            }
            if containsVolatileAqueousMarker(draft) || containsPremixVolatileDrops(draft) {
                lines.append("Щільно закоркувати")
            }
            if hasExplicitStorageRules, containsAlcoholicTinctureLike(draft) {
                lines.append("Зберігати у прохолодному, захищеному від світла місці")
                lines.append("Щільно закоркувати")
            }
            if hasBoricAcid, hasExplicitStorageRules {
                lines.append("Зберігати в недоступному для дітей місці")
            }
            if hasFuracilin {
                lines.append("Берегти від дітей")
            }
            if draft.ingredients.contains(where: isIodideComponent)
                || draft.ingredients.contains(where: isStableHalideWithoutExplicitPhotolability)
            {
                lines.append("Берегти від дітей")
            }
            if containsAntibioticMarker(draft) {
                lines.append("Виготовити асептично; відпускати у стерильній тарі")
                lines.append("Етикетка: «Приготовлено асептично»")
            }
        } else if effectiveFormMode == .ointments {
            lines.append("Упаковка: баночка або туба")
            lines.append("Етикетка: «Зовнішньо»")
        } else if effectiveFormMode == .powders {
            lines.append("Упаковка: паперові капсули / пакетики")
            lines.append("Етикетка: за способом застосування")
            if requiresAsepticPowderForWoundsOrNewborn(draft) {
                lines.append("Виготовити в асептичних умовах; за термостійкості провести стерилізацію")
                lines.append("Маркування: «Стерильно».")
            }
        } else if effectiveFormMode == .suppositories {
            lines.append("Упаковка: контурна упаковка / коробка")
            lines.append("Зберігати у прохолодному місці")
        }

        var seen: Set<String> = []
        return lines.filter { seen.insert($0).inserted }
    }

    private func harmonizePackagingLines(_ lines: [String], draft: ExtempRecipeDraft) -> [String] {
        guard requiresDarkGlassPackaging(draft) else {
            var seen: Set<String> = []
            return lines.filter { seen.insert($0).inserted }
        }

        var normalized = lines.filter { line in
            let hay = line.lowercased()
            if hay.contains("звичайний скляний флакон") { return false }
            if hay.contains("флакон відповідного об'єму") { return false }
            if (hay.contains("тара: флакон") || hay.contains("упаковка: флакон")),
               !hay.contains("темного"),
               !hay.contains("оранжевого") {
                return false
            }
            return true
        }

        if !normalized.contains(where: { line in
            let hay = line.lowercased()
            return hay.contains("оранжевого") || hay.contains("темного")
        }) {
            normalized.insert("Тара: флакон з темного (оранжевого) скла", at: 0)
        }
        if isLugolGlycerinScenario(draft),
           !normalized.contains(where: { $0.lowercased().contains("звичайний флакон заборонено") }) {
            normalized.insert("Контроль тари: звичайний флакон заборонено, тільки темне скло.", at: 0)
        }

        var seen: Set<String> = []
        return normalized.filter { seen.insert($0).inserted }
    }

    private func requiresDarkGlassPackaging(_ draft: ExtempRecipeDraft) -> Bool {
        containsLightSensitiveMarker(draft)
            || containsAmberGlassMarker(draft)
            || containsPhenolFamily(draft)
            || draft.ingredients.contains(where: { !$0.isAd && !$0.isQS && $0.isReferenceListA })
    }

    private func sanitizeStorageClaimsWithoutEvidence(_ lines: [String], draft: ExtempRecipeDraft) -> [String] {
        guard !hasExplicitStorageRequirement(draft) else { return lines }

        let filtered = lines.filter { line in
            !isStorageControlClaimLine(line)
        }
        if filtered.isEmpty {
            return ["Упаковка: флакон відповідного об'єму"]
        }
        return filtered
    }

    private func hasExplicitStorageRequirement(_ draft: ExtempRecipeDraft) -> Bool {
        draft.ingredients.contains { ingredient in
            hasExplicitStorageRequirement(ingredient)
        }
    }

    private func hasExplicitStorageRequirement(_ ingredient: IngredientDraft) -> Bool {
        if isEthacridineIngredient(ingredient) {
            return true
        }
        if ingredient.isReferenceLightSensitive || ingredient.isReferenceListA || ingredient.refSterile {
            return true
        }

        let storage = (ingredient.refStorage ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !storage.isEmpty {
            if storage.contains("світл")
                || storage.contains("light")
                || storage.contains("темн")
                || storage.contains("оранж")
                || storage.contains("прохолод")
                || storage.contains("cold")
                || storage.contains("cool")
                || storage.contains("зберіг")
                || storage.contains("store") {
                return true
            }
        }

        return markerMatch(
            ingredient,
            keys: ["storage", "instruction_id", "process_note", "light_sensitive", "packaging"],
            values: [
                "lightprotected",
                "protectfromlight",
                "light_sensitive",
                "amberglass",
                "darkglass",
                "темнескло",
                "coolplace",
                "cool_storage",
                "store_cool",
                "tight_closure"
            ]
        )
    }

    private func isStorageControlClaimLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("зберіг")
            || lower.contains("прохолод")
            || lower.contains("холод")
            || lower.contains("cool")
            || lower.contains("cold")
            || lower.contains("берегти від світла")
            || lower.contains("захищен")
            || lower.contains("темного")
            || lower.contains("оранжевого")
            || lower.contains("dark")
            || lower.contains("amber")
    }

    private func autoValidateGeneratedPpk(
        draft: ExtempRecipeDraft,
        backSide: [PpkSection],
        faceSide: [PpkSection],
        control: [PpkSection]
    ) -> [RxIssue] {
        var validationIssues: [RxIssue] = []

        let mathLines = flattenSections(backSide.filter { normalizedTitle($0.title).contains("математич") })
        let technologyLines = flattenSections(faceSide.filter {
            let key = normalizedTitle($0.title)
            return key.contains("порядок внесення") || key.contains("ключові операції")
        })
        let controlLines = flattenSections(control)
        let packagingControlLines = flattenSections(control.filter {
            normalizedTitle($0.title).contains("оформлення") || normalizedTitle($0.title).contains("зберігання")
        })

        let usesKuoCalculation = mathLines.contains(where: isKuoComputationLine)
        if usesKuoCalculation {
            let solidIngredients = draft.ingredients.filter { ingredient in
                !ingredient.isAd
                    && !ingredient.isQS
                    && ingredient.unit.rawValue == "g"
                    && ingredient.amountValue > 0
                    && !isLiquidIngredient(ingredient)
            }
            let missingKuoCount = solidIngredients.filter { ($0.refKuoMlPerG ?? 0) <= 0 }.count
            if missingKuoCount > 0 {
                validationIssues.append(
                    RxIssue(
                        code: "ppk.validation.kou.missing_in_reference",
                        severity: .blocking,
                        message: "Для режиму розрахунку з КУО бракує КУО в довіднику для \(missingKuoCount) твердих компонентів."
                    )
                )
            }
            if !mathLines.contains(where: containsQsAdMarker) {
                validationIssues.append(
                    RxIssue(
                        code: "ppk.validation.kou.qs_missing",
                        severity: .warning,
                        message: "Після розрахунку через КУО відсутнє обов'язкове доведення q.s. ad до кінцевого об'єму."
                    )
                )
            }
        }

        if !hasExplicitStorageRequirement(draft),
           packagingControlLines.contains(where: isStorageControlClaimLine) {
            validationIssues.append(
                RxIssue(
                    code: "ppk.validation.storage.unsubstantiated",
                    severity: .warning,
                    message: "Умови зберігання/тара містять спеціальні вимоги без явного посилання на довідкові правила речовин."
                )
            )
        }

        if mathLines.contains(where: isTechnologyProcessLine) {
            validationIssues.append(
                RxIssue(
                    code: "ppk.validation.sections.math_mixed",
                    severity: .warning,
                    message: "У математичному блоці виявлено технологічні операції (розчинення/фільтрація/нагрівання)."
                )
            )
        }
        if technologyLines.contains(where: isDoseControlLine) {
            validationIssues.append(
                RxIssue(
                    code: "ppk.validation.sections.technology_mixed",
                    severity: .warning,
                    message: "У технологічному блоці виявлено дозові розрахунки; їх слід перенести до математичного/дозового контролю."
                )
            )
        }
        if controlLines.contains(where: isKuoComputationLine) {
            validationIssues.append(
                RxIssue(
                    code: "ppk.validation.sections.control_mixed",
                    severity: .warning,
                    message: "У контрольному блоці виявлено розрахунки КУО; розрахункові рядки мають бути тільки в математичному обґрунтуванні."
                )
            )
        }

        return deduplicatedIssues(validationIssues)
    }

    private func deduplicatedIssues(_ issues: [RxIssue]) -> [RxIssue] {
        var seen: Set<String> = []
        return issues.filter { issue in
            let key = "\(issue.code)|\(issue.severity.rawValue)|\(issue.message)"
            return seen.insert(key).inserted
        }
    }

    private func isKuoComputationLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.contains("куо не враховується")
            || lower.contains("куо не застос")
            || lower.contains("без урахування куо")
            || lower.contains("no kuo")
        {
            return false
        }
        return lower.contains("σкуо")
            || lower.contains("з урахуванням куо")
            || lower.contains("режим розрахунку з урахуванням куо")
            || lower.contains("куо:")
    }

    private func containsQsAdMarker(_ line: String) -> Bool {
        line.lowercased().contains("q.s. ad")
    }

    private func isTechnologyProcessLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("процід")
            || lower.contains("фільтр")
            || lower.contains("нагр")
            || lower.contains("охолод")
            || lower.contains("переміш")
    }

    private func isDoseControlLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("разовий прийом")
            || lower.contains("на добу")
            || lower.contains("кратність")
            || lower.contains("врд")
            || lower.contains("всд")
            || lower.contains("доза")
            || lower.contains("прийом")
    }

    private func appendSide(title: String, sections: [PpkSection], to lines: inout [String]) {
        guard !sections.isEmpty else { return }
        lines.append("")
        lines.append("\(title):")
        for section in sections {
            lines.append("")
            lines.append("\(section.title):")
            if section.lines.isEmpty {
                lines.append("—")
            } else {
                lines.append(contentsOf: section.lines)
            }
        }
    }

    private func inferredTargetValue(from draft: ExtempRecipeDraft) -> Double? {
        if let target = draft.explicitLiquidTargetMl {
            return target
        }

        if let legacy = draft.legacyAdOrQsLiquidTargetMl {
            return legacy
        }

        let measuredLiquids = draft.ingredients.compactMap { ingredient -> Double? in
            guard !ingredient.isQS, !ingredient.isAd else { return nil }
            let volume = draft.effectiveLiquidVolumeMl(for: ingredient)
            return volume > 0 ? volume : nil
        }
        if draft.ingredients.contains(where: isPrimaryAqueousLiquid) {
            let totalMeasured = measuredLiquids.reduce(0, +)
            if totalMeasured > 0 {
                return totalMeasured
            }
        }

        let aquaCandidate = draft.ingredients
            .filter { ingredient in
                ingredient.unit.rawValue == "ml"
                    && ingredient.amountValue > 0
                    && isPrimaryAqueousLiquid(ingredient)
            }
            .max { lhs, rhs in lhs.amountValue < rhs.amountValue }
        return aquaCandidate?.amountValue
    }

    private func latinIngredientName(_ ingredient: IngredientDraft) -> String {
        let raw = (ingredient.refNameLatNom ?? ingredient.refNameLatGen ?? ingredient.displayName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "Substantia" }

        if let token = ingredient.rpPrefix.latinToken {
            let lower = raw.lowercased()
            if !lower.hasPrefix(token.lowercased()) {
                return "\(token) \(raw)"
            }
        }
        return raw
    }

    private func ingredientAmountText(_ ingredient: IngredientDraft, draft: ExtempRecipeDraft) -> String {
        if ingredient.isAd || ingredient.isQS {
            let target = (draft.normalizedTargetValue ?? (ingredient.amountValue > 0 ? ingredient.amountValue : nil)).map(formatAmount) ?? ""
            let unit = (draft.resolvedTargetUnit?.rawValue ?? ingredient.unit.rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
            return target.isEmpty ? "ad \(unit)" : "ad \(target) \(unit)"
        }
        let value = ingredientAmountValueText(ingredient, draft: draft)
        let unit = ingredientAmountUnitText(ingredient, draft: draft)
        if value.isEmpty { return unit }
        return unit.isEmpty ? value : "\(value) \(unit)"
    }

    private func ingredientAmountValueText(_ ingredient: IngredientDraft, draft: ExtempRecipeDraft) -> String {
        if let solutionAmount = solutionAmountParts(for: ingredient, draft: draft) {
            return solutionAmount.valueText
        }

        if let converted = nonAqueousMassAmountValueText(ingredient: ingredient, draft: draft) {
            return converted
        }

        if let inferredWater = inferredPurifiedWaterAmounts(draft: draft)[ingredient.id] {
            return formatAmount(inferredWater)
        }

        if ingredient.isAd || ingredient.isQS {
            return (draft.normalizedTargetValue ?? (ingredient.amountValue > 0 ? ingredient.amountValue : nil)).map(formatAmount) ?? ""
        }

        guard ingredient.amountValue > 0 else { return "" }
        return formatAmount(ingredient.amountValue)
    }

    private func ingredientAmountUnitText(_ ingredient: IngredientDraft, draft: ExtempRecipeDraft) -> String {
        if let solutionAmount = solutionAmountParts(for: ingredient, draft: draft) {
            return solutionAmount.unitText
        }

        if nonAqueousMassAmountValueText(ingredient: ingredient, draft: draft) != nil {
            return "g"
        }

        if ingredient.isAd || ingredient.isQS {
            return draft.resolvedTargetUnit?.rawValue ?? ingredient.unit.rawValue
        }
        return ingredient.unit.rawValue
    }

    private func solutionAmountParts(
        for ingredient: IngredientDraft,
        draft: ExtempRecipeDraft
    ) -> (valueText: String, unitText: String)? {
        guard ingredient.presentationKind == .solution else { return nil }
        guard let volume = draft.solutionVolumeMl(for: ingredient), volume > 0 else { return nil }

        if let percent = draft.solutionDisplayPercent(for: ingredient) {
            return ("\(formatAmount(percent))%", "\(formatAmount(volume)) ml")
        }

        return (formatAmount(volume), "ml")
    }

    private func nonAqueousMassAmountValueText(ingredient: IngredientDraft, draft: ExtempRecipeDraft) -> String? {
        guard let primaryNonAqueous = NonAqueousSolventCatalog.primarySolvent(in: draft),
              primaryNonAqueous.ingredient?.id == ingredient.id,
              primaryNonAqueous.type != .ethanol,
              !usesNonAqueousMassTarget(draft: draft, solventIngredient: ingredient),
              ingredient.unit.rawValue == "ml",
              ingredient.amountValue > 0
        else {
            return nil
        }

        guard let density = NonAqueousSolventCatalog.density(
            for: primaryNonAqueous.type,
            fallback: ingredient.refDensity
        ), density > 0 else {
            return nil
        }

        return formatAmount(ingredient.amountValue * density)
    }

    private func usesNonAqueousMassTarget(draft: ExtempRecipeDraft, solventIngredient: IngredientDraft) -> Bool {
        if draft.explicitPowderTargetG != nil || draft.explicitLiquidTargetMl != nil || draft.legacyAdOrQsLiquidTargetMl != nil {
            return true
        }
        return solventIngredient.isAd || solventIngredient.isQS
    }

    private func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isLiquidLike(draft: ExtempRecipeDraft, routeBranch: String?) -> Bool {
        let effectiveFormMode = SignaUsageAnalyzer.effectiveFormMode(for: draft)
        if effectiveFormMode == .solutions || effectiveFormMode == .drops {
            return true
        }
        guard let routeBranch else { return false }
        return routeBranch.contains("solution")
            || routeBranch.contains("drops")
            || routeBranch.contains("infusion")
            || routeBranch.contains("decoction")
    }

    private func isPrimarySolvent(_ ingredient: IngredientDraft) -> Bool {
        if isPrimaryAqueousLiquid(ingredient) { return true }

        let solventType = (ingredient.refSolventType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if solventType.contains("water") || solventType.contains("aqueous") {
            return true
        }

        let hay = normalizedHay(ingredient)
        return hay.contains("aqua")
            || hay.contains("aquae")
            || hay.contains("water")
            || hay.contains("вода")
    }

    private func inferredPurifiedWaterAmounts(draft: ExtempRecipeDraft) -> [UUID: Double] {
        let targetMl = inferredTargetValue(from: draft) ?? 0
        guard targetMl > 0 else { return [:] }

        let burette = BuretteSystem.evaluateBurette(draft: draft)
        let buretteVolumeMl = burette.totalConcentrateVolumeMl
        let buretteIngredientIds = burette.matchedIngredientIds
        let inferredTargetSolutionIngredientId = inferredTargetSolutionIngredientId(in: draft)

        let waterCandidates = draft.ingredients.filter { ingredient in
            !ingredient.isQS
                && ingredient.unit.rawValue == "ml"
                && PurifiedWaterHeuristics.isPurifiedWater(ingredient)
        }
        guard !waterCandidates.isEmpty else { return [:] }

        let selectedWater: IngredientDraft? = {
            if let explicitAd = waterCandidates.last(where: { $0.isAd }) {
                return explicitAd
            }
            return waterCandidates.max(by: { $0.amountValue < $1.amountValue })
        }()
        guard let selectedWater else { return [:] }

        var otherLiquids = draft.ingredients.compactMap { ingredient -> Double? in
            guard !ingredient.isAd, !ingredient.isQS else { return nil }
            if ingredient.id == selectedWater.id { return nil }
            if buretteIngredientIds.contains(ingredient.id) { return nil }
            if let inferredTargetSolutionIngredientId, ingredient.id == inferredTargetSolutionIngredientId { return nil }
            if ingredient.presentationKind == .solution {
                return max(0, draft.solutionVolumeMl(for: ingredient) ?? 0)
            }
            guard ingredient.unit.rawValue == "ml" else { return nil }
            return max(0, ingredient.amountValue)
        }
        if buretteVolumeMl > 0 {
            otherLiquids.append(buretteVolumeMl)
        }

        let solids = draft.ingredients.compactMap { ingredient -> (weight: Double, kuo: Double?)? in
            guard !ingredient.isAd, !ingredient.isQS else { return nil }
            if buretteIngredientIds.contains(ingredient.id) { return nil }
            guard ingredient.unit.rawValue == "g", ingredient.amountValue > 0 else { return nil }
            guard !isLiquidIngredient(ingredient) else { return nil }
            return (weight: ingredient.amountValue, kuo: ingredient.refKuoMlPerG)
        }

        let adResult = PharmaCalculator.calculateAdWater(
            targetVolume: targetMl,
            otherLiquids: otherLiquids,
            solids: solids,
            kuoPolicy: .adaptive
        )
        guard adResult.amountToMeasure > 0 else { return [:] }

        let shouldOverride = selectedWater.isAd
            || selectedWater.amountValue <= 0
            || draft.explicitLiquidTargetMl == nil
            || abs(adResult.amountToMeasure - selectedWater.amountValue) > 0.0001
        guard shouldOverride else { return [:] }

        return [selectedWater.id: adResult.amountToMeasure]
    }

    private func inferredTargetSolutionIngredientId(in draft: ExtempRecipeDraft) -> UUID? {
        let hasExplicitTarget = draft.explicitLiquidTargetMl != nil || draft.legacyAdOrQsLiquidTargetMl != nil
        guard !hasExplicitTarget else { return nil }

        let hasAquaCandidate = draft.ingredients.contains { ingredient in
            !ingredient.isQS
                && !ingredient.isAd
                && ingredient.unit.rawValue == "ml"
                && ingredient.amountValue > 0
                && PurifiedWaterHeuristics.isPurifiedWater(ingredient)
        }
        guard !hasAquaCandidate else { return nil }

        return draft.ingredients
            .filter { !$0.isQS && !$0.isAd && $0.presentationKind == .solution }
            .compactMap { ingredient -> (UUID, Double)? in
                guard let volume = draft.solutionVolumeMl(for: ingredient), volume > 0 else { return nil }
                return (ingredient.id, volume)
            }
            .max(by: { $0.1 < $1.1 })?
            .0
    }

    private func isLiquidIngredient(_ ingredient: IngredientDraft) -> Bool {
        if ingredient.unit.rawValue == "ml" { return true }
        switch ingredient.rpPrefix {
        case .sol, .tincture:
            return true
        default:
            return ingredient.presentationKind == .solution
        }
    }

    private func isBuretteConcentrateCandidate(_ ingredient: IngredientDraft, draft: ExtempRecipeDraft) -> Bool {
        guard draft.useBuretteSystem else { return false }
        guard ingredient.unit.rawValue == "g" else { return false }
        let hay = normalizedHay(ingredient)
        return BuretteSystem.concentrates.contains { concentrate in
            concentrate.markers.contains { hay.contains($0) }
        }
    }

    private func buretteConcentrateMatch(
        for ingredient: IngredientDraft,
        draft: ExtempRecipeDraft
    ) -> BuretteSystem.Concentrate? {
        guard isBuretteConcentrateCandidate(ingredient, draft: draft) else { return nil }
        let hay = normalizedHay(ingredient)
        return BuretteSystem.concentrates.first { concentrate in
            concentrate.markers.contains { hay.contains($0) }
        }
    }

    private func buretteTechnologyDisplayName(
        for ingredient: IngredientDraft,
        concentrate: BuretteSystem.Concentrate
    ) -> String {
        if let canonicalLatin = buretteCanonicalLatinName(concentrate: concentrate) {
            return "Sol. \(canonicalLatin) \(formatAmount(concentrate.concentrationPercent))%"
        }

        let base = (ingredient.refNameLatGen ?? ingredient.refNameLatNom ?? ingredient.displayName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return concentrate.titleRu }

        let withoutSol = base.replacingOccurrences(
            of: #"^\s*sol\.?\s+"#,
            with: "",
            options: .regularExpression
        )
        return "Sol. \(withoutSol) \(formatAmount(concentrate.concentrationPercent))%"
    }

    private func buretteCanonicalLatinName(concentrate: BuretteSystem.Concentrate) -> String? {
        let title = concentrate.titleRu.lowercased()
        if title.contains("кофеина-натрия бензоата") { return "Coffeini-natrii benzoatis" }
        if title.contains("натрия бромида") { return "Natrii bromidi" }
        if title.contains("магния сульфата") { return "Magnesii sulfatis" }
        if title.contains("калия иодида") || title.contains("калия йодида") { return "Kalii iodidi" }
        if title.contains("натрия гидрокарбоната") { return "Natrii hydrocarbonatis" }
        if title.contains("натрия салицилата") { return "Natrii salicylatis" }
        if title.contains("кальция хлорида") { return "Calcii chloridi" }
        if title.contains("глюкозы") { return "Glucosi" }
        if title.contains("гексаметилентетрамина") { return "Hexamethylentetramini" }
        if title.contains("калия бромида") { return "Kalii bromidi" }
        if title.contains("натрия бензоата") { return "Natrii benzoatis" }
        return nil
    }

    private func isProtectedColloid(_ ingredient: IngredientDraft) -> Bool {
        switch ingredient.refDissolutionType {
        case .colloidProtargol, .colloidCollargol, .ichthyol:
            return true
        case .none, .ordinary, .hmcRestrictedHeat, .hmcRestrictedCool, .hmcUnrestricted:
            break
        }
        let hay = normalizedHay(ingredient)
        return hay.contains("protarg") || hay.contains("collarg") || hay.contains("ichthy") || hay.contains("іхті")
    }

    private func isVmsIngredient(_ ingredient: IngredientDraft) -> Bool {
        switch ingredient.refDissolutionType {
        case .hmcRestrictedHeat, .hmcRestrictedCool, .hmcUnrestricted:
            return true
        case .none, .ordinary, .colloidProtargol, .colloidCollargol, .ichthyol:
            break
        }
        let hay = normalizedHay(ingredient)
        return hay.contains("pepsin")
            || hay.contains("pepsinum")
            || hay.contains("gelatin")
            || hay.contains("amylum")
            || hay.contains("starch")
            || hay.contains("крохмал")
            || hay.contains("methylcell")
    }

    private func isViscousLiquid(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        let type = (ingredient.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return hay.contains("syrup")
            || hay.contains("sirup")
            || hay.contains("sirupi")
            || hay.contains("сироп")
            || hay.contains("glycer")
            || hay.contains("гліцерин")
            || hay.contains("глицерин")
            || type == "syrup"
    }

    private func isVolatileLiquid(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        if requiresPremixWithMixture(ingredient) || isVolatileAqueousLiquid(ingredient) {
            return true
        }
        return ingredient.rpPrefix == .tincture
            || hay.contains("tinct")
            || hay.contains("настойк")
            || hay.contains("настоянк")
            || hay.contains("spirit")
            || hay.contains("alcohol")
            || hay.contains("спирт")
            || hay.contains("oleum")
            || hay.contains("ефір")
    }

    private func isAcidifier(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("acidum hydrochlor")
            || hay.contains("acidi hydrochlorici")
            || hay.contains("hydrochloric acid")
            || hay.contains("хлористовод")
            || hay.contains("солян")
    }

    private func isHardlySoluble(_ ingredient: IngredientDraft) -> Bool {
        WaterSolubilityHeuristics.isWaterInsolubleOrSparinglySoluble(ingredient.refSolubility)
    }

    private func isEasySoluble(_ ingredient: IngredientDraft) -> Bool {
        WaterSolubilityHeuristics.hasExplicitWaterSolubility(ingredient.refSolubility)
    }

    private func markerMatch(_ ingredient: IngredientDraft, keys: [String], values: [String]) -> Bool {
        ingredient.referenceHasMarkerValue(keys: keys, expectedValues: values)
            || ingredient.referenceContainsMarkerToken(values)
    }

    private func hasTechnologyRule(_ ingredient: IngredientDraft, _ rule: SubstanceTechnologyRule) -> Bool {
        ingredient.propertyOverride?.technologyRules.contains(rule) == true
    }

    private func isEthacridineIngredient(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("aethacrid")
            || hay.contains("ethacrid")
            || hay.contains("етакрид")
            || hay.contains("этакрид")
            || hay.contains("риванол")
            || hay.contains("rivanol")
    }

    private func isPotassiumPermanganateIngredient(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("permangan")
            || hay.contains("перманганат")
    }

    private func isHydrogenPeroxideIngredient(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("hydrogenii perox")
            || hay.contains("hydrogen peroxide")
            || hay.contains("перекис водню")
            || hay.contains("перекись водор")
            || hay.contains("пергідрол")
            || hay.contains("пергидрол")
    }

    private func isPapaverineHydrochlorideIngredient(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("papaverin")
            && (hay.contains("hydrochlorid") || hay.contains("гидрохлорид") || hay.contains("гідрохлорид"))
    }

    private func isBoricAcidIngredient(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("acidum boric")
            || hay.contains("acidi borici")
            || hay.contains("boric acid")
            || hay.contains("борна кислот")
            || hay.contains("кислота борн")
    }

    private func isFuracilinIngredient(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("furacil")
            || hay.contains("nitrofural")
            || hay.contains("фурацил")
    }

    private func isSilverNitrateIngredient(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("argenti nitrat")
            || hay.contains("silver nitrate")
            || hay.contains("нітрат срібл")
            || hay.contains("нитрат серебр")
            || hay.contains("ляпіс")
    }

    private func requiresBoilingWaterDissolution(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        if hay.contains("furacil") || hay.contains("nitrofural") || hay.contains("фурацил") {
            return true
        }
        if hasTechnologyRule(ingredient, .requiresBoilingWaterDissolution) { return true }
        if let temp = ingredient.refWaterTempC, temp >= 95 { return true }
        return markerMatch(
            ingredient,
            keys: ["instruction_id", "process_note", "solubility_speed"],
            values: ["boiling_water", "boilingwater", "boil_water", "heat_solvent_100c", "кипляч"]
        )
    }

    private func requiresHotWaterDissolution(_ ingredient: IngredientDraft) -> Bool {
        if isEthacridineIngredient(ingredient) || isPapaverineHydrochlorideIngredient(ingredient) { return true }
        if hasTechnologyRule(ingredient, .requiresHeatingForDissolution) { return true }
        if let temp = ingredient.refWaterTempC, temp >= 70, temp < 95 { return true }
        return markerMatch(
            ingredient,
            keys: ["instruction_id", "process_note", "solubility_speed"],
            values: ["heat_water_80c", "hot_solvent", "hot_water", "гаряч"]
        )
    }

    private func requiresWarmWaterDissolution(_ ingredient: IngredientDraft) -> Bool {
        if isPotassiumPermanganateIngredient(ingredient) { return true }
        if let temp = ingredient.refWaterTempC, temp >= 35, temp < 70 { return true }
        return markerMatch(
            ingredient,
            keys: ["instruction_id", "process_note", "solubility_speed"],
            values: ["warm_solvent", "warm_water", "40_50c", "40-50c", "тепл"]
        )
    }

    private func requiresNaClIsotonization(_ ingredient: IngredientDraft) -> Bool {
        if hasTechnologyRule(ingredient, .furacilinAddSodiumChloride) { return true }
        if ingredient.referenceHasMarkerValue(
            keys: ["needs_isotonization", "needsisotonization", "needs_isotonisation", "needsisotonisation"],
            expectedValues: ["yes", "true", "1"]
        ) {
            return true
        }
        return markerMatch(
            ingredient,
            keys: ["instruction_id", "process_note", "interaction_notes", "needs_isotonization"],
            values: ["add_nacl", "nacl_0_9", "isoton", "furacilin_add_sodium_chloride", "needs_isotonization"]
        )
    }

    private func requiresFreshlyDistilledWater(_ ingredient: IngredientDraft) -> Bool {
        if hasTechnologyRule(ingredient, .requiresFreshDistilledWater) { return true }
        return markerMatch(
            ingredient,
            keys: ["instruction_id", "process_note", "solvent_type"],
            values: ["freshly_distilled_water", "fresh_distilled_water", "recenter_destillata", "chloride_free_water", "безхлорид"]
        )
    }

    private func requiresGlassFilterOnly(_ ingredient: IngredientDraft) -> Bool {
        if isPotassiumPermanganateIngredient(ingredient) || isHydrogenPeroxideIngredient(ingredient) { return true }
        if hasTechnologyRule(ingredient, .avoidPaperFilter) { return true }
        return markerMatch(
            ingredient,
            keys: ["filter_type", "instruction_id", "process_note"],
            values: ["glass_filter_only", "glassfilteronly", "glass_filter", "no_organic_filter", "avoid_paper_filter"]
        )
    }

    private func isStrongOxidizerIngredient(_ ingredient: IngredientDraft) -> Bool {
        if isPotassiumPermanganateIngredient(ingredient) || isHydrogenPeroxideIngredient(ingredient) { return true }
        if hasTechnologyRule(ingredient, .oxidizerHandleSeparately) { return true }
        return markerMatch(
            ingredient,
            keys: ["instruction_id", "process_note", "interaction_notes"],
            values: ["strong_oxidizer", "oxidizer_handle_separately", "сильнийокисник"]
        )
    }

    private func markerDrivenLiquidDissolutionNote(
        for ingredient: IngredientDraft,
        includeIsotonization: Bool = true
    ) -> String? {
        var parts: [String] = []

        if requiresFreshlyDistilledWater(ingredient) {
            parts.append("розчиняти у Aqua purificata recenter destillata")
        } else if requiresBoilingWaterDissolution(ingredient) {
            parts.append("розчиняти у киплячій воді")
        } else if requiresHotWaterDissolution(ingredient) {
            if isEthacridineIngredient(ingredient) || isPapaverineHydrochlorideIngredient(ingredient) {
                parts.append("розчиняти у гарячій Aqua purificata (70-80°C)")
            } else {
                parts.append("розчиняти у гарячій Aqua purificata (80-90°C)")
            }
        } else if requiresWarmWaterDissolution(ingredient) {
            parts.append("розчиняти у теплій Aqua purificata (40-50°C)")
        }

        if includeIsotonization, requiresNaClIsotonization(ingredient) {
            parts.append("за потреби ізотонувати NaCl 0,9%")
        }
        if requiresGlassFilterOnly(ingredient) {
            parts.append("фільтрація тільки через скляний фільтр/скляну вату")
        }
        if isEthacridineIngredient(ingredient) {
            parts.append("проціджувати теплим крізь пухкий ватний тампон")
            parts.append("працювати в рукавичках; речовина інтенсивно забарвлює шкіру та обладнання")
        }
        if isFuracilinIngredient(ingredient) {
            parts.append("до фільтрації переконатися у повному розчиненні кристалів; за наявності осаду продовжити нагрівання та перемішування")
        }
        if isStrongOxidizerIngredient(ingredient) {
            parts.append("працювати окремими інструментами, уникати контакту з органікою")
        }
        if isSilverNitrateIngredient(ingredient) {
            parts.append("зважувати на окремих вагах; уникати контакту з металевими предметами")
            parts.append("перед фільтрацією промити скляний фільтр свіжоперегнаною водою")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "; ")
    }

    private func expandedSingleAqueousSolutionTechnologyOrder(draft: ExtempRecipeDraft) -> [TechnologyOrderItem]? {
        guard let ingredient = singleAqueousSolutionIngredient(in: draft) else { return nil }
        guard let volumeMl = draft.solutionVolumeMl(for: ingredient), volumeMl > 0 else { return nil }
        guard let activeMassG = draft.solutionActiveMassG(for: ingredient), activeMassG > 0 else { return nil }

        var items: [TechnologyOrderItem] = []
        items.append(
            TechnologyOrderItem(
                stepIndex: 1,
                ingredientId: nil,
                ingredientName: "Aqua purificata",
                amountText: formatAmount(volumeMl),
                unitText: "ml",
                note: solutionWaterPreparationNote(for: ingredient)
            )
        )

        if requiresNaClIsotonization(ingredient),
           !draft.ingredients.contains(where: isExplicitNatriiChloridum)
        {
            let nacl = 0.009 * volumeMl
            if nacl > 0 {
                items.append(
                    TechnologyOrderItem(
                        stepIndex: items.count + 1,
                        ingredientId: nil,
                        ingredientName: "Natrii chloridum",
                        amountText: formatAmount(nacl),
                        unitText: "g",
                        note: "розчинити у воді для ізотонування та покращення розчинності"
                    )
                )
            }
        }

        items.append(
            TechnologyOrderItem(
                stepIndex: items.count + 1,
                ingredientId: ingredient.id,
                ingredientName: activeLatinNameForSolutionIngredient(ingredient),
                amountText: formatAmount(activeMassG),
                unitText: "g",
                note: markerDrivenLiquidDissolutionNote(
                    for: ingredient,
                    includeIsotonization: false
                ) ?? "розчинити до повної прозорості"
            )
        )

        return items
    }

    private func singleAqueousSolutionIngredient(in draft: ExtempRecipeDraft) -> IngredientDraft? {
        guard draft.standardSolutionSourceKey == nil else { return nil }
        guard NonAqueousSolventCatalog.primarySolvent(in: draft) == nil else { return nil }

        let active = draft.ingredients.filter { !$0.isQS && !$0.isAd }
        guard active.count == 1, let ingredient = active.first else { return nil }
        guard ingredient.presentationKind == .solution else { return nil }
        guard !draft.solutionPercentRepresentsSolventStrength(for: ingredient) else { return nil }
        return ingredient
    }

    private func activeLatinNameForSolutionIngredient(_ ingredient: IngredientDraft) -> String {
        let base = (ingredient.refNameLatNom ?? ingredient.refNameLatGen ?? ingredient.displayName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return "Substantia" }

        if let range = base.range(of: #"^\s*sol\.?\s+"#, options: .regularExpression) {
            let trimmed = String(base[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return base
    }

    private func solutionWaterPreparationNote(for ingredient: IngredientDraft) -> String {
        if requiresFreshlyDistilledWater(ingredient) {
            return "відміряти Aqua purificata recenter destillata"
        }
        if requiresBoilingWaterDissolution(ingredient) {
            return "відміряти та довести до кипіння (ad 100°C)"
        }
        if requiresHotWaterDissolution(ingredient) {
            return (isEthacridineIngredient(ingredient) || isPapaverineHydrochlorideIngredient(ingredient))
                ? "відміряти та підігріти до 70-80°C"
                : "відміряти та підігріти до 80-90°C"
        }
        if requiresWarmWaterDissolution(ingredient) {
            return "відміряти та підігріти до 40-50°C"
        }
        return "взяти як первинний розчинник"
    }

    private func addIsotonizingNaClItemIfNeeded(items: inout [TechnologyOrderItem], draft: ExtempRecipeDraft) {
        guard !draft.ingredients.contains(where: isExplicitNatriiChloridum) else { return }

        let sources = draft.ingredients.filter {
            !$0.isQS && !$0.isAd && requiresNaClIsotonization($0)
        }
        guard !sources.isEmpty else { return }

        let inferredTarget = inferredTargetValue(from: draft) ?? 0
        let sourceVolume = sources.compactMap { draft.solutionVolumeMl(for: $0) }.max() ?? 0
        let targetVolumeMl = max(inferredTarget, sourceVolume)
        guard targetVolumeMl > 0 else { return }

        let naclMass = 0.009 * targetVolumeMl
        guard naclMass > 0 else { return }

        let sourceIds = Set(sources.map(\.id))
        let insertIndex = items.firstIndex { item in
            guard let ingredientId = item.ingredientId else { return false }
            return sourceIds.contains(ingredientId)
        } ?? items.count

        let item = TechnologyOrderItem(
            stepIndex: 0,
            ingredientId: nil,
            ingredientName: "Natrii chloridum",
            amountText: formatAmount(naclMass),
            unitText: "g",
            note: "розчинити у воді для ізотонування та покращення розчинності"
        )
        items.insert(item, at: insertIndex)
    }

    private func isExplicitNatriiChloridum(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("natrii chlorid")
            || hay.contains("natrii chloridi")
            || hay.contains("sodium chlorid")
            || hay.contains("натрію хлорид")
            || hay.contains("натрия хлорид")
    }

    private func safetyPriority(_ ingredient: IngredientDraft) -> Int {
        if ingredient.refIsNarcotic { return 0 }
        if ingredient.isReferenceListA { return 1 }
        if ingredient.isReferenceListB { return 2 }
        return 3
    }

    private func colloidOrVmsNote(for ingredient: IngredientDraft) -> String {
        if isAcidMediumDependent(ingredient) {
            return "внести після підкислення; не нагрівати"
        }
        if isProtectedColloid(ingredient) {
            return "ввести за спеціальним режимом без грубого збовтування"
        }
        return "ввести за спеціальним режимом набухання/розчинення"
    }

    private func defaultLiquidNote(for ingredient: IngredientDraft) -> String {
        if isAcidMediumDependent(ingredient) {
            return "внести після створення кислого середовища"
        }
        if isAromaticWater(ingredient) {
            return ingredient.hasReferenceAromaticWaterRatio
                ? "готова ароматна вода 1:1000; не нагрівати"
                : "не нагрівати; зберігати прохолодно"
        }
        if safetyPriority(ingredient) < 3 {
            return "внести під посиленим дозовим контролем"
        }
        return "вносити у робочому порядку"
    }

    private func isAcidMediumDependent(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("pepsin") || hay.contains("pepsinum")
    }

    private func containsSuspensionMarker(_ draft: ExtempRecipeDraft) -> Bool {
        draft.ingredients.contains(where: isHardlySoluble)
    }

    private func containsEmulsionMarker(_ draft: ExtempRecipeDraft) -> Bool {
        let hasWater = draft.ingredients.contains(where: isPrimarySolvent)
        let hasOil = draft.ingredients.contains { ingredient in
            let hay = normalizedHay(ingredient)
            return hay.contains("oleum")
                || hay.contains("olei")
                || hay.contains("oil")
                || hay.contains("олія")
                || hay.contains("масл")
        }
        return hasWater && hasOil
    }

    private func containsLightSensitiveMarker(_ draft: ExtempRecipeDraft) -> Bool {
        draft.ingredients.contains { ingredient in
            if ingredient.isAd || ingredient.isQS { return false }
            if PurifiedWaterHeuristics.isPurifiedWater(ingredient) { return false }
            if isStableHalideWithoutExplicitPhotolability(ingredient) {
                return false
            }
            return isEthacridineIngredient(ingredient)
                || ingredient.isReferenceLightSensitive
                || markerMatch(
                    ingredient,
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

    private func isStableHalideWithoutExplicitPhotolability(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
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

    private func containsAmberGlassMarker(_ draft: ExtempRecipeDraft) -> Bool {
        draft.ingredients.contains { ingredient in
            if ingredient.isAd || ingredient.isQS { return false }
            if PurifiedWaterHeuristics.isPurifiedWater(ingredient) { return false }
            return markerMatch(
                ingredient,
                keys: ["instruction_id", "process_note", "storage", "solvent_type"],
                values: [
                    "amberglass",
                    "orangeglass",
                    "оранжевескло",
                    "темнескло"
                ]
            )
        }
    }

    private func containsPhenolFamily(_ draft: ExtempRecipeDraft) -> Bool {
        draft.ingredients.contains(where: isPhenolFamily)
    }

    private func containsGlycerinFamily(_ draft: ExtempRecipeDraft) -> Bool {
        if let primary = NonAqueousSolventCatalog.primarySolvent(in: draft), primary.type == .glycerin {
            return true
        }
        return draft.ingredients.contains { ingredient in
            let hay = normalizedHay(ingredient)
            return hay.contains("glycer")
                || hay.contains("glycerin")
                || hay.contains("glycerinum")
                || hay.contains("гліцерин")
                || hay.contains("глицерин")
        }
    }

    private func hasPhenolFamilyInFattyOilSolution(_ draft: ExtempRecipeDraft) -> Bool {
        guard let primary = NonAqueousSolventCatalog.primarySolvent(in: draft),
              primary.type == .fattyOil
        else { return false }

        return draft.ingredients.contains { ingredient in
            guard !ingredient.isQS, !ingredient.isAd else { return false }
            guard ingredient.id != primary.ingredient?.id else { return false }
            return isPhenolFamily(ingredient)
        }
    }

    private func iodideComplexOrderPreparation(draft: ExtempRecipeDraft) -> IodideComplexOrderPreparation? {
        let activeIngredients = draft.ingredients.filter { !$0.isQS && !$0.isAd }
        let iodineIngredients = activeIngredients.filter(isIodineComponent)
        let iodideIngredients = activeIngredients.filter(isIodideComponent)
        guard !iodineIngredients.isEmpty, !iodideIngredients.isEmpty else { return nil }

        let primary = NonAqueousSolventCatalog.primarySolvent(in: draft)
        let iodineMass = iodineIngredients.reduce(0.0) { $0 + inferredMassG(for: $1, draft: draft) }
        let iodideMass = iodideIngredients.reduce(0.0) { $0 + inferredMassG(for: $1, draft: draft) }
        guard iodineMass > 0 || iodideMass > 0 else { return nil }

        let explicitWaterMass = draft.ingredients
            .filter { !$0.isQS && PurifiedWaterHeuristics.isPurifiedWater($0) }
            .map { max(0, draft.effectiveLiquidVolumeMl(for: $0)) }
            .reduce(0, +)
        let minimumWaterMass = primary?.type == .glycerin
            ? iodideMass * 1.5
            : max(iodideMass * 1.5, 0.2)
        let hasIodideSolutionCarrier = iodideIngredients.contains { $0.presentationKind == .solution }
        let waterMl: Double = {
            if hasIodideSolutionCarrier { return minimumWaterMass }
            if explicitWaterMass > 0 { return min(explicitWaterMass, minimumWaterMass) }
            return minimumWaterMass
        }()
        let hasExplicitWater = explicitWaterMass > 0

        return IodideComplexOrderPreparation(
            waterMl: waterMl,
            iodideIds: Set(iodideIngredients.map(\.id)),
            iodineIds: Set(iodineIngredients.map(\.id)),
            hasExplicitWater: hasExplicitWater,
            hasIodideSolutionCarrier: hasIodideSolutionCarrier,
            solventIngredientId: primary?.ingredient?.id
        )
    }

    private func inferredMassG(for ingredient: IngredientDraft, draft: ExtempRecipeDraft) -> Double {
        let inferred = draft.inferredActiveMassG(for: ingredient)
        if inferred > 0 { return inferred }
        if let fallback = ingredientMassG(ingredient), fallback > 0 { return fallback }
        return 0
    }

    private func isPhenolFamily(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("phenol")
            || hay.contains("phenolum")
            || hay.contains("carbol")
            || hay.contains("acidum carbol")
            || hay.contains("acidi carbol")
            || hay.contains("фенол")
            || hay.contains("карбол")
    }

    private func isGlycerinMarker(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("glycer")
            || hay.contains("glycerinum")
            || hay.contains("гліцерин")
            || hay.contains("глицерин")
    }

    private func isOilMarker(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("oleum")
            || hay.contains("olei")
            || hay.contains("oil")
            || hay.contains("олія")
            || hay.contains("масл")
    }

    private func isCastorOilComponent(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("ricini")
            || hay.contains("castor")
            || hay.contains("рицинов")
    }

    private func isGelatosaComponent(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("gelatos")
            || hay.contains("желатоз")
            || hay.contains("гелатоз")
    }

    private func isSulfurComponent(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("sulfur")
            || hay.contains("sulphur")
            || hay.contains("сірк")
            || hay.contains("серн")
    }

    private func isMentholComponent(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("menthol")
            || hay.contains("ментол")
    }

    private func isCamphorComponent(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("camphor")
            || hay.contains("камфор")
    }

    private func isIodineComponent(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        if hay.contains("iodid") || hay.contains("йодид") { return false }
        return hay.contains("iodum")
            || hay.contains(" iodi ")
            || hay.hasPrefix("iodi ")
            || hay.contains("iodine")
            || hay.contains(" йод ")
            || hay.hasPrefix("йод ")
    }

    private func isIodideComponent(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("iodid") || hay.contains("йодид")
    }

    private func ingredientMassG(_ ingredient: IngredientDraft) -> Double? {
        if ingredient.unit.rawValue == "g", ingredient.amountValue > 0 {
            return ingredient.amountValue
        }
        if ingredient.unit.rawValue == "ml", ingredient.amountValue > 0 {
            if let density = ingredient.refDensity, density > 0 {
                return ingredient.amountValue * density
            }
            if PurifiedWaterHeuristics.isPurifiedWater(ingredient) {
                return ingredient.amountValue
            }
        }
        return nil
    }

    private func containsAromaticWaterMarker(_ draft: ExtempRecipeDraft) -> Bool {
        draft.ingredients.contains(where: isAromaticWater)
    }

    private func containsVolatileAqueousMarker(_ draft: ExtempRecipeDraft) -> Bool {
        draft.ingredients.contains(where: isVolatileAqueousLiquid)
    }

    private func containsPremixVolatileDrops(_ draft: ExtempRecipeDraft) -> Bool {
        draft.ingredients.contains(where: requiresPremixWithMixture)
    }

    private func containsAromaticOrVolatileMarker(_ draft: ExtempRecipeDraft) -> Bool {
        containsAromaticWaterMarker(draft)
            || containsVolatileAqueousMarker(draft)
            || containsPremixVolatileDrops(draft)
            || containsAlcoholicTinctureLike(draft)
    }

    private func containsAlcoholicTinctureLike(_ draft: ExtempRecipeDraft) -> Bool {
        draft.ingredients.contains(where: isVolatileLiquid)
    }

    private func containsAntibioticMarker(_ draft: ExtempRecipeDraft) -> Bool {
        draft.ingredients.contains(where: isAntibioticIngredient)
    }

    private func isAntibioticIngredient(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        let activity = (ingredient.refPharmActivity ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if hay.contains("antibiot")
            || hay.contains("антибіот")
            || hay.contains("антибиот")
        {
            return true
        }
        return hay.contains("penicillin")
            || hay.contains("benzylpenicillin")
            || hay.contains("streptomycin")
            || hay.contains("gentamicin")
            || hay.contains("chloramphenicol")
            || hay.contains("levomycetin")
            || hay.contains("erythromycin")
            || hay.contains("tetracyclin")
            || hay.contains("cef")
            || hay.contains("цеф")
            || activity.contains("антибіот")
            || activity.contains("антибиот")
    }

    private func requiresAsepticPowderForWoundsOrNewborn(_ draft: ExtempRecipeDraft) -> Bool {
        requiresSterileExternalUse(signa: draft.signa)
            || requiresAsepticForNewborn(signa: draft.signa, patientAgeYears: draft.patientAgeYears)
    }

    private func requiresSterileExternalUse(signa: String) -> Bool {
        let s = signa.lowercased()
        return s.contains("рана")
            || s.contains("рану")
            || s.contains("ушкоджен")
            || s.contains("поврежден")
            || s.contains("открыт")
    }

    private func requiresAsepticForNewborn(signa: String, patientAgeYears: Int?) -> Bool {
        if let patientAgeYears, patientAgeYears <= 1 {
            return true
        }
        let s = signa.lowercased()
        return s.contains("новорож")
            || s.contains("новонарод")
            || s.contains("неонат")
            || s.contains("немовля")
            || s.contains("груднич")
            || s.contains("infant")
            || s.contains("newborn")
    }

    private func isAromaticWater(_ ingredient: IngredientDraft) -> Bool {
        ingredient.isReferenceAromaticWater
    }

    private func isVolatileAqueousLiquid(_ ingredient: IngredientDraft) -> Bool {
        ingredient.isReferenceVolatileAqueousLiquid
    }

    private func requiresPremixWithMixture(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("liquor ammonii anisati")
            || hay.contains("ammonii anisati")
            || hay.contains("нашатирно-аніс")
            || hay.contains("нашатырно-анис")
            || hay.contains("spiritus menthae")
            || hay.contains("spirit of peppermint")
    }

    private func isLateAddedReadyLiquid(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("adonisid")
            || hay.contains("adonizid")
            || hay.contains("adonis")
    }

    private func isPrimaryAqueousLiquid(_ ingredient: IngredientDraft) -> Bool {
        if PurifiedWaterHeuristics.isPurifiedWater(ingredient) { return true }
        return ingredient.isReferenceAromaticWater
    }

    private func shouldAddAromaticWaterAfterFiltration(_ ingredient: IngredientDraft, draft: ExtempRecipeDraft) -> Bool {
        guard isAromaticWater(ingredient) else { return false }
        return draft.ingredients.contains { other in
            other.id != ingredient.id
                && !other.isAd
                && !other.isQS
                && isPrimarySolvent(other)
        }
    }

    private func normalizedHay(_ ingredient: IngredientDraft) -> String {
        let a = (ingredient.refNameLatNom ?? ingredient.displayName).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = (ingredient.refInnKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let c = ingredient.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [a, b, c].joined(separator: " ")
    }

    private func formatAmount(_ value: Double) -> String {
        let normalized = abs(value) < 0.0000005 ? 0 : value
        if normalized == floor(normalized), abs(normalized) >= 1 {
            return String(format: "%.1f", normalized).replacingOccurrences(of: ",", with: ".")
        }

        let decimals: Int = {
            let magnitude = abs(normalized)
            if magnitude > 0 && magnitude < 0.001 { return 6 }
            return 3
        }()

        var text = String(format: "%.\(decimals)f", normalized).replacingOccurrences(of: ",", with: ".")
        while text.contains(".") && text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.append("0")
        }
        return text
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "uk_UA")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }
}
