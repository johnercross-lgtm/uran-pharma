import SwiftUI

@MainActor
struct ExtempFormBindingAdapter {
    let store: RxBuilderStore
    let viewModel: ExtempFormBuilderViewModel
    let parseDouble: (String) -> Double?
    let autoDetectedFormMode: () -> FormMode
    let getFormModeMirror: () -> FormMode
    let setFormModeMirror: (FormMode) -> Void
    let getQsTargetText: () -> String
    let setQsTargetText: (String) -> Void
    let getQsTargetUnitId: () -> Int?
    let setQsTargetUnitId: (Int?) -> Void
    let getPatientFullName: () -> String
    let setPatientFullName: (String) -> Void
    let getPrescriptionNumber: () -> String
    let setPrescriptionNumber: (String) -> Void
    let getPatientAgeYearsText: () -> String
    let setPatientAgeYearsText: (String) -> Void

    func bindingForDraftIngredient(_ id: UUID) -> Binding<IngredientDraft> {
        Binding(
            get: {
                store.draft.ingredients.first(where: { $0.id == id }) ?? IngredientDraft(
                    id: id,
                    substanceId: 0,
                    displayName: "",
                    role: .other,
                    amountValue: 0,
                    unit: UnitCode(rawValue: ""),
                    scope: .auto,
                    isAna: false,
                    isQS: false,
                    isAd: false,
                    isSol: false
                )
            },
            set: { newValue in
                viewModel.replaceIngredient(in: store, id: id, with: newValue)
            }
        )
    }

    func numeroTextBinding() -> Binding<String> {
        ExtempBindingFactory.optionalIntText(
            getValue: { store.draft.numero },
            setValue: { value in
                viewModel.setDraftValue(in: store, \.numero, to: value)
            }
        )
    }

    func amountTextBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let ingredient = store.draft.ingredients.first(where: { $0.id == id }) else { return "" }
                return ExtempViewFormatter.formatAmount(ingredient.amountValue)
            },
            set: { newText in
                let value = parseDouble(newText)
                viewModel.updateIngredient(in: store, id: id) { $0.amountValue = value ?? 0 }
            }
        )
    }

    func solPercentTextBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let ingredient = store.draft.ingredients.first(where: { $0.id == id }) else { return "" }
                guard ingredient.presentationKind == .solution else { return "" }
                let rawInput = store.draft.solPercentInputText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !rawInput.isEmpty {
                    return rawInput
                }
                if let value = store.draft.solPercent, value > 0 {
                    return ExtempViewFormatter.formatAmount(value)
                }
                return ""
            },
            set: { newText in
                viewModel.updateSolutionPercent(
                    in: store,
                    ingredientId: id,
                    text: newText,
                    parsedValue: parseSolutionPercentInput(newText)
                )
            }
        )
    }

    func solVolumeMlTextBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let ingredient = store.draft.ingredients.first(where: { $0.id == id }) else { return "" }
                guard ingredient.presentationKind == .solution else { return "" }
                if let value = store.draft.solVolumeMl, value > 0 {
                    return ExtempViewFormatter.formatAmount(value)
                }
                let unit = ingredient.unit.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if unit == "ml", ingredient.amountValue > 0 {
                    return ExtempViewFormatter.formatAmount(ingredient.amountValue)
                }
                return ""
            },
            set: { newText in
                viewModel.updateSolutionVolume(
                    in: store,
                    ingredientId: id,
                    text: newText,
                    parsedValue: parseDouble(newText)
                )
            }
        )
    }

    func unitSelectionBinding(for id: UUID) -> Binding<ExtempUnit?> {
        Binding(
            get: {
                guard let ingredient = store.draft.ingredients.first(where: { $0.id == id }) else { return nil }
                return unitFor(code: ingredient.unit)
            },
            set: { newUnit in
                let preferred = (newUnit?.lat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    ? newUnit!.lat
                    : (newUnit?.code ?? "")
                let code = UnitCode(rawValue: preferred.isEmpty ? "g" : preferred)
                viewModel.updateIngredient(in: store, id: id) { $0.unit = code }
            }
        )
    }

    func flagBinding(
        for id: UUID,
        get: @escaping (IngredientDraft) -> Bool,
        set: @escaping (inout IngredientDraft, Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: {
                guard let ingredient = store.draft.ingredients.first(where: { $0.id == id }) else { return false }
                return get(ingredient)
            },
            set: { newValue in
                viewModel.updateIngredient(in: store, id: id) { ingredient in
                    set(&ingredient, newValue)
                }
            }
        )
    }

    func adBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: {
                store.draft.ingredients.first(where: { $0.id == id })?.isAd ?? false
            },
            set: { newValue in
                viewModel.setAdFlag(in: store, ingredientId: id, isEnabled: newValue)
            }
        )
    }

    func formModeBinding() -> Binding<FormMode> {
        Binding(
            get: { store.draft.formMode },
            set: { newValue in
                let resolvedMode = (newValue == .auto) ? autoDetectedFormMode() : newValue
                viewModel.setFormMode(in: store, to: newValue, resolvedMode: resolvedMode)
                if getFormModeMirror() != newValue {
                    setFormModeMirror(newValue)
                }
            }
        )
    }

    func liquidTechnologyModeBinding() -> Binding<LiquidTechnologyMode> {
        Binding(
            get: { store.draft.liquidTechnologyMode },
            set: { newValue in
                viewModel.setDraftValue(in: store, \.liquidTechnologyMode, to: newValue)
            }
        )
    }

    func ophthalmicDropsBinding() -> Binding<Bool> {
        Binding(
            get: { store.draft.isOphthalmicDrops },
            set: { newValue in
                viewModel.setDraftValue(in: store, \.isOphthalmicDrops, to: newValue)
            }
        )
    }

    func useVmsColloidsBinding() -> Binding<Bool> {
        Binding(
            get: { store.draft.useVmsColloidsBlock },
            set: { newValue in
                viewModel.setDraftValue(in: store, \.useVmsColloidsBlock, to: newValue)
            }
        )
    }

    func useStandardSolutionsBinding() -> Binding<Bool> {
        Binding(
            get: { store.draft.useStandardSolutionsBlock },
            set: { newValue in
                viewModel.setDraftValue(in: store, \.useStandardSolutionsBlock, to: newValue)
            }
        )
    }

    func useBuretteSystemBinding() -> Binding<Bool> {
        Binding(
            get: { store.draft.useBuretteSystem },
            set: { newValue in
                viewModel.setDraftValue(in: store, \.useBuretteSystem, to: newValue)
            }
        )
    }

    func metrologyScaleBinding() -> Binding<MetrologicalScaleSelection> {
        Binding(
            get: { store.draft.metrologyScale },
            set: { newValue in
                viewModel.setDraftValue(in: store, \.metrologyScale, to: newValue)
            }
        )
    }

    func metrologyDropperModeBinding() -> Binding<MetrologicalDropperMode> {
        Binding(
            get: { store.draft.metrologyDropperMode },
            set: { newValue in
                viewModel.setDraftValue(in: store, \.metrologyDropperMode, to: newValue)
            }
        )
    }

    func metrologyDropperDropsPerMlWaterBinding() -> Binding<String> {
        ExtempBindingFactory.optionalDoubleText(
            getValue: { store.draft.metrologyDropperDropsPerMlWater },
            setValue: { value in
                viewModel.setDraftValue(in: store, \.metrologyDropperDropsPerMlWater, to: value)
            },
            formatValue: ExtempViewFormatter.formatAmount,
            parseValue: parseDouble
        )
    }

    func metrologyCorrectionVolumeMlBinding() -> Binding<String> {
        ExtempBindingFactory.optionalDoubleText(
            getValue: { store.draft.metrologyCorrectionVolumeMl },
            setValue: { value in
                viewModel.setDraftValue(in: store, \.metrologyCorrectionVolumeMl, to: value)
            },
            formatValue: ExtempViewFormatter.formatAmount,
            parseValue: parseDouble
        )
    }

    func metrologyCorrectionActualPercentBinding() -> Binding<String> {
        ExtempBindingFactory.optionalDoubleText(
            getValue: { store.draft.metrologyCorrectionActualPercent },
            setValue: { value in
                viewModel.setDraftValue(in: store, \.metrologyCorrectionActualPercent, to: value)
            },
            formatValue: ExtempViewFormatter.formatAmount,
            parseValue: parseDouble
        )
    }

    func metrologyCorrectionTargetPercentBinding() -> Binding<String> {
        ExtempBindingFactory.optionalDoubleText(
            getValue: { store.draft.metrologyCorrectionTargetPercent },
            setValue: { value in
                viewModel.setDraftValue(in: store, \.metrologyCorrectionTargetPercent, to: value)
            },
            formatValue: ExtempViewFormatter.formatAmount,
            parseValue: parseDouble
        )
    }

    func metrologyCorrectionStockPercentBinding() -> Binding<String> {
        ExtempBindingFactory.optionalDoubleText(
            getValue: { store.draft.metrologyCorrectionStockPercent },
            setValue: { value in
                viewModel.setDraftValue(in: store, \.metrologyCorrectionStockPercent, to: value)
            },
            formatValue: ExtempViewFormatter.formatAmount,
            parseValue: parseDouble
        )
    }

    private func parseSolutionPercentInput(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        if let direct = parseDouble(trimmed), direct > 0 {
            return direct
        }

        let noPercent = trimmed.replacingOccurrences(of: "%", with: "")
        if let plain = parseDouble(noPercent), plain > 0 {
            return plain
        }

        let compact = noPercent
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
        guard let range = compact.range(
            of: "^1[:/]([0-9]+(?:\\.[0-9]+)?)$",
            options: .regularExpression
        ) else {
            return nil
        }

        let match = String(compact[range])
        guard let denominatorRange = match.range(of: "([0-9]+(?:\\.[0-9]+)?)$", options: .regularExpression) else {
            return nil
        }
        guard let denominator = Double(match[denominatorRange]), denominator > 0 else {
            return nil
        }
        return 100.0 / denominator
    }

    func standardSolutionSourceBinding() -> Binding<SolutionKey?> {
        Binding(
            get: { store.draft.standardSolutionSourceKey },
            set: { newValue in
                viewModel.setDraftValue(in: store, \.standardSolutionSourceKey, to: newValue)
            }
        )
    }

    func standardManualStockBinding() -> Binding<String> {
        ExtempBindingFactory.optionalDoubleText(
            getValue: {
                guard let value = store.draft.standardSolutionManualStockMl, value > 0 else { return nil }
                return value
            },
            setValue: { value in
                viewModel.setDraftValue(in: store, \.standardSolutionManualStockMl, to: value)
            },
            formatValue: ExtempViewFormatter.formatAmount,
            parseValue: parseDouble
        )
    }

    func standardManualWaterBinding() -> Binding<String> {
        ExtempBindingFactory.optionalDoubleText(
            getValue: {
                guard let value = store.draft.standardSolutionManualWaterMl, value > 0 else { return nil }
                return value
            },
            setValue: { value in
                viewModel.setDraftValue(in: store, \.standardSolutionManualWaterMl, to: value)
            },
            formatValue: ExtempViewFormatter.formatAmount,
            parseValue: parseDouble
        )
    }

    func standardManualNoteBinding() -> Binding<String> {
        Binding(
            get: { store.draft.standardSolutionManualNote },
            set: { newValue in
                viewModel.setDraftValue(in: store, \.standardSolutionManualNote, to: newValue)
            }
        )
    }

    func targetTextBinding() -> Binding<String> {
        ExtempBindingFactory.optionalDoubleText(
            getValue: { store.draft.targetValue },
            setValue: { value in
                viewModel.setDraftValue(in: store, \.targetValue, to: value)
            },
            formatValue: ExtempViewFormatter.formatAmount,
            parseValue: parseDouble,
            fallbackText: getQsTargetText,
            setFallbackText: setQsTargetText
        )
    }

    func targetUnitIdBinding() -> Binding<Int?> {
        ExtempBindingFactory.unitIdBinding(
            units: { viewModel.units },
            getCode: { store.draft.targetUnit },
            setCode: { code in
                viewModel.setDraftValue(in: store, \.targetUnit, to: code)
            },
            fallbackId: getQsTargetUnitId,
            setFallbackId: setQsTargetUnitId
        )
    }

    func patientNameBinding() -> Binding<String> {
        ExtempBindingFactory.mirroredString(
            getValue: { store.draft.patientName },
            setValue: { newValue in
                viewModel.setDraftValue(in: store, \.patientName, to: newValue)
            },
            setMirror: { newValue in
                if getPatientFullName() != newValue {
                    setPatientFullName(newValue)
                }
            }
        )
    }

    func prescriptionNumberBinding() -> Binding<String> {
        ExtempBindingFactory.mirroredString(
            getValue: { store.draft.rxNumber },
            setValue: { newValue in
                viewModel.setDraftValue(in: store, \.rxNumber, to: newValue)
            },
            setMirror: { newValue in
                if getPrescriptionNumber() != newValue {
                    setPrescriptionNumber(newValue)
                }
            }
        )
    }

    func patientAgeYearsTextBinding() -> Binding<String> {
        ExtempBindingFactory.optionalRoundedIntText(
            getValue: { store.draft.patientAgeYears },
            setValue: { value in
                viewModel.setDraftValue(in: store, \.patientAgeYears, to: value)
            },
            parseDouble: parseDouble,
            fallbackText: getPatientAgeYearsText,
            setFallbackText: setPatientAgeYearsText
        )
    }

    private func unitFor(code: UnitCode) -> ExtempUnit? {
        let unitKey = code.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if unitKey.isEmpty { return nil }
        return viewModel.units.first(where: {
            $0.lat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == unitKey
            || $0.code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == unitKey
        })
    }
}
