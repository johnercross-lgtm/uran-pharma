import Foundation

struct RxPrescriptionBuilder {
    private enum EffectiveForm {
        case powders
        case solutions
        case drops
        case suppositories
        case ointments
        case auto
    }

    private struct DisplayIngredient {
        var ingredient: IngredientDraft
        var amountText: String
        var unitText: String
        var isAna: Bool
    }

    private struct SubscriptioResult {
        let mfs: String?
        let dtd: String?
        let signaCommand: String
    }

    func build(
        draft: ExtempRecipeDraft,
        routeBranch: String?,
        config: RxOutputRenderConfig,
        issueDate: Date = Date()
    ) -> String {
        let effectiveForm = inferEffectiveForm(draft: draft, routeBranch: routeBranch)
        let signaTrimmed = draft.signa.trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        lines.append("Дата выписки: \(formatDate(issueDate))")

        let patient = draft.patientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let dob = config.patientDobText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !patient.isEmpty {
            if dob.isEmpty {
                lines.append("Пациент: \(patient)")
            } else {
                lines.append("Пациент: \(patient) (ДР: \(dob))")
            }
        }

        let doctor = config.doctorFullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !doctor.isEmpty {
            lines.append("Врач: \(doctor)")
        }

        let clinic = config.clinicName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clinic.isEmpty {
            lines.append("Учреждение: \(clinic)")
        }

        lines.append(config.blankType.rxHeader)

        let hasQs = draft.ingredients.contains(where: { $0.isQS })
        let componentCount = mixtureComponentCount(draft: draft, form: effectiveForm)

        let displayItems = normalizedDisplayIngredients(from: draft)
        let ingredientLines: [String] = {
            if !hasQs {
                return displayItems
                    .map { latinLine(for: $0.ingredient, amountText: $0.amountText, unitText: $0.unitText, isAna: $0.isAna, draft: draft) }
                    .filter { !$0.isEmpty }
            }

            return displayItems
                .filter { !$0.ingredient.isQS }
                .map { latinLine(for: $0.ingredient, amountText: $0.amountText, unitText: $0.unitText, isAna: $0.isAna, draft: draft) }
                .filter { !$0.isEmpty }
        }()

        if let first = ingredientLines.first {
            lines[lines.count - 1] = "\(config.blankType.rxHeader) \(first)"
            for rest in ingredientLines.dropFirst() {
                lines.append("     \(rest)")
            }
        } else {
            lines[lines.count - 1] = "\(config.blankType.rxHeader) —"
        }

        if hasQs, let base = draft.ingredients.first(where: { $0.isQS }) {
            let baseName = latinLine(for: base, amountText: "", unitText: "", isAna: false, draft: draft)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let targetText: String? = {
                guard let value = draft.normalizedTargetValue else { return nil }
                let unit = (draft.resolvedTargetUnit?.rawValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if unit.isEmpty { return formatAmount(value) }
                return "\(formatAmount(value)) \(unit)"
            }()

            if effectiveForm == .powders, let targetText {
                lines.append("     \(baseName) ut fiat pulvis \(targetText)".trimmingCharacters(in: .whitespaces))
            } else {
                lines.append("     \(baseName)".trimmingCharacters(in: .whitespaces))
            }
        }

        let subscriptio = generateSubscriptio(
            form: effectiveForm,
            numberOfDoses: draft.numero,
            isPerDose: !(effectiveForm == .powders && config.powderMassMode == .divide),
            componentCount: componentCount
        )

        if let mfs = subscriptio.mfs,
           !mfs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(mfs)
        }
        if let dtd = subscriptio.dtd,
           !dtd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(dtd)
        }

        let signaValue = signaTrimmed.isEmpty ? "—" : signaTrimmed
        if subscriptio.signaCommand == "S.:" {
            lines.append("S.: \(signaValue)")
        } else {
            lines.append("\(subscriptio.signaCommand): \(signaValue)")
        }

        return lines.joined(separator: "\n")
    }

    private func normalizedDisplayIngredients(from draft: ExtempRecipeDraft) -> [DisplayIngredient] {
        var out: [DisplayIngredient] = draft.ingredients.map { ing in
            let displayAmount: Double? = {
                if ing.isAd || ing.isQS {
                    if let target = draft.normalizedTargetValue {
                        return target
                    }
                    if ing.amountValue > 0 {
                        return ing.amountValue
                    }
                    return nil
                }
                return ing.amountValue > 0 ? ing.amountValue : nil
            }()
            let displayUnit = (ing.isAd || ing.isQS)
                ? (draft.resolvedTargetUnit?.rawValue ?? ing.unit.rawValue)
                : ing.unit.rawValue
            return DisplayIngredient(
                ingredient: ing,
                amountText: displayAmount.map(formatAmount) ?? "",
                unitText: displayUnit,
                isAna: ing.isAna
            )
        }

        guard !out.isEmpty else { return out }

        // If an ana-marked line has amount, apply it to previous missing lines.
        for i in stride(from: out.count - 1, through: 0, by: -1) {
            guard out[i].isAna else { continue }
            let sourceAmount = out[i].amountText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sourceAmount.isEmpty else { continue }
            let sourceUnit = out[i].unitText

            var j = i - 1
            while j >= 0 {
                if out[j].ingredient.isQS || out[j].ingredient.isAd {
                    break
                }
                if !out[j].amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    break
                }
                out[j].amountText = sourceAmount
                out[j].unitText = sourceUnit
                out[j].isAna = true
                j -= 1
            }
        }

        // If ana amount is omitted, inherit from the nearest previous explicit amount.
        var lastAmount: String?
        var lastUnit: String?
        for i in out.indices {
            let currentAmount = out[i].amountText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !currentAmount.isEmpty {
                lastAmount = out[i].amountText
                lastUnit = out[i].unitText
                continue
            }

            guard out[i].isAna, let lastAmount else { continue }
            out[i].amountText = lastAmount
            if let lastUnit {
                out[i].unitText = lastUnit
            }
        }

        guard out.count >= 2 else { return out }

        for i in 0..<(out.count - 1) {
            let next = out[i + 1]
            if next.ingredient.isQS { continue }
            if !next.isAna || next.amountText.isEmpty { continue }
            if out[i].amountText.isEmpty { continue }

            let sameValue = out[i].amountText == next.amountText
            let sameUnit = out[i].unitText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == next.unitText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if sameValue && sameUnit {
                out[i].amountText = ""
                out[i].unitText = ""
                out[i].isAna = false
            }
        }

        return out
    }

    private func inferEffectiveForm(draft: ExtempRecipeDraft, routeBranch: String?) -> EffectiveForm {
        switch SignaUsageAnalyzer.effectiveFormMode(for: draft) {
        case .powders:
            return .powders
        case .solutions:
            return .solutions
        case .drops:
            return .drops
        case .suppositories:
            return .suppositories
        case .ointments:
            return .ointments
        case .auto:
            break
        }

        if let routeBranch {
            switch routeBranch {
            case "powders":
                return .powders
            case "solutions", "infusion", "decoction", "water_solution", "aqueous_true_solution", "aqueous_burette_solution":
                return .solutions
            case "drops", "ophthalmic_drops", "internal_drops", "nasal_drops":
                return .drops
            case "suppositories":
                return .suppositories
            case "ointments":
                return .ointments
            default:
                break
            }
        }

        return .powders
    }

    private func generateSubscriptio(
        form: EffectiveForm,
        numberOfDoses: Int?,
        isPerDose: Bool,
        componentCount: Int
    ) -> SubscriptioResult {
        let isMixture = componentCount > 1
        let n = max(0, numberOfDoses ?? 0)

        let mfs: String? = {
            switch form {
            case .powders:
                return "M. f. pulv."
            case .ointments:
                return "M. f. ung."
            case .suppositories:
                return "M. f. supp."
            case .solutions, .drops:
                return nil
            case .auto:
                return isMixture ? "M." : nil
            }
        }()

        let dtd: String? = {
            guard n > 1 else { return nil }
            if isPerDose {
                return "D. t. d. N \(n)"
            }
            if form == .powders || form == .suppositories {
                return "Div. in p. aeq. N \(n)"
            }
            return nil
        }()

        let signaCommand: String = {
            if form == .solutions || form == .drops {
                return isMixture ? "M. D. S." : "D. S."
            }
            return "S.:"
        }()

        return SubscriptioResult(mfs: mfs, dtd: dtd, signaCommand: signaCommand)
    }

    private func mixtureComponentCount(draft: ExtempRecipeDraft, form: EffectiveForm) -> Int {
        switch form {
        case .solutions, .drops:
            return draft.ingredients.filter { !$0.isQS }.count
        case .powders, .suppositories, .ointments, .auto:
            return draft.ingredients.filter { !$0.isQS && !$0.isAd }.count
        }
    }

    private func latinLine(
        for ingredient: IngredientDraft,
        amountText: String,
        unitText: String,
        isAna: Bool,
        draft: ExtempRecipeDraft
    ) -> String {
        let genRaw = (ingredient.refNameLatGen ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let nomRaw = (ingredient.refNameLatNom ?? ingredient.displayName).trimmingCharacters(in: .whitespacesAndNewlines)

        var name = genRaw.isEmpty ? nomRaw : genRaw
        if name.isEmpty { name = "Substantia" }

        if let token = ingredient.rpPrefix.latinToken,
           shouldApplyRpPrefix(token: token, ingredient: ingredient, draft: draft) {
            let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !lower.hasPrefix(token.lowercased()) {
                name = "\(token) \(name)"
            }
        }

        if ingredient.presentationKind == .solution {
            let volume = max(0, draft.solutionVolumeMl(for: ingredient) ?? 0)
            if volume > 0 {
                var tail: [String] = []
                if let p = draft.solutionDisplayPercent(for: ingredient) {
                    tail.append("\(formatAmount(p))%")
                }
                tail.append("— \(formatAmount(volume)) ml")
                return ([name] + tail).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            }
        }

        if ingredient.isQS {
            return "\(name) q.s.".trimmingCharacters(in: .whitespaces)
        }

        if ingredient.isAd {
            let parts = [
                name,
                "ad",
                amountText.isEmpty ? nil : amountText,
                unitText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : unitText
            ].compactMap { $0 }
            return parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }

        let amountParts: [String?] = {
            if isAna {
                return ["ana", amountText.isEmpty ? nil : amountText, unitText.isEmpty ? nil : unitText]
            }
            return [amountText.isEmpty ? nil : amountText, unitText.isEmpty ? nil : unitText]
        }()

        let parts = ([name] + amountParts).compactMap { $0 }
        return parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    private func shouldApplyRpPrefix(token: String, ingredient: IngredientDraft, draft: ExtempRecipeDraft) -> Bool {
        if token.lowercased() == "sol.",
           draft.solutionPercentRepresentsSolventStrength(for: ingredient) {
            return false
        }
        return true
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }

    private func formatAmount(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        }

        let raw = String(format: "%.4f", value).replacingOccurrences(of: ",", with: ".")
        return raw.replacingOccurrences(
            of: "(\\.\\d*?[1-9])0+$|\\.0+$",
            with: "$1",
            options: .regularExpression
        )
    }
}
