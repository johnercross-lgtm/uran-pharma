import Foundation

enum LivingDeathEasterEgg {
    private struct IngredientMarker {
        let key: String
        let markers: [String]
    }

    private static let asphodel = IngredientMarker(
        key: "asphodel",
        markers: ["златоцв", "асфодел", "asphodel", "asfodel"]
    )
    private static let wormwood = IngredientMarker(
        key: "wormwood",
        markers: ["полин", "полын", "absinth", "wormwood", "абсинт"]
    )
    private static let sopophor = IngredientMarker(
        key: "sopophor",
        markers: ["софофор", "сопофор", "sopophor"]
    )
    private static let waterMarkers: [String] = ["aqua purificata", "aqua", "вода", "water", "purificata"]

    static func searchMatches(query: String) -> [ExtempSubstance] {
        let normalized = normalize(query)
        guard !normalized.isEmpty else { return [] }

        var out: [ExtempSubstance] = []
        if matchesMarker(asphodel, in: normalized) {
            out.append(asphodelSubstance)
        }
        if matchesMarker(wormwood, in: normalized) {
            out.append(wormwoodTincture)
        }
        if matchesMarker(sopophor, in: normalized) {
            out.append(sopophorJuice)
        }
        return out
    }

    static func mergeSearchResults(hidden: [ExtempSubstance], db: [ExtempSubstance], limit: Int) -> [ExtempSubstance] {
        var seen: Set<String> = []
        var merged: [ExtempSubstance] = []

        for item in hidden + db {
            let key = normalize([item.innKey, item.nameLatNom, item.nameRu].joined(separator: " "))
            guard !key.isEmpty else { continue }
            if seen.insert(key).inserted {
                merged.append(item)
            }
            if merged.count >= limit {
                break
            }
        }

        return merged
    }

    static func isActive(draft: ExtempRecipeDraft) -> Bool {
        let relevantIngredients = draft.ingredients.filter { !$0.isQS && !$0.isAd }
        guard relevantIngredients.count >= 3 else { return false }

        let haystacks = relevantIngredients.map { ingredient in
            ingredientHaystack(ingredient)
        }
        guard haystacks.contains(where: { matchesMarker(asphodel, in: $0) }) else { return false }
        guard haystacks.contains(where: { matchesMarker(wormwood, in: $0) }) else { return false }
        guard haystacks.contains(where: { matchesMarker(sopophor, in: $0) }) else { return false }

        return haystacks.allSatisfy { haystack in
            matchesMarker(asphodel, in: haystack)
                || matchesMarker(wormwood, in: haystack)
                || matchesMarker(sopophor, in: haystack)
                || waterMarkers.contains(where: { haystack.contains($0) })
        }
    }

    static func expertiseTitle() -> String {
        "Напій Живої Смерті"
    }

    static func expertiseReasons() -> [String] {
        [
            "У складі одночасно є златоцвітник, полин і софофор",
            "Комбінація збігається з легендарним рецептом Снегга",
            "ППК буде оформлено як спеціальний магістральний сценарій"
        ]
    }

    static func ppkText(draft: ExtempRecipeDraft, issueDate: Date = Date()) -> String {
        let patient = nonEmpty(draft.patientName) ?? "Поттер Г."
        let rxNumber = nonEmpty(draft.rxNumber) ?? "9¾"
        let dateText = formatDate(issueDate)

        let lines: [String] = [
            "ППК",
            "Зворотний бік (до виготовлення):",
            "Вихідні дані:",
            "Форма: Складний колоїдний розчин (ВМС/Настоянка)",
            "V_total: 100 ml",
            "• Pulvis Radicis Asphodeli — 5 g",
            "• Tinctura Absinthii — 10 ml",
            "• Succus Sopophori — 5 ml",
            "• Aqua purificata — ad 100 ml",
            "Математичне обґрунтування:",
            "V_target = 100 ml",
            "Σ(рідини, крім ad) = 15 ml (настоянка + сік)",
            "Σ(тверді) = 5 g",
            "5 / 100 × 100% = 5%",
            "Гілка: ≥ 3% (з урахуванням КУО)",
            "Aqua purificata = 100 - 15 - (5 × 0,6) ≈ 82 ml",
            "Технологічне обґрунтування:",
            "Златоцвітник потребує тривалого набухання у гарячій воді.",
            "Спиртова настоянка полину додається краплями після утворення рівного колоїду.",
            "Сік софофора вноситься наприкінці: контрольна ознака якості — перехід від рожевого до абсолютно прозорого розчину.",
            "Лицьовий бік (після виготовлення):",
            "Шапка:",
            "Дата: \(dateText)",
            "№ рецепта: \(rxNumber)",
            "Пацієнт: \(patient)",
            "Порядок внесення (TechnologyOrder):",
            "1. Aqua purificata 82 ml — підігріти до появи перших бульбашок.",
            "2. Pulvis Radicis Asphodeli 5 g — вносити при інтенсивному перемішуванні за годинниковою стрілкою.",
            "3. Tinctura Absinthii 10 ml — додати повільно краплями.",
            "4. Succus Sopophori 5 ml — додати після 7-го оберту проти годинникової стрілки.",
            "Ключові операції:",
            "1. Подрібнити корінь златоцвітника до стану дрібного порошку.",
            "2. Розчинити порошок у гарячій воді та дочекатися набухання.",
            "3. Фільтрацію не проводити: має утворитися ідеальний колоїд.",
            "4. Додати настоянку полину до появи насичено-пурпурового кольору.",
            "5. Додати сік софофора для миттєвої стабілізації та прозорості.",
            "6. Розлити у скляний флакон з притертою пробкою.",
            "Контроль:",
            "Фізичний контроль:",
            "Колір: абсолютно прозорий, як вода.",
            "Запах: специфічний, гіркий.",
            "Осад: відсутній після 12 обертів.",
            "Оформлення та зберігання:",
            "Етикетка: Внутрішнє. ОТРУТА (Venenum).",
            "Зберігати в підземеллях Хогвартсу.",
            "Термін придатності: вічний, якщо не розбити флакон.",
            "Зауваження:",
            "• [warning] Потрібен підпис Майстра Зіллеваріння (С. Снегг).",
            "• [warning] Смертельно небезпечно: використовувати тільки за наявності Безоару під рукою."
        ]

        return lines.joined(separator: "\n")
    }

    private static var asphodelSubstance: ExtempSubstance {
        ExtempSubstance(
            id: -910001,
            innKey: "asphodelus",
            categoryId: 0,
            nameRu: "Корінь златоцвітника",
            nameLatNom: "Radix Asphodeli",
            nameLatGen: "Radicis Asphodeli",
            role: "Актив",
            refType: "act",
            isColoring: false,
            vrdG: nil,
            vsdG: nil,
            pedsVrdG: nil,
            pedsRdG: nil,
            vrdChild0_1: nil,
            vrdChild1_6: nil,
            vrdChild7_14: nil,
            kuoMlPerG: 0.6,
            kvGPer100G: nil,
            gttsPerMl: nil,
            eFactor: nil,
            density: nil,
            solubility: "colloid",
            storage: nil,
            interactionNotes: nil,
            ointmentEntryType: nil,
            ointmentSolventInnKey: nil,
            ointmentRatioSoluteToSolvent: nil,
            ointmentNote: nil,
            needsTrituration: true,
            listA: false,
            listB: false,
            isNarcotic: false,
            pharmActivity: nil,
            physicalState: nil,
            prepMethod: nil,
            herbalRatio: nil,
            waterTempC: nil,
            heatBathMin: nil,
            standMin: nil,
            coolMin: nil,
            strain: false,
            pressMarc: false,
            bringToVolume: false,
            shelfLifeHours: nil,
            storagePrepared: nil,
            extractionSolvent: nil,
            tinctureRatio: nil,
            macerationDays: nil,
            shakeDaily: false,
            filter: false,
            storageTincture: nil,
            extractType: nil,
            extractSolvent: nil,
            extractRatio: nil,
            bufferPH: nil,
            bufferMolarity: nil,
            solventType: nil,
            sterile: false,
            dissolutionType: nil
        )
    }

    private static var wormwoodTincture: ExtempSubstance {
        ExtempSubstance(
            id: -910002,
            innKey: "absinthium",
            categoryId: 0,
            nameRu: "Настоянка полину",
            nameLatNom: "Tinctura Absinthii",
            nameLatGen: "Tincturae Absinthii",
            role: "Solvent",
            refType: "solvent",
            isColoring: false,
            vrdG: nil,
            vsdG: nil,
            pedsVrdG: nil,
            pedsRdG: nil,
            vrdChild0_1: nil,
            vrdChild1_6: nil,
            vrdChild7_14: nil,
            kuoMlPerG: nil,
            kvGPer100G: nil,
            gttsPerMl: 30,
            eFactor: nil,
            density: nil,
            solubility: nil,
            storage: nil,
            interactionNotes: nil,
            ointmentEntryType: nil,
            ointmentSolventInnKey: nil,
            ointmentRatioSoluteToSolvent: nil,
            ointmentNote: nil,
            needsTrituration: false,
            listA: false,
            listB: false,
            isNarcotic: false,
            pharmActivity: nil,
            physicalState: nil,
            prepMethod: nil,
            herbalRatio: nil,
            waterTempC: nil,
            heatBathMin: nil,
            standMin: nil,
            coolMin: nil,
            strain: false,
            pressMarc: false,
            bringToVolume: false,
            shelfLifeHours: nil,
            storagePrepared: nil,
            extractionSolvent: "Spiritus aethylicus",
            tinctureRatio: nil,
            macerationDays: nil,
            shakeDaily: false,
            filter: false,
            storageTincture: nil,
            extractType: nil,
            extractSolvent: nil,
            extractRatio: nil,
            bufferPH: nil,
            bufferMolarity: nil,
            solventType: "alcohol",
            sterile: false,
            dissolutionType: nil
        )
    }

    private static var sopophorJuice: ExtempSubstance {
        ExtempSubstance(
            id: -910003,
            innKey: "sopophor",
            categoryId: 0,
            nameRu: "Сік софофора",
            nameLatNom: "Succus Sopophori",
            nameLatGen: "Succi Sopophori",
            role: "Excipient",
            refType: "solvent",
            isColoring: false,
            vrdG: nil,
            vsdG: nil,
            pedsVrdG: nil,
            pedsRdG: nil,
            vrdChild0_1: nil,
            vrdChild1_6: nil,
            vrdChild7_14: nil,
            kuoMlPerG: nil,
            kvGPer100G: nil,
            gttsPerMl: 20,
            eFactor: nil,
            density: nil,
            solubility: nil,
            storage: nil,
            interactionNotes: nil,
            ointmentEntryType: nil,
            ointmentSolventInnKey: nil,
            ointmentRatioSoluteToSolvent: nil,
            ointmentNote: nil,
            needsTrituration: false,
            listA: false,
            listB: false,
            isNarcotic: false,
            pharmActivity: nil,
            physicalState: nil,
            prepMethod: nil,
            herbalRatio: nil,
            waterTempC: nil,
            heatBathMin: nil,
            standMin: nil,
            coolMin: nil,
            strain: false,
            pressMarc: false,
            bringToVolume: false,
            shelfLifeHours: nil,
            storagePrepared: nil,
            extractionSolvent: nil,
            tinctureRatio: nil,
            macerationDays: nil,
            shakeDaily: false,
            filter: false,
            storageTincture: nil,
            extractType: nil,
            extractSolvent: nil,
            extractRatio: nil,
            bufferPH: nil,
            bufferMolarity: nil,
            solventType: "juice",
            sterile: false,
            dissolutionType: nil
        )
    }

    private static func ingredientHaystack(_ ingredient: IngredientDraft) -> String {
        normalize(
            [
                ingredient.displayName,
                ingredient.refInnKey ?? "",
                ingredient.refNameLatNom ?? "",
                ingredient.refNameLatGen ?? ""
            ].joined(separator: " ")
        )
    }

    private static func matchesMarker(_ marker: IngredientMarker, in haystack: String) -> Bool {
        marker.markers.contains(where: { haystack.contains($0) })
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "uk_UA"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "uk_UA")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }
}
