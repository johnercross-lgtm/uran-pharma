import Foundation

struct PowdersTriturationsBlock: RxProcessingBlock {
    static let blockId = "powders_triturations"
    let id = blockId

    func apply(context: inout RxPipelineContext) {
        context.routeBranch = "powders"

        let result = PowdersCalculator.calculate(draft: context.draft)
        let ingredientById = Dictionary(uniqueKeysWithValues: context.draft.ingredients.map { ($0.id, $0) })
        let hasColoring = result.components.contains(where: \.isColoring)
        let perDose = result.perDoseG
        let route = powderRoute(for: context.draft, components: result.components, ingredientById: ingredientById)
        let likelyActives = result.components.filter { isLikelyActive(component: $0, ingredientById: ingredientById) }
        let potentTinyTotals = likelyActives.filter { $0.totalG > 0 && $0.totalG < 0.05 }
        let volatilePowders = likelyActives.filter { isVolatilePowder(component: $0, ingredientById: ingredientById) }
        let needsAirtight = !volatilePowders.isEmpty || route == .effervescent
        let needsSterileExternal = route == .external && requiresSterileExternalUse(signa: context.draft.signa)
        let needsAsepticForNewborn = requiresAsepticForNewborn(
            signa: context.draft.signa,
            patientAgeYears: context.draft.patientAgeYears
        )
        let needsAsepticPowder = needsSterileExternal || needsAsepticForNewborn

        if perDose > 0.5 {
            context.addIssue(code: "powders.mass.high", severity: .warning, message: "Маса порошку на дозу > 0.5 g")
        }
        if perDose > 0.6 {
            context.addIssue(code: "powders.mass.too_high", severity: .blocking, message: "Маса порошку на дозу > 0.6 g")
        }
        if result.tinyActivesTotalG > 0 && !result.canBuildTrituration {
            context.addIssue(code: "powders.trituration.carrier.low", severity: .warning, message: "Недостатньо цукрового носія для тритурації 1:10")
        } else if result.canBuildTrituration {
            context.addIssue(code: "powders.trituration.recommended", severity: .info, message: "Застосовано рекомендацію тритурації 1:10")
        }
        if let filler = result.adFillerG, filler < 0 {
            context.addIssue(
                code: "powders.ad.impossible",
                severity: .blocking,
                message: "Неможливо довести масу ad: речовини перевищують target на \(format(abs(filler))) g"
            )
        }
        if result.autoFillG > 0 {
            context.addIssue(code: "powders.mass.low", severity: .warning, message: "Розвеска < 0.3 g/дозу: масу доведено наповнювачем")
        }
        if !potentTinyTotals.isEmpty && !result.canBuildTrituration {
            context.addIssue(
                code: "powders.trituration.required.unmet",
                severity: .blocking,
                message: "Є активні речовини <0.05 g (загалом), але тритурацію 1:10/1:100 неможливо виконати без носія."
            )
        } else if !potentTinyTotals.isEmpty {
            context.addIssue(
                code: "powders.trituration.required",
                severity: .info,
                message: "Для активних речовин <0.05 g застосовано правило тритурації 1:10/1:100."
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
        if result.n <= 1 {
            context.addIssue(
                code: "powders.multidose.measuring_device",
                severity: .info,
                message: "Для багатодозового порошку потрібен мірний пристрій у комплекті."
            )
        }

        context.calculations["powders_total_mass_g"] = format(result.totalMassG)
        context.calculations["powders_per_dose_g"] = format(result.perDoseG)
        context.calculations["powders_n"] = String(result.n)
        context.calculations["powders_mass_mode"] = result.mode.rawValue
        context.calculations["powders_route"] = route.rawValue
        if let target = result.adTargetTotalG {
            context.calculations["powders_ad_target_g"] = format(target)
        }
        if let filler = result.adFillerG, filler >= 0 {
            context.calculations["powders_ad_filler_g"] = format(filler)
        }
        if result.canBuildTrituration {
            context.calculations["powders_trituration_total_g"] = format(result.tinyActivesTotalG + result.triturationSugarNeedG)
        }
        if !potentTinyTotals.isEmpty {
            context.calculations["powders_tiny_totals_count"] = String(potentTinyTotals.count)
        }
        if needsAirtight {
            context.calculations["powders_container_mode"] = "airtight"
        }

        context.addStep(TechStep(kind: .trituration, title: "Подрібнення і змішування порошків за правилами геометричного розведення", isCritical: true))
        context.addStep(TechStep(kind: .packaging, title: "Дозування/фасування порошків за кількістю доз"))

        var calcLines: [String] = [
            "Нормативна база: ДФУ (2001), правила порошків",
            "Режим маси: \(result.mode.title)",
            "Кількість доз (N): \(result.n)",
            "Класифікація пропису: \(result.components.count <= 1 ? "простий" : "складний") порошок",
            "Сума без наповнювача: \(format(result.nonAdMassG)) g"
        ]
        if let target = result.adTargetTotalG {
            calcLines.append("Target ad/q.s.: \(format(target)) g")
            if let filler = result.adFillerG {
                if filler >= 0 {
                    let fillerName = (result.adBaseName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                        ? result.adBaseName!
                        : "Наповнювач"
                    calcLines.append("\(fillerName) ad: \(format(filler)) g")
                } else {
                    calcLines.append("⚠ ad/q.s. недосяжне: перевищення на \(format(abs(filler))) g")
                }
            }
        }
        if result.canBuildTrituration {
            calcLines.append("Тритурація 1:10: активні \(format(result.tinyActivesTotalG)) g + носій \(format(result.triturationSugarNeedG)) g")
        }
        if !potentTinyTotals.isEmpty {
            for component in potentTinyTotals {
                let ratio = component.perDoseG < 0.005 ? "1:100" : "1:10"
                calcLines.append("\(component.name): total \(format(component.totalG)) g (<0.05 g) -> рекомендована тритурація \(ratio)")
            }
        }
        if result.autoFillG > 0 {
            calcLines.append("Автодоведення наповнювачем до 0.3 g/дозу: +\(format(result.autoFillG)) g")
        }
        calcLines.append("Сумарна маса: \(format(result.totalMassG)) g")
        calcLines.append("Маса 1 дози: \(format(result.perDoseG)) g")

        let p = result.allowedDeviationPercent
        let lo = perDose * (1 - p / 100)
        let hi = perDose * (1 + p / 100)
        calcLines.append("Допустиме відхилення: ±\(format(p))% (\(format(lo))–\(format(hi)) g/дозу)")

        context.appendSection(title: "Розрахунки", lines: calcLines)

        let uniformityChecks = likelyActives.compactMap {
            makeUniformityCheck(for: $0, perDoseMassG: result.perDoseG, ingredientById: ingredientById)
        }
        let contentChecks = uniformityChecks.filter { $0.requiresContentUniformity }
        let contentChecksNonExcluded = contentChecks.filter { !$0.isExcluded }
        let activeChecks = uniformityChecks.filter { !$0.isExcluded }
        let requiresUniformityContent = !contentChecksNonExcluded.isEmpty
        let isSingleDosePack = result.n > 1
        let skipMassUniformity = !activeChecks.isEmpty && activeChecks.allSatisfy { $0.requiresContentUniformity }
        let requiresMassUniformity = isSingleDosePack && !skipMassUniformity

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

        var techLines: [String] = [
            "1. Подрібнити компоненти окремо за потреби",
            "2. Змішувати від найменших кількостей до більших (правило геометричного розведення)"
        ]
        techLines.append(result.canBuildTrituration ? "3. Виконати тритурацію 1:10 для малих доз активних" : "3. Тритурація не обов'язкова")
        if let filler = result.adFillerG, filler >= 0 {
            let fillerName = (result.adBaseName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? result.adBaseName!
                : "наповнювач"
            techLines.append("4. Довести масу \(fillerName) до ad/q.s.")
            techLines.append(hasColoring ? "5. Для барвників застосувати метод 'сендвіча' (затирати білим)" : "5. Розважити на дози та упакувати")
            if hasColoring {
                techLines.append("6. Розважити на дози та упакувати")
            }
        } else if hasColoring {
            techLines.append("4. Для барвників застосувати метод 'сендвіча' (затирати білим)")
            techLines.append("5. Розважити на дози та упакувати")
        } else {
            techLines.append("4. Розважити на дози та упакувати")
        }
        if route == .effervescent {
            techLines.append("5. Для шипучого порошку: перед застосуванням розчинити/диспергувати у воді")
        }
        if needsAsepticPowder {
            if needsSterileExternal {
                techLines.append("6. Виготовити у стерильних умовах (зовнішнє застосування на ушкоджену шкіру/рани)")
            } else {
                techLines.append("6. Виготовити в асептичних умовах (порошок для новонародженого); за термостійкості провести стерилізацію")
            }
        }
        context.appendSection(title: "Технологія", lines: techLines)

        var qualityLines: [String] = [
            "Дисперсність: ситовий аналіз або інший валідований метод.",
            "Відсутність агрегатів/грудок частинок."
        ]
        if requiresUniformityContent {
            qualityLines.append("Однорідність вмісту (Test B): обов'язково для активних <2 mg/дозу або <2% у дозі.")
            for check in contentChecksNonExcluded {
                qualityLines.append("\(check.name): \(format(check.perDoseMg)) mg/дозу; \(format(check.percentInDose))% у дозі.")
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
        context.appendSection(title: "Контроль якості", lines: qualityLines)

        var packagingLines: [String] = []
        if route == .external {
            packagingLines.append("Маркування: «Для зовнішнього застосування».")
        }
        if needsAsepticPowder {
            packagingLines.append("Маркування: «Стерильно».")
        }
        if isSingleDosePack {
            packagingLines.append("Фасування: однодозові пакети (саше/паперові капсули).")
            packagingLines.append("Для кожної дози вказати активну речовину та кількість.")
            packagingLines.append("Додатково: термін придатності, умови зберігання, спосіб застосування.")
        } else {
            packagingLines.append("Фасування: багатодозова тара.")
            packagingLines.append("Додати мірний пристрій у комплект.")
        }
        packagingLines.append(
            needsAirtight
                ? "Зберігати в герметично закритій тарі (airtight)."
                : "Зберігати в щільно закритій тарі."
        )
        context.appendSection(title: "Оформлення та зберігання", lines: packagingLines)
    }

    private func format(_ v: Double) -> String {
        if v == floor(v) { return String(Int(v)) }
        return String(format: "%.3f", v)
    }

    private func powderRoute(
        for draft: ExtempRecipeDraft,
        components: [PowderComponentResult],
        ingredientById: [UUID: IngredientDraft]
    ) -> PowderRoute {
        if isEffervescentPowder(components: components, ingredientById: ingredientById) {
            return .effervescent
        }
        let signa = draft.signa.lowercased()
        if signa.contains("зовніш") || signa.contains("наруж") || signa.contains("присып")
            || signa.contains("на кожу") || signa.contains("на шкіру") {
            return .external
        }
        return .oral
    }

    private func isLikelyActive(component: PowderComponentResult, ingredientById: [UUID: IngredientDraft]) -> Bool {
        if component.isActive { return true }
        if component.isSugarCarrier { return false }
        guard let ingredient = ingredientById[component.id] else { return true }
        let refType = (ingredient.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if refType == "solvent" || refType == "base" || refType == "excipient" || refType == "aux" {
            return false
        }
        return true
    }

    private func isVolatilePowder(component: PowderComponentResult, ingredientById: [UUID: IngredientDraft]) -> Bool {
        let hayFromComponent = component.name.lowercased()
        let hayFromIngredient: String = {
            guard let ingredient = ingredientById[component.id] else { return "" }
            return [
                ingredient.displayName,
                ingredient.refNameLatNom ?? "",
                ingredient.refInnKey ?? ""
            ]
            .joined(separator: " ")
            .lowercased()
        }()
        let hay = hayFromComponent + " " + hayFromIngredient
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
        components: [PowderComponentResult],
        ingredientById: [UUID: IngredientDraft]
    ) -> Bool {
        func hay(_ component: PowderComponentResult) -> String {
            let local = component.name.lowercased()
            let ing = ingredientById[component.id]
            let shared = [
                ing?.displayName ?? "",
                ing?.refNameLatNom ?? "",
                ing?.refInnKey ?? ""
            ]
            .joined(separator: " ")
            .lowercased()
            return local + " " + shared
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
        for component: PowderComponentResult,
        perDoseMassG: Double,
        ingredientById: [UUID: IngredientDraft]
    ) -> UniformityCheck {
        let perDoseMg = component.perDoseG * 1_000.0
        let percentInDose = perDoseMassG > 0 ? (component.perDoseG / perDoseMassG) * 100.0 : 0
        let hay = [
            component.name,
            ingredientById[component.id]?.displayName ?? "",
            ingredientById[component.id]?.refNameLatNom ?? "",
            ingredientById[component.id]?.refInnKey ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
        let isExcluded = hay.contains("multivit") || hay.contains("мікроелем") || hay.contains("microelement")
        let requiresContent = perDoseMg < 2.0 || percentInDose < 2.0
        return UniformityCheck(
            name: component.name,
            perDoseMg: perDoseMg,
            percentInDose: percentInDose,
            requiresContentUniformity: requiresContent,
            isExcluded: isExcluded
        )
    }

    private enum PowderRoute: String {
        case oral
        case external
        case effervescent
    }

    private struct UniformityCheck {
        let name: String
        let perDoseMg: Double
        let percentInDose: Double
        let requiresContentUniformity: Bool
        let isExcluded: Bool
    }
}
