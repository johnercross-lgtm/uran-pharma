import Foundation

struct StrongControlBlock: RxProcessingBlock {
    static let blockId = "strong_control"
    let id = blockId

    func apply(context: inout RxPipelineContext) {
        let resolved = StrongControl.resolve(draft: context.draft)
        guard !resolved.results.isEmpty else { return }

        let results = resolved.results
        let ingredientById = Dictionary(uniqueKeysWithValues: context.draft.ingredients.map { ($0.id, $0) })
        let powderTechnology = resolved.powderTechnology
        let ownsPowderTechnology = context.draft.formMode == .powders && !PoisonControl.containsListA(draft: context.draft)
        let listBNames = results.map(\.ingredientName).joined(separator: ", ")

        if context.draft.formMode == .powders, (context.draft.numero ?? 0) <= 0 {
            context.addIssue(
                code: "strong.listb.powders.numeroRequired",
                severity: .blocking,
                message: "Для порошків зі Списком Б обов'язково вказати кількість доз (numero)"
            )
        }
        if powderTechnology != nil, ownsPowderTechnology, context.powderTechnology == nil {
            context.powderTechnology = powderTechnology
            context.routeBranch = "powders"
        }

        context.addStep(
            TechStep(
                kind: .prep,
                title: "Список Б: перевірити дозовий контроль та підготувати запис Heroica",
                ingredientIds: results.map(\.ingredientId),
                isCritical: true
            )
        )

        var doseLines: [String] = []
        var calcLines: [String] = []
        var techLines: [String] = []
        var packagingLines: [String] = []
        var qualityLines: [String] = []
        var controlLines: [String] = [
            "Виявлено речовини Списку Б: \(listBNames)"
        ]

        if let powderTechnology, ownsPowderTechnology {
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

            calcLines.append("Нормативна база: ДФУ (2001), правила порошків")
            calcLines.append("Класифікація пропису: \(powderComponents.count <= 1 ? "простий" : "складний") порошок")
            calcLines.append("Шлях застосування: \(route.displayName)")

            for plan in powderTechnology.triturationPlans {
                guard let ratio = plan.ratio else { continue }
                let perDoseActive = plan.totalActiveMass / Double(max(1, powderTechnology.dosesCount))
                calcLines.append("\(plan.ingredientName): \(formatMass(perDoseActive)) * \(powderTechnology.dosesCount) = \(formatMass(plan.totalActiveMass)) g")
                calcLines.append("Trituratio \(plan.ingredientName) 1:\(ratio): \(formatMass(plan.totalActiveMass)) * \(ratio) = \(formatMass(plan.totalTriturationMass)) g")
            }
            if !potentTinyTotals.isEmpty {
                for component in potentTinyTotals {
                    let perDose = component.totalG / Double(max(1, powderTechnology.dosesCount))
                    let ratio = perDose < 0.005 ? "1:100" : "1:10"
                    calcLines.append("\(component.name): total \(formatMass(component.totalG)) g (<0.05 g) -> рекомендована тритурація \(ratio)")
                }
            }

            if let fillerMass = powderTechnology.correctedFillerMass,
               let originalFillerMass = powderTechnology.originalFillerMass
            {
                let fillerName = powderTechnology.fillerIngredientName ?? StrongControl.defaultDiluent
                let triturationDiluent = powderTechnology.triturationPlans.reduce(0.0) { partial, plan in
                    partial + max(0, plan.totalTriturationMass - plan.totalActiveMass)
                }
                calcLines.append("\(fillerName): (\(formatMass(originalFillerMass / Double(max(1, powderTechnology.dosesCount)))) * \(powderTechnology.dosesCount)) - \(formatMass(triturationDiluent)) = \(formatMass(fillerMass)) g")
            } else if powderTechnology.fillerAdded > 0 {
                calcLines.append("Автодоведення наповнювачем до 0.3 g/дозу: +\(formatMass(powderTechnology.fillerAdded)) g \(StrongControl.defaultDiluent)")
            }

            if let fillerMass = powderTechnology.correctedFillerMass {
                let triturationMass = powderTechnology.triturationPlans.reduce(0.0) { $0 + $1.totalTriturationMass }
                let nonTriturationMass = roundInternal(powderTechnology.totalPowderMass - triturationMass)
                calcLines.append("Загальна маса: \(formatMass(triturationMass)) + \(formatMass(nonTriturationMass)) = \(formatMass(powderTechnology.totalPowderMass)) g")
                if fillerMass > 0 {
                    controlLines.append("• Скоригований наповнювач: \(formatMass(fillerMass)) g")
                }
            } else {
                calcLines.append("Загальна маса: \(formatMass(powderTechnology.totalPowderMass)) g")
            }

            calcLines.append("Маса 1 дози: \(formatMass(powderTechnology.totalPowderMass)) / \(powderTechnology.dosesCount) = \(formatMass(powderTechnology.doseMass)) g")
            calcLines.append("Допустиме відхилення: ±\(formatMass(powderTechnology.allowedDeviationPercent))% (\(formatMass(powderTechnology.lowerDeviationMass))–\(formatMass(powderTechnology.upperDeviationMass)) g)")

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
                let fillerName = powderTechnology.fillerIngredientName ?? StrongControl.defaultDiluent
                techLines.append("• Спочатку затерти пори ступки частиною \(fillerName)")
                if powderTechnology.triturationPlans.isEmpty {
                    for ingredient in context.draft.ingredients where ingredient.isReferenceListB && !ingredient.isAd && !ingredient.isQS {
                        techLines.append("• Внести \(latinName(ingredient)) у затерту ступку")
                    }
                } else {
                    for plan in powderTechnology.triturationPlans {
                        if let ratio = plan.ratio {
                            techLines.append("• Trituratio \(plan.ingredientName) 1:\(ratio) внести у затерту ступку")
                        }
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
                if powderTechnology.triturationPlans.isEmpty {
                    for ingredient in context.draft.ingredients where ingredient.isReferenceListB && !ingredient.isAd && !ingredient.isQS {
                        context.addStep(
                            TechStep(
                                kind: .trituration,
                                title: "Внести \(latinName(ingredient)) у затерту ступку",
                                ingredientIds: [ingredient.id],
                                isCritical: true
                            )
                        )
                    }
                } else {
                    for plan in powderTechnology.triturationPlans {
                        guard let ratio = plan.ratio else { continue }
                        context.addStep(
                            TechStep(
                                kind: .trituration,
                                title: "Внести Trituratio \(plan.ingredientName) 1:\(ratio) у затерту ступку",
                                ingredientIds: [plan.ingredientId],
                                isCritical: true
                            )
                        )
                    }
                }
                context.addStep(
                    TechStep(
                        kind: .mixing,
                        title: "Додати решту наповнювача методом геометричного розведення",
                        ingredientIds: powderTechnology.fillerIngredientId.map { [$0] } ?? [],
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
                if let profile = concentrationControlProfile(
                    draft: context.draft,
                    ingredientId: result.ingredientId
                ) {
                    if let concentration = profile.concentrationPercent {
                        doseLine += "зовнішнє застосування: контроль ВРД/ВСД не потрібен; контроль концентрації \(formatMass(concentration))% (\(profile.title))"
                    } else {
                        doseLine += "зовнішнє застосування: контроль ВРД/ВСД не потрібен; препарат класифіковано як офіцинальний/комплексний (\(profile.title)), контролюється концентрація"
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
                      context.draft.signa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                doseLine += "; потрібна Signa для розрахунку добової дози"
            }
            if validation.requiresNumericAndTextDose,
               (validation.exceedsPerDose || validation.exceedsPerDay),
               validation.overrideAccepted
            {
                doseLine += "; дозу перевищено обґрунтовано позначкою !"
            }
            doseLines.append(doseLine)

            if validation.requiresNumericAndTextDose && (validation.exceedsPerDose || validation.exceedsPerDay) {
                if validation.overrideAccepted {
                    context.addIssue(
                        code: "strong.listb.override.\(result.ingredientId)",
                        severity: .warning,
                        message: "Список Б: перевищення дози для \(result.ingredientName) позначено '!' у Signa, потрібна ручна перевірка"
                    )
                } else {
                    context.addIssue(
                        code: "strong.listb.doseExceeded.\(result.ingredientId)",
                        severity: .blocking,
                        message: "Список Б: перевищено ВРД/ВСД для \(result.ingredientName); без '!' у Signa готування заблоковане, орієнтир відпуску: не більше 1/2 ВРД"
                    )
                    controlLines.append("• \(result.ingredientName): блокування без '!'; орієнтир відпуску: не більше 1/2 ВРД")
                }
            }

            for warning in result.blockingWarnings {
                context.addIssue(
                    code: "strong.listb.validation.\(result.ingredientId)",
                    severity: .blocking,
                    message: warning
                )
                controlLines.append("• \(result.ingredientName): \(warning)")
            }

            controlLines.append("• \(result.ingredientName): зберігання — \(result.storage)")
            controlLines.append(contentsOf: result.ppkNotes.map { "• \(result.ingredientName): \($0)" })
            controlLines.append(contentsOf: result.physicalWarnings.map { "• \(result.ingredientName): \($0)" })

            if context.draft.formMode != .powders || powderTechnology?.requiresPoreRubbing != true {
                techLines.append(contentsOf: result.mixingInstructions.map { "• \($0)" })
            }

            packagingLines.append("• \(result.ingredientName): \(result.packaging.joined(separator: ", "))")
            packagingLines.append("• Етикетки: \(result.requiredLabels.joined(separator: ", "))")

            switch result.method {
            case .directWeighing, .dissolveFirst:
                break
            case .trituration(let ratio):
                if context.draft.formMode == .powders, powderTechnology?.requiresPoreRubbing == true {
                    break
                }
                context.addStep(
                    TechStep(
                        kind: .trituration,
                        title: "Список Б: для \(result.ingredientName) виконати тритурацію 1:\(ratio)",
                        ingredientIds: [result.ingredientId],
                        isCritical: true
                    )
                )
            case .dissolveInMinimalVolume(let volumeMl):
                context.addStep(
                    TechStep(
                        kind: .mixing,
                        title: "Список Б: \(result.ingredientName) розчинити у мінімальному об’ємі \(formatMass(volumeMl)) ml",
                        ingredientIds: [result.ingredientId],
                        isCritical: true
                    )
                )
            }
        }

        if !calcLines.isEmpty {
            let title = context.draft.formMode == .powders ? "Розрахунки" : "Розрахунки Списку Б"
            context.appendSection(title: title, lines: calcLines)
        }
        if !doseLines.isEmpty {
            context.appendSection(title: "Контроль доз", lines: doseLines)
        }
        if !techLines.isEmpty {
            context.appendSection(title: "Технологія Списку Б", lines: deduplicated(techLines))
        }
        if !qualityLines.isEmpty {
            context.appendSection(title: "Контроль якості", lines: deduplicated(qualityLines))
        }
        if !packagingLines.isEmpty {
            context.appendSection(title: "Упаковка/Маркування", lines: deduplicated(packagingLines))
        }
        context.appendSection(title: "Контроль списку Б", lines: deduplicated(controlLines))

        context.calculations["strong_list_b_present"] = "true"
        context.calculations["strong_list_b_names"] = listBNames
        if let powderTechnology {
            context.calculations["strong_powder_total_mass_g"] = formatMass(powderTechnology.totalPowderMass)
            context.calculations["strong_powder_dose_mass_g"] = formatMass(powderTechnology.doseMass)
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

    private func roundInternal(_ value: Double) -> Double {
        (value / StrongControl.internalPrecision).rounded() * StrongControl.internalPrecision
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

    private func concentrationControlProfile(
        draft: ExtempRecipeDraft,
        ingredientId: UUID
    ) -> ConcentrationControlProfile? {
        guard let ingredient = draft.ingredients.first(where: { $0.id == ingredientId }) else { return nil }
        return NonAqueousSolventCatalog.concentrationControlProfile(for: ingredient)
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
