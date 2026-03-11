import Foundation

enum IngredientUnit: String, Sendable {
    case g
    case ml
}

enum SolubilityInGlycerin: String, Sendable {
    case soluble
    case slightlySoluble
    case insoluble
}

struct Ingredient: Sendable {
    let id: String
    let name: String
    let amount: Double
    let unit: IngredientUnit
    let isListA: Bool
    let isCaustic: Bool
    let solubilityInGlycerin: SolubilityInGlycerin
    let isCrystalline: Bool
    let densityGPerMl: Double?
}

enum SolventUnit: String, Sendable {
    case g
    case ml
}

struct Solvent: Sendable {
    let id: String
    let name: String
    let amount: Double
    let unit: SolventUnit
    let densityGPerMl: Double?
}

struct PhenolPPCResult: Sendable {
    let faceSideLines: [String]
    let technologyOrder: [String]
    let warnings: [String]
    let labels: [String]
    let requiresSecondPharmacistSignature: Bool
    let isVrdCheckEnabled: Bool
}

enum PhenolLogicError: Error, LocalizedError {
    case invalidSolventAmount
    case ingredientMassUnavailable(name: String)
    case phenolMissing

    var errorDescription: String? {
        switch self {
        case .invalidSolventAmount:
            return "Невозможно рассчитать массу растворителя."
        case .ingredientMassUnavailable(let name):
            return "Невозможно перевести \(name) в граммы (нет плотности)."
        case .phenolMissing:
            return "В составе не найден Phenolum purum."
        }
    }
}

final class PhenolLogicController {
    private let glycerinDensity = 1.25
    private let highConcentrationThresholdPercent = 5.0

    func calculatePPC(
        ingredients: [Ingredient],
        solvent: Solvent,
        signa: String = ""
    ) throws -> PhenolPPCResult {
        guard let phenol = ingredients.first(where: isPhenol) else {
            throw PhenolLogicError.phenolMissing
        }

        let solventMass = try normalizedSolventMass(solvent)
        let ingredientMasses = try normalizedIngredientMasses(ingredients)
        guard let phenolMass = ingredientMasses[phenol.id] else {
            throw PhenolLogicError.ingredientMassUnavailable(name: phenol.name)
        }

        let totalMass = solventMass + ingredientMasses.values.reduce(0, +)
        let phenolConcentrationPercent = totalMass > 0 ? (phenolMass / totalMass) * 100 : 0

        var warnings: [String] = []
        if phenolConcentrationPercent > highConcentrationThresholdPercent {
            warnings.append("ВЫСОКАЯ КОНЦЕНТРАЦИЯ ФЕНОЛА, ПРОВЕРЬТЕ ДОЗИРОВКУ.")
        }
        if phenol.isCaustic {
            warnings.append("ОПАСНО: ФЕНОЛ ВЫЗЫВАЕТ ХИМИЧЕСКИЕ ОЖОГИ КОЖИ И СЛИЗИСТЫХ.")
        }

        let isExternalSmearing = isSmearingSigna(signa)
        let vrdEnabled = !isExternalSmearing

        let secondSignatureRequired = phenol.isListA
        let labels = phenol.isListA
            ? ["ЯД (POISON)", "ОФОРМИТЬ СИГНАТУРОЙ (РОЗОВАЯ ПОЛОСА)", "ОПЕЧАТАТЬ СУРГУЧОМ"]
            : []

        var faceSide = [
            "Phenolum purum: \(formatMass(phenolMass)) g",
            "Glycerinum: \(formatMass(solventMass)) g",
            "M_total: \(formatMass(totalMass)) g",
            "Концентрация Phenolum purum: \(formatPercent(phenolConcentrationPercent))%"
        ]
        if secondSignatureRequired {
            faceSide.append("Двойной контроль (Список А): подпись второго фармацевта ______")
        }

        var technologyOrder: [String] = []
        technologyOrder.append("Осторожно! Фенол вызывает химические ожоги. Работать строго в перчатках в вытяжной шкафу.")
        technologyOrder.append("Таровать сухой флакон оранжевого (темного) стекла.")
        technologyOrder.append("Взвесить фенол на отдельных весах для ядовитых веществ во флакон отпуска.")
        if phenol.isCrystalline {
            technologyOrder.append("Растереть кристаллы в ступці с 2–3 каплями глицерина.")
        }
        technologyOrder.append("Добавить расчетную массу глицерина и перемешать.")
        technologyOrder.append("Поместить флакон на водяную баню (t = 40–50°C) до полного растворения.")
        technologyOrder.append("Хранить в защищенном от света месте (фенол розовеет на свету).")

        return PhenolPPCResult(
            faceSideLines: faceSide,
            technologyOrder: technologyOrder,
            warnings: warnings.map { $0.uppercased() },
            labels: labels,
            requiresSecondPharmacistSignature: secondSignatureRequired,
            isVrdCheckEnabled: vrdEnabled
        )
    }

    private func isPhenol(_ ingredient: Ingredient) -> Bool {
        let hay = ingredient.name.lowercased()
        return hay.contains("phenol")
            || hay.contains("phenolum")
            || hay.contains("acidum carbolicum")
            || hay.contains("карбол")
            || hay.contains("фенол")
    }

    private func normalizedSolventMass(_ solvent: Solvent) throws -> Double {
        guard solvent.amount > 0 else { throw PhenolLogicError.invalidSolventAmount }
        if solvent.unit == .g { return solvent.amount }

        let density: Double
        if solvent.name.lowercased().contains("glycer")
            || solvent.name.lowercased().contains("глиц")
            || solvent.name.lowercased().contains("гліц")
        {
            density = glycerinDensity
        } else if let customDensity = solvent.densityGPerMl, customDensity > 0 {
            density = customDensity
        } else {
            throw PhenolLogicError.invalidSolventAmount
        }
        return solvent.amount * density
    }

    private func normalizedIngredientMasses(_ ingredients: [Ingredient]) throws -> [String: Double] {
        var out: [String: Double] = [:]
        for ingredient in ingredients {
            if ingredient.amount <= 0 { continue }
            if ingredient.unit == .g {
                out[ingredient.id] = ingredient.amount
                continue
            }
            guard let density = ingredient.densityGPerMl, density > 0 else {
                throw PhenolLogicError.ingredientMassUnavailable(name: ingredient.name)
            }
            out[ingredient.id] = ingredient.amount * density
        }
        return out
    }

    private func isSmearingSigna(_ signa: String) -> Bool {
        let normalized = signa
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.contains("смазування")
            || normalized.contains("смазывание")
            || normalized.contains("змазування")
    }

    private func formatMass(_ value: Double) -> String {
        String(format: "%.3f", value)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: #"(\.\d*?)0+$"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: ".0", options: .regularExpression)
    }

    private func formatPercent(_ value: Double) -> String {
        String(format: "%.2f", value).replacingOccurrences(of: ",", with: ".")
    }
}
