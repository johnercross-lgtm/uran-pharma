import Foundation

struct SuppositoriesBlock: RxProcessingBlock {
    static let blockId = "suppositories"
    let id = blockId

    func apply(context: inout RxPipelineContext) {
        context.routeBranch = "suppositories"

        let result = SuppositoriesCalculator.calculate(draft: context.draft)

        if result.hasNegativeBase {
            context.addIssue(code: "supp.base.negative", severity: .blocking, message: "Неможливо розрахувати основу: активні речовини перевищують масу форми")
        }

        if result.fallbackCount > 0 {
            context.addIssue(code: "supp.efactor.fallback", severity: .warning, message: "Для \(result.fallbackCount) компонентів використано E-фактор за замовчуванням")
        }

        let hasBase = result.baseIngredientName != nil
        if !hasBase {
            context.addIssue(code: "supp.base.missing", severity: .warning, message: "Не вказана основа (q.s./ad) для супозиторіїв")
        }

        context.calculations["supp_n"] = String(result.n)
        context.calculations["supp_mold_mass_g"] = format(result.moldMassPerSuppG)
        context.calculations["supp_total_target_g"] = format(result.targetTotalG)
        context.calculations["supp_actives_g"] = format(result.activesTotalG)
        context.calculations["supp_base_displacement_g"] = format(result.displacedBaseTotalG)
        context.calculations["supp_base_g"] = format(max(0, result.baseNeededG))

        context.addStep(TechStep(kind: .prep, title: "Підготувати форму для супозиторіїв і основу", isCritical: true))
        context.addStep(TechStep(kind: .mixing, title: "Розплавити/підготувати основу, ввести активні речовини"))
        context.addStep(TechStep(kind: .packaging, title: "Розлити/сформувати супозиторії та упакувати"))

        var calcLines: [String] = [
            "N = \(result.n)",
            "Маса 1 супозиторія (форма): \(format(result.moldMassPerSuppG)) g",
            "Цільова сумарна маса: \(format(result.targetTotalG)) g",
            "Активні речовини: \(format(result.activesTotalG)) g",
            "Заміщення основи: \(format(result.displacedBaseTotalG)) g",
            "Основа: \(format(result.targetTotalG)) − \(format(result.displacedBaseTotalG)) = \(format(max(0, result.baseNeededG))) g"
        ]
        if result.usedDefaultMoldMass {
            calcLines.append("⚠ Маса форми не вказана — використано значення за замовчуванням 3 g")
        }
        for a in result.actives {
            let suffix = a.usedFallback ? " (E fallback)" : ""
            calcLines.append("• \(a.name): \(format(a.totalG)) g × E(\(format(a.eFactor))) = \(format(a.displacedBaseG)) g\(suffix)")
        }
        if let baseName = result.baseIngredientName, result.baseNeededG >= 0 {
            calcLines.append("Базовий компонент: \(baseName) \(format(result.baseNeededG)) g")
        }

        let perSupp = result.targetTotalG / Double(result.n)
        let p = 5.0
        let lo = perSupp * (1 - p / 100)
        let hi = perSupp * (1 + p / 100)
        calcLines.append("Допустиме відхилення: ±\(format(p))% (\(format(lo))–\(format(hi)) g на 1 супозиторій)")

        context.appendSection(title: "Розрахунки", lines: calcLines)

        var techLines: [String] = [
            "Основу плавити на водяній бані без перегрівання (орієнтовно 40-60°C залежно від типу основи).",
            "Активні речовини вводити за розчинністю: розчинні — через розчинення, нерозчинні — через тонке диспергування.",
            "Перемішувати масу обережно, уникати аерації; розлити у підготовлені форми.",
            "Охолодити до повного тверднення, вилучити супозиторії та перевірити однорідність і цілісність."
        ]
        if hasVolatileOrThermolabileIngredient(context.draft.ingredients) {
            techLines.insert("Леткі/термолабільні компоненти вводити у частково охолоджену масу (близько 40-45°C).", at: 2)
        }
        context.appendSection(title: "Технологія супозиторіїв", lines: techLines)

        context.appendSection(
            title: "Упаковка",
            lines: [
                "Упаковка: контурна чарункова упаковка / фольга / парафінований папір.",
                "Маркування: за способом застосування.",
                "Зберігати у прохолодному місці."
            ]
        )
    }

    private func format(_ v: Double) -> String {
        if v == floor(v) { return String(Int(v)) }
        return String(format: "%.3f", v)
    }

    private func hasVolatileOrThermolabileIngredient(_ ingredients: [IngredientDraft]) -> Bool {
        ingredients.contains(where: isVolatileOrThermolabile)
    }

    private func isVolatileOrThermolabile(_ ingredient: IngredientDraft) -> Bool {
        let hay = normalizedHay(ingredient)
        return hay.contains("menthol")
            || hay.contains("camphor")
            || hay.contains("eucalypt")
            || hay.contains("thymi")
            || hay.contains("anisi")
            || hay.contains("olei")
            || hay.contains("oleum")
            || hay.contains("ефірн")
            || hay.contains("ментол")
            || hay.contains("камфор")
    }

    private func normalizedHay(_ ingredient: IngredientDraft) -> String {
        let a = (ingredient.refNameLatNom ?? ingredient.displayName).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = (ingredient.refInnKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let c = ingredient.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [a, b, c].joined(separator: " ")
    }
}
