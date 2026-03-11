import Foundation

struct PoisonControlBlock: RxProcessingBlock {
    static let blockId = "poison_control"
    let id = blockId

    func apply(context: inout RxPipelineContext) {
        let resolved = PoisonControl.resolve(draft: context.draft)
        guard !resolved.results.isEmpty else { return }

        let results = resolved.results
        let ingredientById = Dictionary(uniqueKeysWithValues: context.draft.ingredients.map { ($0.id, $0) })
        context.powderTechnology = resolved.powderTechnology
        let listANames = results.map(\.ingredientName).joined(separator: ", ")
        let powderTechnology = resolved.powderTechnology

        if context.draft.formMode == .powders, (context.draft.numero ?? 0) <= 0 {
            context.addIssue(
                code: "poison.lista.powders.numeroRequired",
                severity: .blocking,
                message: "Для порошків зі Списком А обов'язково вказати кількість доз (numero)"
            )
        }
        if powderTechnology != nil, context.draft.formMode == .powders {
            context.routeBranch = "powders"
        }

        let hasSeparateWeighing = results.contains(where: \.separateWeighing)
        let prepTitle: String = {
            switch context.draft.formMode {
            case .powders:
                return "Список А: підготувати окремі терези, окрему ступку та журнал контролю"
            case .solutions, .drops:
                if hasSeparateWeighing {
                    return "Список А: підготувати окремі терези, підставку/мірний посуд та журнал контролю"
                }
                return "Список А: підготувати окремий мірний посуд, підставку та журнал контролю (без зважування рідин)"
            case .ointments, .suppositories, .auto:
                if hasSeparateWeighing {
                    return "Список А: підготувати окремі терези, підставку та журнал контролю"
                }
                return "Список А: підготувати окремий мірний посуд, підставку та журнал контролю (без зважування рідин)"
            }
        }()

        context.addStep(
            TechStep(
                kind: .prep,
                title: prepTitle,
                ingredientIds: results.map(\.ingredientId),
                isCritical: true
            )
        )

        var doseLines: [String] = []
        var controlLines: [String] = [
            "Виявлено речовини Списку А: \(listANames)",
            "Потрібен подвійний контроль і підтвердження другого фармацевта",
            "Розфасування та маркування виконувати як для отруйних речовин"
        ]
        var packagingLines: [String] = []
        var poisonCalcLines: [String] = []
        var techLines: [String] = []
        var qualityLines: [String] = []

        if let powderTechnology {
            let powderComponents = powderComponents(draft: context.draft, dosesCount: powderTechnology.dosesCount)
            let route = powderRoute(
                draft: context.draft,
                components: powderComponents,
                ingredientById: ingredientById
            )
            let likelyActives = powderComponents.filter { isLikelyActive(component: $0, ingredientById: ingredientById) }
            let potentTinyTotals = likelyActives.filter { $0.totalG > 0 && $0.totalG < 0.05 }
            let volatilePowders = likelyActives.filter { isVolatilePowder(component: $0, ingredientById: ingredientById) }
            let needsAirtight = !volatilePowders.isEmpty || route == .effervescent
            let needsSterileExternal = route == .external && requiresSterileExternalUse(signa: context.draft.signa)
            let needsAsepticForNewborn = requiresAsepticForNewborn(
                signa: context.draft.signa,
                patientAgeYears: context.draft.patientAgeYears
            )
            let needsAsepticPowder = needsSterileExternal || needsAsepticForNewborn
            let uniformityChecks = likelyActives.map {
                makeUniformityCheck(
                    for: $0,
                    perDoseMassG: powderTechnology.doseMass,
                    ingredientById: ingredientById,
                    dosesCount: powderTechnology.dosesCount
                )
            }
            let contentChecks = uniformityChecks.filter { $0.requiresContentUniformity }
            let contentChecksNonExcluded = contentChecks.filter { !$0.isExcluded }
            let activeChecks = uniformityChecks.filter { !$0.isExcluded }
            let requiresUniformityContent = !contentChecksNonExcluded.isEmpty
            let isSingleDosePack = powderTechnology.dosesCount > 1
            let skipMassUniformity = !activeChecks.isEmpty && activeChecks.allSatisfy { $0.requiresContentUniformity }
            let requiresMassUniformity = isSingleDosePack && !skipMassUniformity

            if powderTechnology.doseMass > 0.5 {
                context.addIssue(code: "powders.mass.high", severity: .warning, message: "Маса порошку на дозу > 0.5 g")
            }
            if powderTechnology.doseMass > 0.6 {
                context.addIssue(code: "powders.mass.too_high", severity: .blocking, message: "Маса порошку на дозу > 0.6 g")
            }
            if powderTechnology.fillerAdded > 0 {
                context.addIssue(code: "powders.mass.low", severity: .warning, message: "Розвеска < 0.3 g/дозу: масу доведено наповнювачем")
            }
            if !potentTinyTotals.isEmpty && powderTechnology.triturationPlans.isEmpty {
                context.addIssue(
                    code: "powders.trituration.required.unmet",
                    severity: .blocking,
                    message: "Є активні речовини <0.05 g (загалом), але тритурацію 1:10/1:100 не визначено."
                )
            } else if !potentTinyTotals.isEmpty {
                context.addIssue(
                    code: "powders.trituration.required",
                    severity: .info,
                    message: "Для активних речовин <0.05 g застосовано правило тритурації 1:10/1:100."
                )
            }
            if requiresUniformityContent {
                context.addIssue(
                    code: "powders.qc.uniformity_content.required",
                    severity: .warning,
                    message: "Потрібен тест однорідності вмісту (Test B): є активні <2 mg/дозу або <2% у дозі."
                )
            }
            if requiresMassUniformity {
                context.addIssue(
                    code: "powders.qc.uniformity_mass.required",
                    severity: .info,
                    message: "Для однодозового фасування потрібен контроль однорідності маси."
                )
            }
            if needsAsepticPowder {
                let msg = needsSterileExternal
                    ? "Для зовнішнього нанесення на ушкоджену шкіру/відкриті рани потрібне стерильне виготовлення."
                    : "Порошки для новонароджених слід виготовляти асептично; за термостійкості провести стерилізацію."
                context.addIssue(
                    code: "powders.external.sterile.required",
                    severity: .warning,
                    message: msg
                )
            }
            if !isSingleDosePack {
                context.addIssue(
                    code: "powders.multidose.measuring_device",
                    severity: .info,
                    message: "Для багатодозового порошку потрібен мірний пристрій у комплекті."
                )
            }

            poisonCalcLines.append("Нормативна база: ДФУ (2001), правила порошків")
            poisonCalcLines.append("Класифікація пропису: \(powderComponents.count <= 1 ? "простий" : "складний") порошок")
            poisonCalcLines.append("Шлях застосування: \(route.displayName)")
            for plan in powderTechnology.triturationPlans {
                guard let ratio = plan.ratio else { continue }
                let perDoseActive = plan.totalActiveMass / Double(max(1, powderTechnology.dosesCount))
                poisonCalcLines.append("\(plan.ingredientName): \(formatMass(perDoseActive)) * \(powderTechnology.dosesCount) = \(formatMass(plan.totalActiveMass)) g")
                poisonCalcLines.append("Trituratio \(plan.ingredientName) 1:\(ratio): \(formatMass(plan.totalActiveMass)) * \(ratio) = \(formatMass(plan.totalTriturationMass)) g")
            }
            if !potentTinyTotals.isEmpty {
                for component in potentTinyTotals {
                    let perDose = component.totalG / Double(max(1, powderTechnology.dosesCount))
                    let ratio = perDose < 0.005 ? "1:100" : "1:10"
                    poisonCalcLines.append("\(component.name): total \(formatMass(component.totalG)) g (<0.05 g) -> рекомендована тритурація \(ratio)")
                }
            }

            if let fillerMass = powderTechnology.correctedFillerMass,
               let originalFillerMass = powderTechnology.originalFillerMass
            {
                let fillerName = powderTechnology.fillerIngredientName ?? PoisonControl.defaultDiluent
                let triturationTotalMass = powderTechnology.triturationPlans.reduce(0.0) { $0 + $1.totalTriturationMass }
                poisonCalcLines.append("\(fillerName): (\(formatMass(originalFillerMass / Double(max(1, powderTechnology.dosesCount)))) * \(powderTechnology.dosesCount)) - \(formatMass(triturationTotalMass)) = \(formatMass(fillerMass)) g")
            } else if powderTechnology.fillerAdded > 0 {
                poisonCalcLines.append("Автодоведення наповнювачем до 0.3 g/дозу: +\(formatMass(powderTechnology.fillerAdded)) g \(PoisonControl.defaultDiluent)")
            }

            if let fillerMass = powderTechnology.correctedFillerMass {
                let triturationMass = powderTechnology.triturationPlans.reduce(0.0) { $0 + $1.totalTriturationMass }
                poisonCalcLines.append("Загальна маса: \(formatMass(triturationMass)) + \(formatMass(fillerMass)) = \(formatMass(powderTechnology.totalPowderMass)) g")
            } else {
                poisonCalcLines.append("Загальна маса: \(formatMass(powderTechnology.totalPowderMass)) g")
            }

            poisonCalcLines.append("Маса 1 дози: \(formatMass(powderTechnology.totalPowderMass)) / \(powderTechnology.dosesCount) = \(formatMass(powderTechnology.doseMass)) g")
            poisonCalcLines.append("Допустиме відхилення: ±\(formatMass(powderTechnology.allowedDeviationPercent))% (\(formatMass(powderTechnology.lowerDeviationMass))–\(formatMass(powderTechnology.upperDeviationMass)) g)")
            if powderTechnology.roundingCorrection != 0 {
                poisonCalcLines.append("Корекція округлення покладена на наповнювач останньої дози: \(formatMass(powderTechnology.roundingCorrection)) g")
            }

            qualityLines.append("Дисперсність: ситовий аналіз або інший валідований метод.")
            qualityLines.append("Відсутність агрегатів/грудок частинок.")
            if requiresUniformityContent {
                qualityLines.append("Однорідність вмісту (Test B): обов'язково для активних <2 mg/дозу або <2% у дозі.")
                for check in contentChecksNonExcluded {
                    qualityLines.append("\(check.name): \(formatMass(check.perDoseMg)) mg/дозу; \(formatMass(check.percentInDose))% у дозі.")
                }
            }
            if contentChecks.contains(where: \.isExcluded) {
                qualityLines.append("Для multivitamins/microelements тест однорідності вмісту може не застосовуватись за монографією.")
            }
            if requiresMassUniformity {
                qualityLines.append("Однорідність маси: обов'язково для однодозового фасування.")
            } else if isSingleDosePack && skipMassUniformity {
                qualityLines.append("Однорідність маси може бути пропущена, бо однорідність вмісту потрібна для всіх активних.")
            }
            let assayMode = isSingleDosePack ? "g/mg/IU на 1 дозу" : "g/mg/IU на 1 g"
            qualityLines.append("Кількісне визначення: виражати як \(assayMode).")
            qualityLines.append("Граничне відхилення вмісту: не більше ±10%.")
            qualityLines.append("Додатково за потреби: pH, важкі метали.")

            if route == .external {
                packagingLines.append("• Маркування: «Для зовнішнього застосування».")
            }
            if needsAsepticPowder {
                packagingLines.append("• Маркування: «Стерильно».")
            }
            if isSingleDosePack {
                packagingLines.append("• Фасування: однодозові пакети (саше/паперові капсули).")
                packagingLines.append("• Для кожної дози вказати активну речовину та кількість.")
                packagingLines.append("• Додатково: термін придатності, умови зберігання, спосіб застосування.")
            } else {
                packagingLines.append("• Фасування: багатодозова тара.")
                packagingLines.append("• Додати мірний пристрій у комплект.")
            }
            packagingLines.append(needsAirtight
                ? "• Зберігати в герметично закритій тарі (airtight)."
                : "• Зберігати в щільно закритій тарі.")

            if powderTechnology.requiresPoreRubbing {
                let fillerName = powderTechnology.fillerIngredientName ?? PoisonControl.defaultDiluent
                techLines.append("• Спочатку затерти пори ступки частиною \(fillerName)")
                for plan in powderTechnology.triturationPlans {
                    if let ratio = plan.ratio {
                        techLines.append("• Trituratio \(plan.ingredientName) 1:\(ratio) внести в середину")
                    }
                }
                techLines.append("• Додати решту наповнювача методом геометричного розведення")

                context.addStep(
                    TechStep(
                        kind: .trituration,
                        title: "Затерти пори ступки частиною \(fillerName)",
                        ingredientIds: powderTechnology.fillerIngredientId.map { [$0] } ?? [],
                        isCritical: true
                    )
                )
                for plan in powderTechnology.triturationPlans {
                    guard let ratio = plan.ratio else { continue }
                    context.addStep(
                        TechStep(
                            kind: .trituration,
                            title: "Внести Trituratio \(plan.ingredientName) 1:\(ratio) у середину",
                            ingredientIds: [plan.ingredientId],
                            isCritical: true
                        )
                    )
                }
                context.addStep(
                    TechStep(
                        kind: .mixing,
                        title: "Додати решту наповнювача методом геометричного розведення",
                        ingredientIds: powderTechnology.fillerIngredientId.map { [$0] } ?? [],
                        isCritical: true
                    )
                )
                context.addStep(
                    TechStep(
                        kind: .packaging,
                        title: "Розділити на \(powderTechnology.dosesCount) порошків по \(formatMass(powderTechnology.doseMass)) g",
                        isCritical: true
                    )
                )
                context.addStep(
                    TechStep(
                        kind: .packaging,
                        title: "Упакувати в паперові капсули",
                        isCritical: true
                    )
                )
                context.addStep(
                    TechStep(
                        kind: .labeling,
                        title: "Маркування: ЯД, сигнатура (рожева смуга), Поводитись обережно, Берегти від дітей; флакон опечатати",
                        isCritical: true
                    )
                )
            }
            if route == .effervescent {
                techLines.append("• Для шипучого порошку: перед застосуванням розчинити/диспергувати у воді")
            }
            if needsAsepticPowder {
                if needsSterileExternal {
                    techLines.append("• Виготовити у стерильних умовах (зовнішнє застосування на ушкоджену шкіру/рани)")
                } else {
                    techLines.append("• Виготовити в асептичних умовах (порошок для новонародженого); за термостійкості провести стерилізацію")
                }
            }
        }

        for result in results {
            let validation = result.doseValidation
            var doseLine = "• \(result.ingredientName): "
            if !validation.requiresNumericAndTextDose {
                if let concentration = phenolGlycerinConcentrationPercent(
                    draft: context.draft,
                    ingredientId: result.ingredientId
                ) {
                    if concentration > 5 {
                        doseLine += "зовнішнє застосування: контроль ВРД/ВСД не потрібен; ВИСОКА КОНЦЕНТРАЦІЯ \(formatMass(concentration))% (>5%), перевірити дозування"
                    } else {
                        doseLine += "зовнішнє застосування: концентрація \(formatMass(concentration))% у межах норми (2-5%); перевірка ВРД/ВСД не потрібна"
                    }
                } else {
                    doseLine += "зовнішнє застосування: контроль ВРД/ВСД не потрібен, контролюється концентрація"
                }
            } else if let perDose = validation.perDoseG {
                doseLine += "разова доза \(formatMass(perDose)) g"
                if let limit = validation.perDoseLimitG {
                    doseLine += " / ВРД \(formatMass(limit)) g"
                }
            } else {
                doseLine += "разову дозу не вдалося обчислити автоматично"
            }
            if let perDay = validation.perDayG {
                doseLine += "; добова доза \(formatMass(perDay)) g"
                if let limit = validation.perDayLimitG {
                    doseLine += " / ВСД \(formatMass(limit)) g"
                }
            } else if validation.requiresNumericAndTextDose,
                      context.draft.signa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                doseLine += "; потрібна Signa для розрахунку добової дози"
            }
            doseLines.append(doseLine)

            if let perDose = validation.perDoseG, let limit = validation.perDoseLimitG, perDose > limit {
                context.addIssue(
                    code: "DoseExceedsMaximum.\(result.ingredientId).single",
                    severity: .blocking,
                    message: "Список А: перевищено ВРД для \(result.ingredientName) (\(formatMass(perDose)) g > \(formatMass(limit)) g)"
                )
            }
            if let perDay = validation.perDayG, let limit = validation.perDayLimitG, perDay > limit {
                context.addIssue(
                    code: "DoseExceedsMaximum.\(result.ingredientId).daily",
                    severity: .blocking,
                    message: "Список А: перевищено ВСД для \(result.ingredientName) (\(formatMass(perDay)) g > \(formatMass(limit)) g)"
                )
            }
            if validation.perDoseG == nil, validation.requiresNumericAndTextDose {
                context.addIssue(
                    code: "poison.lista.doseContextMissing.\(result.ingredientId)",
                    severity: .warning,
                    message: "Список А: для \(result.ingredientName) не вистачає даних для автоматичного розрахунку разової дози"
                )
            }

            if !(context.draft.formMode == .powders && powderTechnology?.requiresPoreRubbing == true) {
                techLines.append(contentsOf: result.mixingInstructions.map { "• \($0)" })
            }
            controlLines.append(contentsOf: result.ppkNotes.map { "• \(result.ingredientName): \($0)" })

            switch result.method {
            case .directWeighing:
                break
            case .trituration(let ratio):
                if context.draft.formMode == .powders, powderTechnology?.requiresPoreRubbing == true {
                    break
                }
                context.addStep(
                    TechStep(
                        kind: .trituration,
                        title: "Список А: для \(result.ingredientName) виконати тритурацію 1:\(ratio) з \(PoisonControl.defaultDiluent)",
                        ingredientIds: [result.ingredientId],
                        isCritical: true
                    )
                )
            case .concentrate(let volumeMl):
                context.addStep(
                    TechStep(
                        kind: .dissolution,
                        title: "Список А: для \(result.ingredientName) відібрати частину із вже відміряного розчинника (\(formatMass(volumeMl)) ml орієнтовно), приготувати концентрат і повернути його у загальний об’єм (кінцевий V не збільшувати)",
                        ingredientIds: [result.ingredientId],
                        isCritical: true
                    )
                )
            case .dissolvedInMinimalVolume(let volumeMl):
                context.addStep(
                    TechStep(
                        kind: .mixing,
                        title: "Список А: \(result.ingredientName) розчинити у мінімальному об’ємі \(formatMass(volumeMl)) ml та емульгувати в основу",
                        ingredientIds: [result.ingredientId],
                        isCritical: true
                    )
                )
            case .levigation(let liquidType, let liquidMassG):
                context.addStep(
                    TechStep(
                        kind: .mixing,
                        title: "Список А: \(result.ingredientName) левігувати з \(liquidType) (\(formatMass(liquidMassG)) g) і вводити геометричним методом",
                        ingredientIds: [result.ingredientId],
                        isCritical: true
                    )
                )
            }

            packagingLines.append("• \(result.ingredientName): \(result.packaging)")
            packagingLines.append("• Етикетки: \(result.requiredLabels.joined(separator: ", "))")
        }

        if !(context.draft.formMode == .powders && powderTechnology?.requiresPoreRubbing == true) {
            context.addStep(
                TechStep(
                    kind: .labeling,
                    title: "Список А: оформити сигнатуру (рожева смуга), маркування «ЯД», флакон опечатати",
                    ingredientIds: results.map(\.ingredientId),
                    isCritical: true
                )
            )
        }

        if !poisonCalcLines.isEmpty {
            let title = context.draft.formMode == .powders ? "Розрахунки" : "Розрахунки Списку А"
            context.appendSection(title: title, lines: poisonCalcLines)
        }
        if !doseLines.isEmpty {
            context.appendSection(title: "Контроль доз", lines: doseLines)
        }
        if !techLines.isEmpty, context.draft.formMode != .powders || powderTechnology?.requiresPoreRubbing == true {
            context.appendSection(title: "Технологія Списку А", lines: techLines)
        }
        if !qualityLines.isEmpty {
            context.appendSection(title: "Контроль якості", lines: deduplicated(qualityLines))
        }
        if !packagingLines.isEmpty {
            context.appendSection(title: "Упаковка/Маркування", lines: deduplicated(packagingLines))
        }
        context.appendSection(title: "Контроль списку А", lines: deduplicated(controlLines))

        context.calculations["poison_list_a_present"] = "true"
        context.calculations["poison_list_a_names"] = listANames
        if let powderTechnology {
            context.calculations["poison_powder_total_mass_g"] = formatMass(powderTechnology.totalPowderMass)
            context.calculations["poison_powder_dose_mass_g"] = formatMass(powderTechnology.doseMass)
            context.calculations["poison_powder_filler_added_g"] = formatMass(powderTechnology.fillerAdded)
            let route = powderRoute(
                draft: context.draft,
                components: powderComponents(draft: context.draft, dosesCount: powderTechnology.dosesCount),
                ingredientById: ingredientById
            )
            context.calculations["powders_route"] = route.displayName
        }
    }

    private func deduplicated(_ lines: [String]) -> [String] {
        var seen: Set<String> = []
        return lines.filter { seen.insert($0).inserted }
    }

    private func latinName(_ ingredient: IngredientDraft) -> String {
        let name = (ingredient.refNameLatNom ?? ingredient.displayName).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Subst." : name
    }

    private func formatMass(_ value: Double) -> String {
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

    private func powderComponents(draft: ExtempRecipeDraft, dosesCount: Int) -> [PowderComponent] {
        draft.ingredients.compactMap { ingredient in
            guard !ingredient.isQS, !ingredient.isAd else { return nil }
            guard ingredient.unit.rawValue == "g", ingredient.amountValue > 0 else { return nil }
            let total = resolvedTotalMass(rawValue: ingredient.amountValue, scope: ingredient.scope, draft: draft, dosesCount: dosesCount)
            guard total > 0 else { return nil }
            return PowderComponent(id: ingredient.id, name: latinName(ingredient), totalG: total)
        }
    }

    private func resolvedTotalMass(rawValue: Double, scope: AmountScope, draft: ExtempRecipeDraft, dosesCount: Int) -> Double {
        switch scope {
        case .perDose:
            return rawValue * Double(max(1, dosesCount))
        case .total:
            return rawValue
        case .auto:
            return draft.powderMassMode == .dispensa ? (rawValue * Double(max(1, dosesCount))) : rawValue
        }
    }

    private func powderRoute(
        draft: ExtempRecipeDraft,
        components: [PowderComponent],
        ingredientById: [UUID: IngredientDraft]
    ) -> PowderRoute {
        if isEffervescentPowder(components: components, ingredientById: ingredientById) {
            return .effervescent
        }
        let signa = draft.signa.lowercased()
        if signa.contains("зовніш")
            || signa.contains("наруж")
            || signa.contains("присып")
            || signa.contains("на кожу")
            || signa.contains("на шкіру")
        {
            return .external
        }
        return .oral
    }

    private func isLikelyActive(component: PowderComponent, ingredientById: [UUID: IngredientDraft]) -> Bool {
        guard let ingredient = ingredientById[component.id] else { return true }
        let hay = normalizedHaystack(ingredient: ingredient)
        if hay.contains("sacchar") || hay.contains("lactos") { return false }
        let refType = (ingredient.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if refType == "solvent" || refType == "base" || refType == "excipient" || refType == "aux" {
            return false
        }
        return true
    }

    private func isVolatilePowder(component: PowderComponent, ingredientById: [UUID: IngredientDraft]) -> Bool {
        let hay = component.name.lowercased() + " " + (ingredientById[component.id].map(normalizedHaystack(ingredient:)) ?? "")
        let markers = [
            "menthol", "camphor", "eucalypt", "oleum", "olei", "aether", "ether",
            "chloroform", "terebinth", "лаванд", "ефірн", "йодоформ"
        ]
        return markers.contains { hay.contains($0) }
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

    private func isEffervescentPowder(
        components: [PowderComponent],
        ingredientById: [UUID: IngredientDraft]
    ) -> Bool {
        func hay(_ component: PowderComponent) -> String {
            component.name.lowercased() + " " + (ingredientById[component.id].map(normalizedHaystack(ingredient:)) ?? "")
        }
        let hasAcid = components.contains { component in
            let text = hay(component)
            return text.contains("acid") || text.contains("лимонн") || text.contains("citric")
                || text.contains("tartar") || text.contains("ascorb")
        }
        let hasCarbonate = components.contains { component in
            let text = hay(component)
            return text.contains("carbonat")
                || text.contains("hydrocarbonat")
                || text.contains("bicarbon")
                || text.contains("натрію гідрокарбонат")
                || text.contains("натрия гидрокарбонат")
        }
        return hasAcid && hasCarbonate
    }

    private func makeUniformityCheck(
        for component: PowderComponent,
        perDoseMassG: Double,
        ingredientById: [UUID: IngredientDraft],
        dosesCount: Int
    ) -> UniformityCheck {
        let perDoseG = component.totalG / Double(max(1, dosesCount))
        let perDoseMg = perDoseG * 1_000
        let percentInDose = perDoseMassG > 0 ? (perDoseG / perDoseMassG) * 100 : 0
        let hay = component.name.lowercased() + " " + (ingredientById[component.id].map(normalizedHaystack(ingredient:)) ?? "")
        let isExcluded = hay.contains("multivit") || hay.contains("мікроелем") || hay.contains("microelement")
        return UniformityCheck(
            name: component.name,
            perDoseMg: perDoseMg,
            percentInDose: percentInDose,
            requiresContentUniformity: perDoseMg < 2 || percentInDose < 2,
            isExcluded: isExcluded
        )
    }

    private func normalizedHaystack(ingredient: IngredientDraft) -> String {
        [
            ingredient.displayName,
            ingredient.refNameLatNom ?? "",
            ingredient.refInnKey ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func phenolGlycerinConcentrationPercent(draft: ExtempRecipeDraft, ingredientId: UUID) -> Double? {
        guard let primary = NonAqueousSolventCatalog.primarySolvent(in: draft),
              primary.type == .glycerin,
              let solventIngredient = primary.ingredient
        else { return nil }

        let activeIngredients = draft.ingredients.filter { !$0.isAd && !$0.isQS }
        guard let phenol = activeIngredients.first(where: { $0.id == ingredientId }) else { return nil }

        guard let phenolMass = ingredientMassG(phenol), phenolMass > 0 else { return nil }
        guard let solventMass = ingredientMassG(solventIngredient, glycerinFallbackDensity: 1.25), solventMass > 0 else { return nil }

        let fixedMass = activeIngredients
            .filter { $0.id != solventIngredient.id }
            .compactMap { ingredientMassG($0) }
            .reduce(0, +)
        let totalMass = fixedMass + solventMass
        guard totalMass > 0 else { return nil }

        return (phenolMass / totalMass) * 100
    }

    private func ingredientMassG(_ ingredient: IngredientDraft, glycerinFallbackDensity: Double? = nil) -> Double? {
        guard ingredient.amountValue > 0 else { return nil }
        if ingredient.unit.rawValue == "g" {
            return ingredient.amountValue
        }
        guard ingredient.unit.rawValue == "ml" else { return nil }

        if let density = ingredient.refDensity, density > 0 {
            return ingredient.amountValue * density
        }
        let hay = normalizedHaystack(ingredient: ingredient)
        if hay.contains("glycer") || hay.contains("глицерин") || hay.contains("гліцерин"),
           let fallback = glycerinFallbackDensity {
            return ingredient.amountValue * fallback
        }
        if PurifiedWaterHeuristics.isPurifiedWater(ingredient) {
            return ingredient.amountValue
        }
        return nil
    }

    private struct PowderComponent {
        let id: UUID
        let name: String
        let totalG: Double
    }

    private struct UniformityCheck {
        let name: String
        let perDoseMg: Double
        let percentInDose: Double
        let requiresContentUniformity: Bool
        let isExcluded: Bool
    }

    private enum PowderRoute {
        case oral
        case external
        case effervescent

        var displayName: String {
            switch self {
            case .oral:
                return "оральний"
            case .external:
                return "зовнішній"
            case .effervescent:
                return "шипучий"
            }
        }
    }
}
