import Foundation

struct RxDraftNormalizationResult {
    var normalizedDraft: ExtempRecipeDraft
    var issues: [RxIssue]
}

struct RxDraftNormalizer {
    func normalize(draft: ExtempRecipeDraft) -> RxDraftNormalizationResult {
        var issues: [RxIssue] = []
        var normalized = draft

        let qsIdxs = normalized.ingredients.indices.filter { normalized.ingredients[$0].isQS }
        if qsIdxs.count > 1 {
            issues.append(
                RxIssue(
                    code: "qs.multiple",
                    severity: .blocking,
                    message: "Дозволено лише один q.s."
                )
            )

            if let keep = qsIdxs.last {
                for i in qsIdxs where i != keep {
                    normalized.ingredients[i].isQS = false
                }
            }
        }

        let adIdxs = normalized.ingredients.indices.filter { normalized.ingredients[$0].isAd }
        if adIdxs.count > 1 {
            issues.append(
                RxIssue(
                    code: "ad.multiple",
                    severity: .blocking,
                    message: "Дозволено лише один ad"
                )
            )
        }
        if let keep = adIdxs.last {
            for i in adIdxs where i != keep {
                normalized.ingredients[i].isAd = false
            }
            if let lastIngredientIdx = normalized.ingredients.indices.last, keep != lastIngredientIdx {
                issues.append(
                    RxIssue(
                        code: "ad.not.last",
                        severity: .warning,
                        message: "ad бажано ставити в останньому інгредієнті"
                    )
                )
            }
        }

        let solutionIdxs = normalized.ingredients.indices.filter { normalized.ingredients[$0].presentationKind == .solution }
        if solutionIdxs.count > 1 {
            issues.append(
                RxIssue(
                    code: "sol.multiple",
                    severity: .warning,
                    message: "У рецепті кілька Sol.-компонентів; нормалізатор не повинен змінювати їх presentationKind"
                )
            )
        }

        let hasSolution = normalized.ingredients.contains(where: { $0.presentationKind == .solution })
        if !hasSolution {
            normalized.solPercent = nil
            normalized.solPercentInputText = ""
            normalized.solVolumeMl = nil
        } else {
            if normalized.solPercent == nil,
               let inferredPercent = inferSolutionPercent(from: normalized),
               inferredPercent > 0,
               inferredPercent <= 100
            {
                normalized.solPercent = inferredPercent
                normalized.solPercentInputText = formatPercent(inferredPercent)
            }

            if let p = normalized.solPercent {
                if p <= 0 || p > 100 {
                    issues.append(
                        RxIssue(
                            code: "sol.percent.invalid",
                            severity: .blocking,
                            message: "Sol.% має бути в діапазоні 0–100"
                        )
                    )
                }
            } else {
                issues.append(
                    RxIssue(
                        code: "sol.percent.missing",
                        severity: .warning,
                        message: "Sol.% не задано"
                    )
                )
            }

            if normalized.solVolumeMl == nil,
               let inferredVolume = inferSolutionVolumeMl(from: normalized),
               inferredVolume > 0
            {
                normalized.solVolumeMl = inferredVolume
            }

            if let v = normalized.solVolumeMl {
                if v <= 0 {
                    issues.append(
                        RxIssue(
                            code: "sol.volume.invalid",
                            severity: .blocking,
                            message: "Sol. volume має бути > 0 ml"
                        )
                    )
                }
            } else {
                issues.append(
                    RxIssue(
                        code: "sol.volume.missing",
                        severity: .warning,
                        message: "Sol. volume (ml) не задано"
                    )
                )
            }
        }

        applyAnaEqualization(to: &normalized)

        return RxDraftNormalizationResult(normalizedDraft: normalized, issues: issues)
    }

    private func inferSolutionPercent(from draft: ExtempRecipeDraft) -> Double? {
        guard let solutionIngredient = draft.ingredients.first(where: { $0.presentationKind == .solution }) else {
            return nil
        }

        let descriptor = (solutionIngredient.refNameLatNom ?? solutionIngredient.displayName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ",", with: ".")
        if descriptor.isEmpty {
            return nil
        }

        if let percentRange = descriptor.range(of: #"(\d{1,3}(?:\.\d+)?)\s*%"#, options: .regularExpression) {
            let raw = String(descriptor[percentRange]).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let percent = Double(raw), percent > 0, percent <= 100 {
                return percent
            }
        }

        if let ratioRange = descriptor.range(
            of: #"(?<!\d)1\s*[:/]\s*([0-9]+(?:\.[0-9]+)?)"#,
            options: .regularExpression
        ) {
            let matched = String(descriptor[ratioRange])
            if let denominatorRange = matched.range(of: #"[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression),
               let denominator = Double(String(matched[denominatorRange])),
               denominator > 0 {
                return 100.0 / denominator
            }
        }

        return nil
    }

    private func inferSolutionVolumeMl(from draft: ExtempRecipeDraft) -> Double? {
        guard let solutionIngredient = draft.ingredients.first(where: { $0.presentationKind == .solution }) else {
            return nil
        }

        let unit = solutionIngredient.unit.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if (unit == "ml" || unit == "мл"), solutionIngredient.amountValue > 0 {
            return solutionIngredient.amountValue
        }

        if let explicitTarget = draft.explicitLiquidTargetMl, explicitTarget > 0 {
            return explicitTarget
        }
        if let legacyTarget = draft.legacyAdOrQsLiquidTargetMl, legacyTarget > 0 {
            return legacyTarget
        }

        return nil
    }

    private func formatPercent(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(format: "%.0f", value)
        }
        if (value * 10).rounded(.towardZero) == value * 10 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }

    private func applyAnaEqualization(to draft: inout ExtempRecipeDraft) {
        guard !draft.ingredients.isEmpty else { return }

        // Pattern: "... [prev no amount], [ana line with amount]".
        // Fill previous missing amounts with the current ana value until an explicit amount is reached.
        for i in stride(from: draft.ingredients.count - 1, through: 0, by: -1) {
            guard draft.ingredients[i].isAna else { continue }
            let sourceAmount = draft.ingredients[i].amountValue
            guard sourceAmount > 0 else { continue }
            let sourceUnit = draft.ingredients[i].unit

            var j = i - 1
            while j >= 0 {
                if draft.ingredients[j].isQS || draft.ingredients[j].isAd {
                    break
                }
                if draft.ingredients[j].amountValue > 0 {
                    break
                }
                draft.ingredients[j].amountValue = sourceAmount
                draft.ingredients[j].unit = sourceUnit
                j -= 1
            }
        }

        // Pattern: "... [amount], [ana with no amount]".
        // Fill missing ana amount from the closest previous explicit amount.
        var lastAmount: Double?
        var lastUnit: UnitCode?
        for i in draft.ingredients.indices {
            if draft.ingredients[i].amountValue > 0 {
                lastAmount = draft.ingredients[i].amountValue
                lastUnit = draft.ingredients[i].unit
                continue
            }

            guard draft.ingredients[i].isAna, let lastAmount else { continue }
            draft.ingredients[i].amountValue = lastAmount
            if let lastUnit {
                draft.ingredients[i].unit = lastUnit
            }
        }
    }
}
