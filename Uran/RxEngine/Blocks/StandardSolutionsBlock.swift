import Foundation

struct StandardSolutionsBlock: RxProcessingBlock {
    static let blockId = "standard_solutions"
    let id = blockId

    func apply(context: inout RxPipelineContext) {
        let repo = StandardSolutionsRepository.shared
        let calc = StandardSolutionCalculator()
        let signaLower = context.draft.signa.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasDemyanovich = signaLower.contains("демья")
            || signaLower.contains("дем’ян")
            || signaLower.contains("дем'ян")
            || signaLower.contains("demjan")
            || signaLower.contains("demian")
            || signaLower.contains("demyan")
        let hasNumber2 = signaLower.range(
            of: "(№\\s*2|#\\s*2|\\bno\\.?\\s*2\\b|\\bрозчин\\s*№\\s*2\\b|\\bраствор\\s*№\\s*2\\b)",
            options: .regularExpression
        ) != nil
        let signaIsDemyanovich2 = hasDemyanovich && hasNumber2
        let isDemyanovichMethod = context.draft.standardSolutionSpecialCase == .demyanovich2
            || signaIsDemyanovich2
            || hasDemyanovich

        var lines: [String] = []
        var tech: [String] = []
        let selectedSource = context.draft.selectedStandardSolution(repo: repo)
        let selectedSolutionIngredientId = context.draft.ingredients.first(where: {
            !$0.isQS && !$0.isAd && $0.presentationKind == .solution
        })?.id

        for ing in context.draft.ingredients where !ing.isQS && !ing.isAd {
            let explicitPercent: Double? = {
                if let p = context.draft.solutionDisplayPercent(for: ing) { return p }
                return parsePercent(from: ing.refNameLatNom ?? ing.displayName)
            }()
            let matched: (solution: StandardSolution, kind: DilutionInputNameKind)? = {
                if let selectedSource, selectedSolutionIngredientId == ing.id {
                    return (selectedSource, context.draft.standardSolutionInputNameKind ?? .chemicalName)
                }
                return repo.matchIngredient(ing, parsedPercent: explicitPercent)
            }()
            guard let matched else { continue }

            let targetPercent: Double = {
                if let p = explicitPercent { return p }
                return matched.solution.avgPercent ?? calc.defaultPercentIfMissing(for: matched.solution.id) ?? 0
            }()
            guard targetPercent > 0 else { continue }

            let volume: Double = {
                if let solutionVolume = context.draft.solutionVolumeMl(for: ing), solutionVolume > 0 {
                    return solutionVolume
                }
                if ing.unit.rawValue == "ml", ing.amountValue > 0 { return ing.amountValue }
                return context.facts.inferredLiquidTargetMl ?? 0
            }()
            guard volume > 0 else {
                lines.append("⚠ \(displayName(matched.solution, kind: matched.kind)): для розрахунку потрібен об’єм у ml")
                continue
            }

            let manualStock = max(0, context.draft.standardSolutionManualStockMl ?? 0)
            let manualWater = max(0, context.draft.standardSolutionManualWaterMl ?? 0)
            let hasManualMix = context.draft.hasManualStandardSolutionMix && selectedSolutionIngredientId == ing.id
            if hasManualMix {
                let dispName = displayName(matched.solution, kind: matched.kind)
                lines.append("\(dispName) \(format(targetPercent))%: ручний режим \(format(manualStock)) ml + Aqua purificata \(format(manualWater)) ml")
                if abs((manualStock + manualWater) - volume) > 0.0001 {
                    lines.append("⚠ Ручна суміш = \(format(manualStock + manualWater)) ml, рецепт = \(format(volume)) ml")
                }
                tech.append("У підставку: Aqua purificata \(format(manualWater)) ml")
                tech.append("Додати: \(dispName) \(format(manualStock)) ml")
                tech.append("Перемішати та оформити")
                let note = context.draft.standardSolutionManualNote.trimmingCharacters(in: .whitespacesAndNewlines)
                if !note.isEmpty {
                    tech.append("Примітка: \(note)")
                }
                continue
            }

            let explicitWaterIngredient = context.draft.ingredients.first(where: {
                !$0.isQS
                    && !$0.isAd
                    && $0.id != ing.id
                    && PurifiedWaterHeuristics.isPurifiedWater($0)
                    && isMlUnit($0.unit.rawValue)
                    && $0.amountValue > 0
            })
            if matched.solution.id == .hydrochloricAcidDiluted,
               explicitPercent == nil,
               isMlUnit(ing.unit.rawValue),
               ing.amountValue > 0,
               let waterIngredient = explicitWaterIngredient {
                let stockAmount = ing.amountValue
                let waterAmount = waterIngredient.amountValue
                let totalVolume = stockAmount + waterAmount
                lines.append("Acidum hydrochloricum dilutum 8,3% \(format(stockAmount)) ml + Aqua purificata \(format(waterAmount)) ml (V=\(format(totalVolume)) ml)")
                tech.append("У підставку: Aqua purificata \(format(waterAmount)) ml")
                tech.append("Додати: Acidum hydrochloricum dilutum 8,3% \(format(stockAmount)) ml")
                tech.append("Збовтати, процідити через ватний тампон, оформити")
                continue
            }

            let shouldDispenseAsIs: Bool = {
                guard let stock = matched.solution.avgPercent else { return false }
                if explicitPercent == nil { return true }
                return abs(targetPercent - stock) < 0.0001
            }()

            if shouldDispenseAsIs {
                lines.append("\(displayName(matched.solution, kind: matched.kind)) \(format(targetPercent))% — \(format(volume)) ml")
                if matched.solution.id == .hydrogenPeroxideDiluted, abs(targetPercent - 3.0) < 0.0001 {
                    tech.append("Відпустити готовий аптечний розчин Hydrogenii peroxydi 3%")
                }
                continue
            }

            do {
                let calcKind: DilutionInputNameKind = {
                    if matched.kind == .aliasName, matched.solution.unitWhenAliased {
                        return .aliasName
                    }
                    return .chemicalName
                }()

                let result = try calc.dilute(stock: matched.solution, finalVolume: volume, targetPercent: targetPercent, inputNameKind: calcKind)
                let dispName = displayName(matched.solution, kind: matched.kind)
                let stockName = stockDisplayName(matched.solution, inputNameKind: calcKind)
                let note = context.draft.standardSolutionManualNote.trimmingCharacters(in: .whitespacesAndNewlines)
                if isDemyanovichMethod,
                   matched.solution.id == .hydrochloricAcidDiluted,
                   abs(targetPercent - 6.0) < 0.0001,
                   abs(volume - 200.0) < 0.0001 {
                    let concentratedEquivalent = volume * targetPercent / 100.0
                    let dilutedAmount = volume * targetPercent * 3.0 / 100.0
                    let waterAmount = volume - dilutedAmount
                    lines.append("Фармакопейний еквівалент для розчину №2 за Дем'яновичем: кислота 24,8–25,2% \(format(concentratedEquivalent)) ml + Aqua purificata ad \(format(volume)) ml")
                    lines.append("Фактичне виготовлення з Acidum hydrochloricum dilutum 8,3%: \(format(dilutedAmount)) ml + Aqua purificata \(format(waterAmount)) ml")
                    tech.append("У підставку: Aqua purificata \(format(waterAmount)) ml")
                    tech.append("Додати: \(stockName) \(format(dilutedAmount)) ml")
                    tech.append("Кислоту додавати у воду")
                    tech.append("Збовтати, процідити у флакон і оформити (розчин №2 за Дем'яновичем)")
                    if !note.isEmpty, selectedSolutionIngredientId == ing.id {
                        tech.append("Примітка: \(note)")
                    }
                    continue
                }
                lines.append("\(dispName) \(format(targetPercent))%: \(format(result.stockAmount)) ml + Aqua purificata ad \(format(volume)) ml")

                if matched.solution.id == .ammoniaSolution, abs(targetPercent - 1.0) < 0.0001, abs(volume - 300.0) < 0.0001 {
                    tech.append("У підставку: Aqua purificata \(format(result.waterAmount)) ml")
                    tech.append("Додати: \(stockName) \(format(result.stockAmount)) ml")
                    tech.append("Перемішати, процідити через ватний тампон, оформити")
                    if !note.isEmpty, selectedSolutionIngredientId == ing.id {
                        tech.append("Примітка: \(note)")
                    }
                    continue
                }
                if matched.solution.id == .hydrochloricAcidDiluted, abs(targetPercent - 2.0) < 0.0001, abs(volume - 200.0) < 0.0001 {
                    tech.append("У підставку: Aqua purificata \(format(result.waterAmount)) ml")
                    tech.append("Додати: \(stockName) \(format(result.stockAmount)) ml")
                    tech.append("Збовтати, за потреби — процідити у флакон і оформити")
                    if !note.isEmpty, selectedSolutionIngredientId == ing.id {
                        tech.append("Примітка: \(note)")
                    }
                    continue
                }
                if matched.solution.id == .hydrogenPeroxideConcentrated, abs(targetPercent - 6.0) < 0.0001, abs(volume - 3000.0) < 0.0001 {
                    tech.append("Відміряти: \(stockName) \(format(result.stockAmount)) ml")
                    tech.append("Aqua purificata \(format(result.waterAmount)) ml")
                    tech.append("Перемішати та оформити")
                    tech.append("⚠ Perhydrolum: концентрат, уникати контакту зі шкірою/очима")
                    if !note.isEmpty, selectedSolutionIngredientId == ing.id {
                        tech.append("Примітка: \(note)")
                    }
                    continue
                }
                if matched.solution.id == .hydrogenPeroxideConcentrated, abs(targetPercent - 5.0) < 0.0001, abs(volume - 100.0) < 0.0001 {
                    tech.append("Відміряти: \(stockName) \(format(result.stockAmount)) ml")
                    tech.append("Aqua purificata \(format(result.waterAmount)) ml")
                    tech.append("Перемішати та оформити")
                    tech.append("⚠ Perhydrolum: концентрат, уникати контакту зі шкірою/очима")
                    if !note.isEmpty, selectedSolutionIngredientId == ing.id {
                        tech.append("Примітка: \(note)")
                    }
                    continue
                }
                tech.append("Розвести \(dispName) до \(format(targetPercent))% та довести до \(format(volume)) ml")
                if matched.solution.id == .hydrogenPeroxideConcentrated {
                    tech.append("⚠ Perhydrolum: концентрат, уникати контакту зі шкірою/очима")
                }
                if !note.isEmpty, selectedSolutionIngredientId == ing.id {
                    tech.append("Примітка: \(note)")
                }
            } catch {
                lines.append("⚠ \(displayName(matched.solution, kind: matched.kind)): помилка розрахунку розведення")
            }
        }

        if !lines.isEmpty {
            context.appendSection(title: "Розрахунки (ГФ: стандартні розчини)", lines: lines)
            context.addStep(TechStep(kind: .mixing, title: "Підготувати розведення стандартного розчину", isCritical: true))
            if !tech.isEmpty {
                context.appendSection(title: "Технологія", lines: tech)
            }
        }
    }

    private func normalizedHay(_ ing: IngredientDraft) -> String {
        let a = (ing.refNameLatNom ?? ing.displayName).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = (ing.refInnKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return a + " " + b
    }

    private func parsePercent(from text: String) -> Double? {
        let s = text.replacingOccurrences(of: ",", with: ".")
        guard let r = s.range(of: "(\\d{1,2}(?:\\.\\d+)?)\\s*%", options: .regularExpression) else { return nil }
        let m = String(s[r]).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(m)
    }

    private func displayName(_ solution: StandardSolution, kind: DilutionInputNameKind) -> String {
        if kind == .aliasName, let alias = solution.alias { return alias }
        return solution.chemicalName
    }

    private func stockDisplayName(_ solution: StandardSolution, inputNameKind: DilutionInputNameKind) -> String {
        let base = displayName(solution, kind: inputNameKind)
        guard let percent = stockPercent(for: solution, inputNameKind: inputNameKind) else { return base }
        return "\(base) \(ExtempViewFormatter.formatPercentValue(percent))%"
    }

    private func stockPercent(for solution: StandardSolution, inputNameKind: DilutionInputNameKind) -> Double? {
        switch inputNameKind {
        case .aliasName:
            return 100.0
        case .chemicalName:
            if let avg = solution.avgPercent {
                return avg
            }
            if let min = solution.gfPercentRange?.min, solution.gfPercentRange?.max == nil {
                return min
            }
            return nil
        }
    }

    private func isMlUnit(_ raw: String) -> Bool {
        let unit = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return unit == "ml" || unit == "мл"
    }

    private func format(_ v: Double) -> String {
        if v == floor(v) { return String(Int(v)) }
        return String(format: "%.3f", v)
    }
}
