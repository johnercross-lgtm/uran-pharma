import Foundation

enum IncompatibilitySeverity: String {
    case block
    case warning
}

struct IncompatibilityIssue: Hashable {
    let severity: IncompatibilitySeverity
    let message: String
}

enum IncompatibilityChecker {
    static func checkAdd(
        new: ExtempSubstance,
        existing: [ExtempIngredientDraft]
    ) -> [IncompatibilityIssue] {
        let current = existing.map { $0.substance }
        var issues: [IncompatibilityIssue] = []

        if let ctx = contextBlock(new: new, existing: current) {
            issues.append(ctx)
        }

        if let w1 = adsorbentWarning(new: new, existing: current) {
            issues.append(w1)
        }

        if let w2 = waterOilWarning(new: new, existing: current) {
            issues.append(w2)
        }

        return issues
    }

    // MARK: - Rules

    private static func contextBlock(new: ExtempSubstance, existing: [ExtempSubstance]) -> IncompatibilityIssue? {
        let newTags = tags(for: new)
        let existingTags = Set(existing.flatMap(tags(for:)))

        // Oxidizers + reducers
        if newTags.contains(.oxidizer) && existingTags.contains(.reducer) {
            return IncompatibilityIssue(severity: .block, message: "Несовместимость: окислитель + восстановитель (опасная реакция).")
        }
        if newTags.contains(.reducer) && existingTags.contains(.oxidizer) {
            return IncompatibilityIssue(severity: .block, message: "Несовместимость: восстановитель + окислитель (опасная реакция).")
        }

        // Acids + alkalis
        if newTags.contains(.acid) && existingTags.contains(.alkali) {
            return IncompatibilityIssue(severity: .block, message: "Несовместимость: кислота + щёлочь (нейтрализация).")
        }
        if newTags.contains(.alkali) && existingTags.contains(.acid) {
            return IncompatibilityIssue(severity: .block, message: "Несовместимость: щёлочь + кислота (нейтрализация).")
        }

        if newTags.contains(.acidSensitive) && existingTags.contains(.acid) {
            return IncompatibilityIssue(
                severity: .block,
                message: "Несовместимость: вещество нестабильно в кислой среде (риск разложения и утраты активности)."
            )
        }
        if newTags.contains(.acid) && existingTags.contains(.acidSensitive) {
            return IncompatibilityIssue(
                severity: .block,
                message: "Несовместимость: кислый компонент может вызвать разложение кислоточувствительного вещества."
            )
        }
        if newTags.contains(.alkaliSensitive) && existingTags.contains(.alkali) {
            return IncompatibilityIssue(
                severity: .block,
                message: "Несовместимость: щелочная среда может вызвать выпадение основания из соли и осадок."
            )
        }
        if newTags.contains(.alkali) && existingTags.contains(.alkaliSensitive) {
            return IncompatibilityIssue(
                severity: .block,
                message: "Несовместимость: щёлочь может осаждать основание чувствительного вещества из раствора."
            )
        }

        if newTags.contains(.alkaloidSaltSensitive) && existingTags.contains(.alkaloidSalt) {
            return IncompatibilityIssue(
                severity: .block,
                message: "Несовместимость: возможен осадок при сочетании с солями алкалоидов."
            )
        }
        if newTags.contains(.alkaloidSalt) && existingTags.contains(.alkaloidSaltSensitive) {
            return IncompatibilityIssue(
                severity: .block,
                message: "Несовместимость: соль алкалоида может выпадать в осадок с данным веществом."
            )
        }

        return nil
    }

    private static func adsorbentWarning(new: ExtempSubstance, existing: [ExtempSubstance]) -> IncompatibilityIssue? {
        let newTags = tags(for: new)
        let existingTags = Set(existing.flatMap(tags(for:)))

        let hasAdsorbent = newTags.contains(.adsorbent) || existingTags.contains(.adsorbent)
        let hasActive = newTags.contains(.active) || existingTags.contains(.active)

        if hasAdsorbent && hasActive {
            return IncompatibilityIssue(
                severity: .warning,
                message: "Предупреждение: адсорбент может снизить эффективность активного вещества (адсорбция)."
            )
        }

        return nil
    }

    private static func waterOilWarning(new: ExtempSubstance, existing: [ExtempSubstance]) -> IncompatibilityIssue? {
        let newTags = tags(for: new)
        let existingTags = Set(existing.flatMap(tags(for:)))

        let hasWater = newTags.contains(.water) || existingTags.contains(.water)
        let hasOilBase = newTags.contains(.oilBase) || existingTags.contains(.oilBase)

        if hasWater && hasOilBase {
            return IncompatibilityIssue(
                severity: .warning,
                message: "Предупреждение: водная фаза + масляная основа — вероятно потребуется эмульгатор."
            )
        }

        return nil
    }

    // MARK: - Tagging

    private enum SubstanceTag: Hashable {
        case oxidizer
        case reducer
        case acid
        case alkali
        case acidSensitive
        case alkaliSensitive
        case alkaloidSalt
        case alkaloidSaltSensitive
        case adsorbent
        case water
        case oilBase
        case active
    }

    nonisolated private static func tags(for s: ExtempSubstance) -> [SubstanceTag] {
        var out: [SubstanceTag] = []

        let key = normKey(s)
        let nameLat = s.nameLatNom.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let role = s.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if role.contains("актив") {
            out.append(.active)
        }

        if let profile = s.propertyOverride {
            if profile.interactionRules.contains(.incompatibleWithAcids) {
                out.append(.acidSensitive)
            }
            if profile.interactionRules.contains(.incompatibleWithAlkalies) {
                out.append(.alkaliSensitive)
            }
            if profile.interactionRules.contains(.incompatibleWithAlkaloidSalts) {
                out.append(.alkaloidSaltSensitive)
            }
        }

        // Explicit known substances
        if key == "kalii permanganas" { out.append(.oxidizer) }
        if key == "glycerinum" { out.append(.reducer) }
        if key == "talcum" { out.append(.adsorbent) }

        if SubstancePropertyCatalog.looksLikeAlkaloidSalt(
            innKey: s.innKey,
            nameLatNom: s.nameLatNom,
            nameRu: s.nameRu
        ) {
            out.append(.alkaloidSalt)
        }

        // Acids by latin name
        if nameLat.hasPrefix("acidum ") { out.append(.acid) }

        // Alkalis (minimal list; can be expanded)
        if key.contains("hydrocarbonas") || key.contains("tetraboras") {
            out.append(.alkali)
        }

        // Water solvents
        if key.hasPrefix("aqua") { out.append(.water) }

        // Oils / oily bases
        if nameLat.hasPrefix("oleum ") { out.append(.oilBase) }
        if role.contains("основа") && (nameLat.contains("vaselin") || nameLat.contains("adeps") || nameLat.contains("lanolin") || nameLat.contains("paraffin")) {
            out.append(.oilBase)
        }

        return out
    }

    nonisolated private static func normKey(_ s: ExtempSubstance) -> String {
        let raw = s.innKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            return raw.lowercased()
        }
        return s.nameLatNom.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
