import Foundation

struct ExtempIngredientCompatibilityResult {
    let message: String?
    let isBlocking: Bool
}

enum ExtempIngredientService {
    static func makeCurrentIngredientsSnapshot(
        drafts: [IngredientDraft],
        substancesById: [UUID: ExtempSubstance],
        units: [ExtempUnit],
        solutionPercent: Double?,
        solutionVolumeMl: Double?
    ) -> [ExtempIngredientDraft] {
        drafts.compactMap { draft in
            guard let substance = substancesById[draft.id] else { return nil }
            return ExtempLegacyAdapter.makeLegacyIngredient(
                from: draft,
                substance: substance,
                units: units,
                solutionPercent: solutionPercent,
                solutionVolumeMl: solutionVolumeMl
            )
        }
    }

    static func checkCompatibility(
        new substance: ExtempSubstance,
        existing: [ExtempIngredientDraft],
        repository: ExtempRepository?
    ) async -> ExtempIngredientCompatibilityResult {
        do {
            if let repository,
               let hard = try await repository.checkHardIncompatibility(new: substance, existing: existing) {
                return ExtempIngredientCompatibilityResult(message: hard.message, isBlocking: true)
            }
        } catch {
            let text = error.localizedDescription.isEmpty ? "Ошибка проверки совместимости" : error.localizedDescription
            return ExtempIngredientCompatibilityResult(message: text, isBlocking: false)
        }

        let issues = IncompatibilityChecker.checkAdd(new: substance, existing: existing)
        if let block = issues.first(where: { $0.severity == .block }) {
            return ExtempIngredientCompatibilityResult(message: block.message, isBlocking: true)
        }
        if let warning = issues.first(where: { $0.severity == .warning }) {
            return ExtempIngredientCompatibilityResult(message: warning.message, isBlocking: false)
        }

        return ExtempIngredientCompatibilityResult(message: nil, isBlocking: false)
    }

    static func makeIngredientDraft(
        id: UUID,
        substance: ExtempSubstance,
        units: [ExtempUnit],
        existingDraft: ExtempRecipeDraft
    ) -> IngredientDraft {
        let type = substance.refType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let preferredUnitLat = preferredUnitLat(for: substance)
        let defaultUnit = units.first(where: {
            $0.lat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == preferredUnitLat
        }) ?? units.first(where: {
            $0.code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == preferredUnitLat
        }) ?? units.first

        let unitLat = (defaultUnit?.lat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? defaultUnit!.lat
            : (defaultUnit?.code ?? "")
        let unitCode = UnitCode(rawValue: unitLat.isEmpty ? "g" : unitLat)
        let shouldAutoQS = (type == "base") && !existingDraft.ingredients.contains(where: { $0.isQS })

        return IngredientDraft(
            id: id,
            substanceId: substance.id,
            displayName: substance.nameRu.isEmpty ? substance.nameLatNom : substance.nameRu,
            role: mapRole(substance),
            amountValue: 0,
            unit: unitCode,
            scope: .auto,
            isAna: false,
            isQS: shouldAutoQS,
            isAd: false,
            isSol: false,
            refInnKey: substance.innKey,
            refType: substance.refType,
            refNameLatNom: substance.nameLatNom,
            refNameLatGen: substance.nameLatGen,
            refVrdG: substance.vrdG,
            refVsdG: substance.vsdG,
            refPedsVrdG: substance.pedsVrdG,
            refPedsRdG: substance.pedsRdG,
            refVrdChild0_1: substance.vrdChild0_1,
            refVrdChild1_6: substance.vrdChild1_6,
            refVrdChild7_14: substance.vrdChild7_14,
            refKuoMlPerG: substance.kuoMlPerG,
            refKvGPer100G: substance.kvGPer100G,
            refGttsPerMl: substance.gttsPerMl,
            refEFactor: substance.eFactor,
            refEFactorNaCl: substance.eFactor,
            refDensity: substance.density,
            refSolubility: substance.solubility,
            refStorage: substance.storage,
            refInteractionNotes: substance.interactionNotes,
            refOintmentNote: substance.ointmentNote,
            refDissolutionType: substance.dissolutionType,
            refNeedsTrituration: substance.needsTrituration,
            refListA: substance.listA,
            refListB: substance.listB,
            refIsNarcotic: substance.isNarcotic,
            refPharmActivity: substance.pharmActivity,
            refPhysicalState: substance.physicalState,
            refPrepMethod: substance.prepMethod,
            refHerbalRatio: substance.herbalRatio,
            refWaterTempC: substance.waterTempC,
            refHeatBathMin: substance.heatBathMin,
            refStandMin: substance.standMin,
            refCoolMin: substance.coolMin,
            refStrain: substance.strain,
            refPressMarc: substance.pressMarc,
            refBringToVolume: substance.bringToVolume,
            refExtractionSolvent: substance.extractionSolvent,
            refTinctureRatio: substance.tinctureRatio,
            refMacerationDays: substance.macerationDays,
            refFilter: substance.filter,
            refExtractType: substance.extractType,
            refExtractSolvent: substance.extractSolvent,
            refExtractRatio: substance.extractRatio,
            refSolventType: substance.solventType,
            refSterile: substance.sterile,
            refIsVolatile: substance.isVolatile,
            refIsFlammable: substance.isFlammable,
            refHeatingAllowed: substance.heatingAllowed,
            refHeatingTempMaxC: substance.heatingTempMaxC,
            refDefaultEthanolStrength: substance.defaultEthanolStrength,
            refIncompatibleWithEthanol: substance.incompatibleWithEthanol
        )
    }

    private static func mapRole(_ substance: ExtempSubstance) -> IngredientRole {
        let raw = substance.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "base":
            return .base
        case "solvent":
            return .solvent
        default:
            break
        }

        let refType = substance.refType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if refType == "act" { return .active }
        return .other
    }

    private static func preferredUnitLat(for substance: ExtempSubstance) -> String {
        isLiquidSubstance(substance) ? "ml" : "g"
    }

    private static func isLiquidSubstance(_ substance: ExtempSubstance) -> Bool {
        if PurifiedWaterHeuristics.isPurifiedWater(substance) {
            return true
        }

        let type = substance.refType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let physicalState = (substance.physicalState ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hay = "\(substance.innKey) \(substance.nameLatNom) \(substance.nameRu)".lowercased()

        let liquidTypes: Set<String> = [
            "solv",
            "solvent",
            "buffersolution",
            "standardsolution",
            "liquidstandard",
            "tincture",
            "extract",
            "syrup",
            "juice",
            "viscous liquid",
            "viscousliquid",
            "liquid",
            "alcoholic"
        ]
        if liquidTypes.contains(type) {
            return true
        }

        if physicalState.contains("liquid") || physicalState.contains("жидк") || physicalState.contains("рідк") {
            return true
        }

        return hay.contains("tinct")
            || hay.contains("настойк")
            || hay.contains("настоянк")
            || hay.contains("extract")
            || hay.contains("extr.")
            || hay.contains("sirup")
            || hay.contains("syrup")
            || hay.contains("сироп")
            || hay.contains("succus")
            || hay.contains("juice")
            || hay.contains("vinyl")
    }
}
