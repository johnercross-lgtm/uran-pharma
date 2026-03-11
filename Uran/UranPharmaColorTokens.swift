import SwiftUI

struct UranPharmaClassificationStatus {
    let role: UranPharmaRoleState
    let solubility: UranPharmaSolubilityState
    let risk: UranPharmaRiskState
}

enum UranPharmaRoleState {
    case activeIngredient
    case solvent
    case excipient
    case flavoringCorrective
    case stabilizerPreservative
    case unknown
    case dataError

    var label: String {
        switch self {
        case .activeIngredient: return "Active ingredient"
        case .solvent: return "Solvent"
        case .excipient: return "Excipient"
        case .flavoringCorrective: return "Flavoring/Corrective"
        case .stabilizerPreservative: return "Stabilizer/Preservative"
        case .unknown: return "Unknown substance"
        case .dataError: return "Data error"
        }
    }

    var color: Color {
        switch self {
        case .activeIngredient: return .uranHex("#2F6F9F")
        case .solvent: return .uranHex("#4AA3B5")
        case .excipient: return .uranHex("#7B8A97")
        case .flavoringCorrective: return .uranHex("#6FA87A")
        case .stabilizerPreservative: return .uranHex("#8A78B0")
        case .unknown: return .uranHex("#9AA6B2")
        case .dataError: return .uranHex("#C23D3D")
        }
    }
}

enum UranPharmaSolubilityState {
    case high
    case medium
    case low
    case insoluble

    var label: String {
        switch self {
        case .high: return "High solubility"
        case .medium: return "Medium solubility"
        case .low: return "Low solubility"
        case .insoluble: return "Insoluble"
        }
    }

    var color: Color {
        switch self {
        case .high: return .uranHex("#4F9E77")
        case .medium: return .uranHex("#E1B95A")
        case .low: return .uranHex("#C98B5C")
        case .insoluble: return .uranHex("#A86A6A")
        }
    }
}

enum UranPharmaRiskState {
    case normal
    case potent
    case toxicControlled

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .potent: return "Potent"
        case .toxicControlled: return "Toxic/Controlled"
        }
    }

    var color: Color {
        switch self {
        case .normal: return .uranHex("#5F7F96")
        case .potent: return .uranHex("#D08A3C")
        case .toxicControlled: return .uranHex("#B44F4F")
        }
    }
}

enum UranPharmaClassificationResolver {
    static func resolve(ingredient: IngredientDraft, substance: ExtempSubstance?) -> UranPharmaClassificationStatus {
        if ingredient.substanceId != nil, substance == nil {
            return UranPharmaClassificationStatus(
                role: .dataError,
                solubility: .insoluble,
                risk: riskState(for: ingredient, substance: substance)
            )
        }
        if substance == nil {
            return UranPharmaClassificationStatus(
                role: .unknown,
                solubility: .medium,
                risk: .normal
            )
        }
        return UranPharmaClassificationStatus(
            role: roleState(for: ingredient, substance: substance),
            solubility: solubilityState(for: ingredient, substance: substance),
            risk: riskState(for: ingredient, substance: substance)
        )
    }

    private static func roleState(for ingredient: IngredientDraft, substance: ExtempSubstance?) -> UranPharmaRoleState {
        let source = [
            substance?.role ?? "",
            substance?.refType ?? "",
            ingredient.refType ?? "",
            ingredient.role.rawValue
        ].joined(separator: " ").lowercased()

        if source.contains("solv") || source.contains("menstru") || source.contains("solvent") {
            return .solvent
        }
        if source.contains("corrigen") || source.contains("flavor") || source.contains("аромат") {
            return .flavoringCorrective
        }
        if source.contains("stabil") || source.contains("preserv") || source.contains("консерв") {
            return .stabilizerPreservative
        }
        if source.contains("excipient") || source.contains("aux") || source.contains("base") || source.contains("основа") {
            return .excipient
        }
        return .activeIngredient
    }

    private static func solubilityState(for ingredient: IngredientDraft, substance: ExtempSubstance?) -> UranPharmaSolubilityState {
        let text = ((substance?.solubility ?? ingredient.refSolubility) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if text.isEmpty {
            return .medium
        }
        if text.contains("нерозчин")
            || text.contains("не розчин")
            || text.contains("insolub")
            || text.contains("practically insolub")
        {
            return .insoluble
        }
        if text.contains("малорозчин")
            || text.contains("malo")
            || text.contains("sparingly")
            || text.contains("slightly")
            || text.contains("погано розчин")
            || text.contains("плохо раствор")
        {
            return .low
        }
        if text.contains("розчин")
            || text.contains("раствор")
            || text.contains("soluble")
            || text.contains("miscible")
        {
            if text.contains("легко")
                || text.contains("дуже")
                || text.contains("easily")
                || text.contains("freely")
                || text.contains("very")
            {
                return .high
            }
            return .medium
        }
        return .medium
    }

    private static func riskState(for ingredient: IngredientDraft, substance: ExtempSubstance?) -> UranPharmaRiskState {
        let isToxic = (substance?.listA ?? ingredient.refListA) || (substance?.isNarcotic ?? ingredient.refIsNarcotic)
        if isToxic { return .toxicControlled }

        let isPotent = substance?.listB ?? ingredient.refListB
        if isPotent { return .potent }

        return .normal
    }
}

extension Color {
    static func uranHex(_ hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
