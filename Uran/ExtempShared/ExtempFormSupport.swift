import Foundation

enum ExtempFormSupport {
    static func amountSummary(
        for ingredient: IngredientDraft,
        targetValue: Double? = nil,
        targetUnit: UnitCode? = nil
    ) -> String {
        let amountText = ExtempViewFormatter.formatAmount(ingredient.amountValue)
        let unitText = ingredient.unit.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if ingredient.isAd {
            let adValue = ingredient.amountValue > 0 ? ingredient.amountValue : (targetValue ?? 0)
            let adAmountText = ExtempViewFormatter.formatAmount(adValue)
            let adUnitText: String = {
                if !unitText.isEmpty { return unitText }
                return targetUnit?.rawValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }()
            if adValue > 0 {
                return adUnitText.isEmpty ? "ad \(adAmountText)" : "ad \(adAmountText) \(adUnitText)"
            }
            return "ad"
        }
        if amountText == "0", unitText.isEmpty { return "Не заполнено" }
        if amountText == "0" { return unitText.isEmpty ? "Не заполнено" : unitText }
        return unitText.isEmpty ? amountText : "\(amountText) \(unitText)"
    }

    static func solutionSummary(
        for ingredient: IngredientDraft,
        percentText: String,
        volumeText: String
    ) -> String? {
        guard ingredient.presentationKind == .solution else { return nil }
        let percent = percentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let volume = volumeText.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !percent.isEmpty { parts.append("\(percent)%") }
        if !volume.isEmpty { parts.append("\(volume) ml") }
        return parts.isEmpty ? "Раствор" : "Раствор: " + parts.joined(separator: " · ")
    }

    static func ingredientBadges(for ingredient: IngredientDraft) -> [String] {
        var badges = [scopeTitle(ingredient.scope)]
        if ingredient.isAna { badges.append("ana") }
        if ingredient.isQS { badges.append("q.s.") }
        if ingredient.isAd { badges.append("ad") }
        if ingredient.presentationKind == .solution { badges.append("sol.") }
        return badges
    }

    static func scopeTitle(_ scope: AmountScope) -> String {
        switch scope {
        case .auto:
            return "Auto"
        case .total:
            return "Total"
        case .perDose:
            return "Per dose"
        }
    }

    static func outputRenderState(
        blankType: RxBlankType,
        patientDobText: String,
        doctorFullName: String,
        clinicName: String,
        powderMassMode: PowderMassMode,
        showPpkSteps: Bool,
        showExtendedTech: Bool,
        belladonnaExtractVariant: BelladonnaExtractVariant
    ) -> ExtempOutputRenderState {
        ExtempOutputRenderState(
            blankType: blankType,
            patientDobText: patientDobText,
            doctorFullName: doctorFullName,
            clinicName: clinicName,
            powderMassMode: powderMassMode,
            showPpkSteps: showPpkSteps,
            showExtendedTech: showExtendedTech,
            belladonnaExtractVariant: belladonnaExtractVariant
        )
    }

    static func normalizedIngredients(
        normalizedDraft: ExtempRecipeDraft,
        ingredientSubstanceById: [UUID: ExtempSubstance],
        units: [ExtempUnit]
    ) -> [ExtempIngredientDraft] {
        ExtempLegacyAdapter.normalizedIngredients(
            from: normalizedDraft.ingredients,
            substancesById: ingredientSubstanceById,
            units: units,
            solutionPercent: normalizedDraft.solPercent,
            solutionVolumeMl: normalizedDraft.solVolumeMl
        )
    }

    static func groupedStorageRules(
        from rules: [ExtempStorageRule]
    ) -> [(key: String, value: [ExtempStorageRule])] {
        let groups = Dictionary(grouping: rules) { rule in
            rule.propertyTitleUk.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return groups
            .map { (key: $0.key, value: $0.value) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    static func recommendedStoragePhrases(from titles: [String]) -> [String] {
        let normalized = Set(titles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() })

        func has(_ code: String) -> Bool {
            normalized.contains(code)
        }

        var out: [String] = []
        if has("LIGHT") { out.append("Зберігати в захищеному від світла місці") }
        if has("COOL") { out.append("Зберігати в прохолодному місці") }
        if has("VOLATILE") { out.append("Зберігати в щільно закритій тарі") }
        if has("HYGRO") { out.append("Зберігати в сухому місці") }
        if has("CRYSTWATER") { out.append("Зберігати в герметичній тарі") }
        if has("CO2") { out.append("Зберігати в щільно закупореній тарі") }
        return out
    }

    static func vrdWarning(
        for ingredient: ExtempIngredientDraft,
        formMode: FormMode
    ) -> String? {
        ExtempLegacyAdapter.vrdWarning(for: ingredient, formMode: formMode)
    }
}
