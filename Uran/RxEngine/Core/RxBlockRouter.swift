import Foundation

struct RxBlockRouter {
    func route(draft: ExtempRecipeDraft, facts: RxFacts) -> Set<String> {
        var ids: Set<String> = [BaseTechnologyBlock.blockId]
        let effectiveFormMode = SignaUsageAnalyzer.effectiveFormMode(for: draft)
        let signaSemantics = SignaUsageAnalyzer.analyze(signa: draft.signa)
        let pureStandardSolution = isPureStandardSolution(draft: draft)
        let hasListA = draft.ingredients.contains(where: { !$0.isAd && !$0.isQS && $0.isReferenceListA })
        let hasListB = draft.ingredients.contains(where: { !$0.isAd && !$0.isQS && $0.isReferenceListB })

        switch effectiveFormMode {
        case .powders:
            if !hasListA && !hasListB {
                ids.insert(PowdersTriturationsBlock.blockId)
            }
        case .suppositories:
            ids.insert(SuppositoriesBlock.blockId)
        case .ointments:
            ids.insert(OintmentsBlock.blockId)
        case .drops:
            let isOphthalmicDrops = draft.isOphthalmicDrops || signaSemantics.isEyeRoute
            if facts.isNonAqueousSolution {
                ids.insert(NonAqueousSolutionsBlock.blockId)
            }
            if isOphthalmicDrops {
                ids.insert(OphthalmicDropsBlock.blockId)
            } else {
                ids.insert(DropsBlock.blockId)
            }
        case .solutions:
            switch draft.liquidTechnologyMode {
            case .alcoholSolution:
                ids.insert(NonAqueousSolutionsBlock.blockId)
            case .infusion:
                ids.insert(InfusionDecoctionBlock.infusionBlockId)
            case .decoction:
                ids.insert(InfusionDecoctionBlock.decoctionBlockId)
            case .waterSolution:
                if facts.isNonAqueousSolution {
                    ids.insert(NonAqueousSolutionsBlock.blockId)
                } else if !pureStandardSolution {
                    ids.insert(WaterSolutionsBlock.blockId)
                }
            }
        case .auto:
            break
        }

        if effectiveFormMode == .solutions && signaSemantics.hasDropsDose {
            ids.insert(DropDoseSupportBlock.blockId)
        }

        if draft.useStandardSolutionsBlock {
            ids.insert(StandardSolutionsBlock.blockId)
        }
        if draft.useBuretteSystem {
            ids.insert(BuretteSystemBlock.blockId)
        }
        if draft.useVmsColloidsBlock {
            ids.insert(VMSColloidsBlock.blockId)
        }
        if hasListA {
            ids.insert(PoisonControlBlock.blockId)
        }
        if hasListB && (!hasListA || effectiveFormMode != .powders) {
            ids.insert(StrongControlBlock.blockId)
        }

        return ids
    }

    private func isPureStandardSolution(draft: ExtempRecipeDraft) -> Bool {
        guard draft.useStandardSolutionsBlock else { return false }

        let repo = StandardSolutionsRepository.shared

        func parsePercent(from text: String) -> Double? {
            let s = text.replacingOccurrences(of: ",", with: ".")
            guard let r = s.range(of: "(\\d{1,2}(?:\\.\\d+)?)\\s*%", options: .regularExpression) else { return nil }
            let m = String(s[r]).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(m)
        }

        let matches: [IngredientDraft] = draft.ingredients.compactMap { ing in
            guard !ing.isQS, !ing.isAd else { return nil }
            let explicitPercent = draft.solutionDisplayPercent(for: ing)
                ?? parsePercent(from: ing.refNameLatNom ?? ing.displayName)
            if draft.standardSolutionSourceKey != nil, ing.presentationKind == .solution {
                return ing
            }
            guard repo.matchIngredient(ing, parsedPercent: explicitPercent) != nil else { return nil }
            return ing
        }

        guard !matches.isEmpty else { return false }

        let hasOtherSolids = draft.ingredients.contains { ing in
            guard !ing.isQS, !ing.isAd else { return false }
            if matches.contains(where: { $0.id == ing.id }) { return false }
            guard ing.unit.rawValue == "g", ing.amountValue > 0 else { return false }
            return !isLiquidByReference(ing)
        }

        return !hasOtherSolids
    }

    private func isLiquidByReference(_ ing: IngredientDraft) -> Bool {
        if ing.unit.rawValue == "ml" { return true }
        let type = (ing.refType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return type == "solvent"
            || type == "buffersolution"
            || type == "standardsolution"
            || type == "tincture"
            || type == "extract"
    }
}
