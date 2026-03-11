import Foundation

enum ExtempLegacyAdapter {
    static func makeLegacyIngredient(
        from draft: IngredientDraft,
        existing: ExtempIngredientDraft? = nil,
        substance: ExtempSubstance,
        units: [ExtempUnit],
        solutionPercent: Double?,
        solutionVolumeMl: Double?
    ) -> ExtempIngredientDraft {
        let unit = resolveUnit(for: draft.unit, in: units)

        var out = existing ?? ExtempIngredientDraft(id: draft.id, substance: substance, unit: unit)
        out.substance = substance
        out.amountValue = formatTargetValueText(draft.amountValue)
        out.unit = unit
        out.amountScope = mapLegacyScope(draft.scope)
        out.isAna = draft.isAna
        out.isQs = draft.isQS
        out.isAd = draft.isAd
        out.presentationKind = draft.presentationKind
        out.rpPrefix = draft.rpPrefix

        if draft.presentationKind == .solution {
            out.solPercentText = solutionPercent.map(formatTargetValueText) ?? ""
            out.solVolumeMlText = solutionVolumeMl.map(formatTargetValueText) ?? ""
        } else {
            out.solPercentText = ""
            out.solVolumeMlText = ""
        }

        return out
    }

    static func normalizedIngredients(
        from drafts: [IngredientDraft],
        substancesById: [UUID: ExtempSubstance],
        units: [ExtempUnit],
        solutionPercent: Double?,
        solutionVolumeMl: Double?
    ) -> [ExtempIngredientDraft] {
        var out: [ExtempIngredientDraft] = drafts.compactMap { draft in
            guard let substance = substancesById[draft.id] else { return nil }
            return makeLegacyIngredient(
                from: draft,
                substance: substance,
                units: units,
                solutionPercent: solutionPercent,
                solutionVolumeMl: solutionVolumeMl
            )
        }

        if !out.isEmpty {
            for i in stride(from: out.count - 1, through: 0, by: -1) {
                guard out[i].isAna else { continue }
                let sourceAmount = out[i].amountValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !sourceAmount.isEmpty else { continue }

                let sourceUnit = out[i].unit
                var j = i - 1
                while j >= 0 {
                    let trimmed = out[j].amountValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { break }
                    out[j].amountValue = out[i].amountValue
                    if out[j].unit == nil {
                        out[j].unit = sourceUnit
                    }
                    j -= 1
                }
            }
        }

        var lastAmount: String?
        var lastUnit: ExtempUnit?
        for i in out.indices {
            let trimmed = out[i].amountValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lastAmount = out[i].amountValue
                lastUnit = out[i].unit
                continue
            }

            if out[i].isAna, let lastAmount {
                out[i].amountValue = lastAmount
                if out[i].unit == nil {
                    out[i].unit = lastUnit
                }
            }
        }

        return out
    }

    static func vrdWarning(for ingredient: ExtempIngredientDraft, formMode: FormMode) -> String? {
        if formMode == .ointments { return nil }
        let type = ingredient.substance.refType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if type != "act" { return nil }
        guard let vrd = ingredient.substance.vrdG else { return nil }
        let unitLat = (ingredient.unit?.lat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "")
        if unitLat != "g" { return nil }
        let trimmed = ingredient.amountValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let dose = Double(normalized), dose > vrd else { return nil }
        return "⚠ Перевищення ВРД: \(formatRefDose(dose)) g > \(formatRefDose(vrd)) g"
    }

    private static func resolveUnit(for code: UnitCode, in units: [ExtempUnit]) -> ExtempUnit? {
        let unitKey = code.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if unitKey.isEmpty { return nil }
        return units.first(where: {
            $0.lat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == unitKey
                || $0.code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == unitKey
        })
    }

    private static func mapLegacyScope(_ scope: AmountScope) -> ExtempIngredientDraft.AmountScope {
        switch scope {
        case .auto:
            return .auto
        case .total:
            return .total
        case .perDose:
            return .perDose
        }
    }

    nonisolated private static func formatTargetValueText(_ value: Double) -> String {
        let s = String(format: "%.4f", value)
        var out = s
        while out.contains(".") && (out.hasSuffix("0") || out.hasSuffix(".")) {
            if out.hasSuffix("0") {
                out.removeLast()
                continue
            }
            if out.hasSuffix(".") {
                out.removeLast()
                break
            }
        }
        return out.replacingOccurrences(of: ".", with: ",")
    }

    nonisolated private static func formatRefDose(_ value: Double) -> String {
        let s = String(format: "%.4f", value)
        var out = s
        while out.contains(".") && (out.hasSuffix("0") || out.hasSuffix(".")) {
            if out.hasSuffix("0") {
                out.removeLast()
                continue
            }
            if out.hasSuffix(".") {
                out.removeLast()
                break
            }
        }
        return out.replacingOccurrences(of: ".", with: ",")
    }
}
