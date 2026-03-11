import Foundation

struct InfusionDecoctionBlock: RxProcessingBlock {
    enum Mode {
        case infusion
        case decoction
    }

    static let infusionBlockId = "infusion"
    static let decoctionBlockId = "decoction"

    let mode: Mode

    var id: String {
        switch mode {
        case .infusion: return Self.infusionBlockId
        case .decoction: return Self.decoctionBlockId
        }
    }

    func apply(context: inout RxPipelineContext) {
        let isDecoction = (mode == .decoction)
        context.routeBranch = isDecoction ? "decoction" : "infusion"

        let draft = context.draft

        let herbalIngredients = draft.ingredients.filter {
            !$0.isQS && !$0.isAd &&
            $0.unit.rawValue == "g" &&
            $0.amountValue > 0 &&
            isHerbalIngredient($0)
        }

        guard !herbalIngredients.isEmpty else {
            context.addIssue(
                code: isDecoction ? "decoction.herbal.missing" : "infusion.herbal.missing",
                severity: .blocking,
                message: isDecoction
                    ? "Для відвару додайте рослинну сировину (herbal raw) у g"
                    : "Для настою додайте рослинну сировину (herbal raw) у g"
            )
            return
        }

        let formName = isDecoction ? "Відвар" : "Настій"
        let hasTanninRichRaw = herbalIngredients.contains(where: isTanninRichHerbalIngredient)

        context.addStep(TechStep(
            kind: .prep,
            title: "\(formName): технологія приготування",
            isCritical: true
        ))

        // MARK: 2️⃣ Расчёт воды по ratio

        var calcLines: [String] = []
        var totalRawWeight: Double = 0
        var theoreticalWater: Double = 0

        for ing in herbalIngredients {

            totalRawWeight += ing.amountValue

            let ratio = parseRatio(ing.refHerbalRatio) ?? defaultRatio(isDecoction: isDecoction)
            let water = ing.amountValue * ratio

            theoreticalWater += water

            calcLines.append("\(ing.displayName): \(format(ing.amountValue)) g × 1:\(format(ratio)) → \(format(water)) ml")
        }

        // MARK: 3️⃣ Учёт водопоглощения сырья

        let absorptionCoefficient = 1.5
        let absorbedWater = totalRawWeight * absorptionCoefficient

        calcLines.append("Поглинання води сировиною ≈ \(format(absorbedWater)) ml")

        let initialWater = theoreticalWater + absorbedWater
        calcLines.append("Води для заливання: \(format(initialWater)) ml")

        context.calculations["infusion_initial_water_ml"] = format(initialWater)

        // MARK: 4️⃣ Потери и доведение до объёма

        let targetVolume = theoreticalWater
        calcLines.append("Довести до об’єму: \(format(targetVolume)) ml")

        context.calculations["infusion_target_volume_ml"] = format(targetVolume)

        // MARK: 5️⃣ Теоретический выход экстракта

        let extractYield = estimateExtractYield(totalRawWeight: totalRawWeight,
                                                isDecoction: isDecoction)

        calcLines.append("Теоретичний вихід екстрактивних речовин ≈ \(format(extractYield)) g")

        context.appendSection(title: "Розрахунки", lines: calcLines)

        // MARK: 6️⃣ Технология

        var tech: [String] = []
        var step = 1

        tech.append("\(step). Подрібнену сировину помістити у фарфорову чашку"); step += 1
        tech.append("\(step). Залити \(format(initialWater)) ml очищеної води"); step += 1

        if isDecoction {
            tech.append("\(step). Нагрівати на водяній бані 30 хв"); step += 1
            if hasTanninRichRaw {
                tech.append("\(step). Для сировини з дубильними речовинами охолоджувати мінімально (до 3–5 хв) і відразу проціджувати гарячим"); step += 1
                context.addIssue(
                    code: "decoction.tannins.hotFiltration",
                    severity: .warning,
                    message: "Відвар із дубильновмісної сировини потрібно проціджувати відразу після бані, щоб уникнути пластівчастого осаду."
                )
            } else {
                tech.append("\(step). Охолодити 10 хв"); step += 1
            }
        } else {
            tech.append("\(step). Нагрівати 15 хв на водяній бані"); step += 1
            tech.append("\(step). Настоювати 45 хв"); step += 1
        }

        tech.append("\(step). Процідити через подвійний шар марлі та ватний тампон у воронці"); step += 1
        tech.append("\(step). Віджати сировину (marc)"); step += 1
        tech.append("\(step). Довести очищеною водою до \(format(targetVolume)) ml"); step += 1
        tech.append("\(step). Перемішати")

        context.appendSection(title: "Технологія", lines: tech)

        // MARK: 7️⃣ Контроль якості

        context.appendSection(title: "Контроль якості", lines: [
            "Прозора або злегка каламутна рідина",
            "Колір характерний для рослинної сировини",
            "Запах специфічний",
            "Відсутність механічних домішок"
        ])

        // MARK: 8️⃣ Условия хранения

        context.appendSection(title: "Зберігання", lines: [
            "У прохолодному місці (8–15°C)",
            "Термін придатності 2–3 доби",
            "Перед застосуванням збовтувати"
        ])

        // MARK: 9️⃣ Оформление

        context.appendSection(title: "Оформлення", lines: [
            "Тара: флакон для внутрішнього застосування",
            "Етикетка: «Внутрішньо»",
            "Вказати дату приготування"
        ])
    }

    private func isHerbalIngredient(_ ing: IngredientDraft) -> Bool {
        let refType = (ing.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if refType == "herbalraw" || refType == "herbalmix" { return true }
        if let ratio = ing.refHerbalRatio?.trimmingCharacters(in: .whitespacesAndNewlines), !ratio.isEmpty { return true }

        let hay = ((ing.refNameLatNom ?? ing.displayName) + " " + (ing.refInnKey ?? ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let herbalMarkers = [
            "herba", "folia", "flores", "flos", "radix", "rhizoma", "cortex", "fructus", "semina",
            "трава", "лист", "цвет", "корен", "кора", "плод", "насіння", "семена"
        ]
        return herbalMarkers.contains(where: { hay.contains($0) })
    }

    private func isTanninRichHerbalIngredient(_ ing: IngredientDraft) -> Bool {
        let hay = [
            ing.displayName,
            ing.refNameLatNom ?? "",
            ing.refInnKey ?? "",
            ing.refInteractionNotes ?? "",
            ing.refSolubility ?? ""
        ]
        .joined(separator: " ")
        .lowercased()

        return hay.contains("tannin")
            || hay.contains("танин")
            || hay.contains("дубиль")
            || hay.contains("querc")
            || hay.contains("cort")
            || hay.contains("кора дуб")
    }

    // MARK: - Ratio

    private func parseRatio(_ text: String?) -> Double? {
        guard let text = text else { return nil }
        let cleaned = text.replacingOccurrences(of: " ", with: "")
        let parts = cleaned.split(separator: ":")
        guard parts.count == 2,
              let value = Double(parts[1])
        else { return nil }
        return value
    }

    private func defaultRatio(isDecoction: Bool) -> Double {
        return isDecoction ? 10 : 10
    }

    // MARK: - Экстрактивность

    private func estimateExtractYield(totalRawWeight: Double,
                                      isDecoction: Bool) -> Double {

        let extractPercent = isDecoction ? 0.15 : 0.10
        return totalRawWeight * extractPercent
    }

    private func format(_ v: Double) -> String {
        if v == floor(v) { return String(Int(v)) }
        return String(format: "%.1f", v)
    }
}
