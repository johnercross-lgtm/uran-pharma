import SwiftUI
import Combine
import UIKit

struct ExtempFormBuilderView: View {
    @StateObject private var store = RxBuilderStore()
    @StateObject private var viewModel = ExtempFormBuilderViewModel()

    @State private var showReorderSheet: Bool = false

    @State private var formMode: FormMode = .auto

    @State private var powderMassMode: PowderMassMode = .dispensa

    @State private var showPpkSteps: Bool = true
    @State private var showExtendedTech: Bool = false

    @State private var belladonnaExtractVariant: BelladonnaExtractVariant = .densum

    @State private var patientFullName: String = ""
    @State private var patientDobText: String = ""
    @State private var patientAgeYearsText: String = ""
    @State private var prescriptionNumber: String = ""
    @State private var doctorFullName: String = ""
    @State private var clinicName: String = ""
    @State private var blankType: RxBlankType = .ordinary

    @State private var qsTargetText: String = ""
    @State private var qsTargetUnitId: Int?

    @State private var toastText: String?
    @State private var isToastVisible: Bool = false

    @State private var isPatientExpanded: Bool = false
    @State private var isFormExpanded: Bool = false
    @State private var isResultExpanded: Bool = false
    @State private var isPpkExpanded: Bool = false
    @State private var showResultSheet: Bool = false
    @State private var showPpkSheet: Bool = false
    @State private var showBuretteSheet: Bool = false
    @State private var showEthanolCalculatorSheet: Bool = false
    @State private var showStandardSolutionsCatalogSheet: Bool = false
    @State private var showSpecialCasesCatalogSheet: Bool = false
    @State private var activeEditorSheet: EditorSheet?

    private enum EditorSheet: Identifiable {
        case ingredient(UUID)
        case signa

        var id: String {
            switch self {
            case .ingredient(let id):
                return "ingredient-\(id.uuidString)"
            case .signa:
                return "signa"
            }
        }
    }

    private var bindingAdapter: ExtempFormBindingAdapter {
        ExtempFormBindingAdapter(
            store: store,
            viewModel: viewModel,
            parseDouble: parseDoubleLocal,
            autoDetectedFormMode: { autoDetectedFormMode },
            getFormModeMirror: { formMode },
            setFormModeMirror: { formMode = $0 },
            getQsTargetText: { qsTargetText },
            setQsTargetText: { qsTargetText = $0 },
            getQsTargetUnitId: { qsTargetUnitId },
            setQsTargetUnitId: { qsTargetUnitId = $0 },
            getPatientFullName: { patientFullName },
            setPatientFullName: { patientFullName = $0 },
            getPrescriptionNumber: { prescriptionNumber },
            setPrescriptionNumber: { prescriptionNumber = $0 },
            getPatientAgeYearsText: { patientAgeYearsText },
            setPatientAgeYearsText: { patientAgeYearsText = $0 }
        )
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func parseDoubleLocal(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    private func bindingForDraftIngredient(_ id: UUID) -> Binding<IngredientDraft> {
        bindingAdapter.bindingForDraftIngredient(id)
    }

    private var numeroTextBinding: Binding<String> {
        bindingAdapter.numeroTextBinding()
    }

    private var draftIngredients: [IngredientDraft] {
        store.draft.ingredients
    }

    private var hasAdIngredient: Bool {
        store.draft.ingredients.contains(where: \.isAd)
    }

    private var autoDetectedFormMode: FormMode {
        AutoFormResolver.inferFormMode(draft: store.draft)
    }

    private var effectiveFormModeForUI: FormMode {
        SignaUsageAnalyzer.effectiveFormMode(for: store.draft)
    }

    private var autoDetectedFormDescription: String {
        guard store.draft.formMode == .auto else { return "" }
        if let expertise = formExpertiseSummary {
            return expertise.title
        }
        return effectiveFormModeForUI.title
    }

    private var shouldShowNumeroField: Bool {
        effectiveFormModeForUI != .ointments && effectiveFormModeForUI != .solutions && effectiveFormModeForUI != .drops
    }

    private var availableFormModes: [FormMode] {
        [.auto, .powders, .solutions, .drops, .suppositories, .ointments]
    }

    private var formExpertiseSummary: ExtempFormExpertiseSummary? {
        ExtempFormExpertiseAnalyzer.summarize(draft: store.draft)
    }

    private var selectedStandardSolutionName: String? {
        store.draft.selectedStandardSolution()?.chemicalName
    }

    private var standardSolutionExpertiseHint: String? {
        let repo = StandardSolutionsRepository.shared
        let detectedSolution: StandardSolution? = {
            if let selected = store.draft.selectedStandardSolution(repo: repo) {
                return selected
            }
            return store.draft.ingredients.first(where: { !$0.isAd && !$0.isQS }).flatMap { ingredient in
                let explicitPercent = store.draft.solutionDisplayPercent(for: ingredient)
                return repo.matchIngredient(ingredient, parsedPercent: explicitPercent)?.solution
            }
        }()

        if let solution = detectedSolution {
            return "Схоже на готовий стандартний розчин: \(solution.chemicalName). Для нього зручно працювати через каталог і відразу перевіряти ППК-прев’ю."
        }
        guard store.draft.useStandardSolutionsBlock else { return nil }
        return "Схоже на розрахунок через готовий фармакопейний розчин. Відкрий каталог, вибери вихідний розчин і підстав свої дані для розрахунку."
    }

    private var buretteExpertiseHint: String? {
        var probe = store.draft
        probe.useBuretteSystem = true
        let burette = BuretteSystem.evaluateBurette(draft: probe)
        let validItems = burette.items.filter { $0.concentrateVolumeMl > 0 && $0.soluteMassG > 0 }
        guard !validItems.isEmpty else { return nil }
        guard !burette.issues.contains(where: { $0.severity == .blocking }) else { return nil }

        let names = validItems
            .map { $0.concentrate.titleRu }
            .sorted()
            .joined(separator: ", ")

        if store.draft.useBuretteSystem {
            return "Для поточного складу доступні бюреточні концентрати: \(names). Розрахунок іде бюреточним методом."
        }
        return "Для поточного складу доступні бюреточні концентрати: \(names). Можна увімкнути бюреточний метод для автоматичного розрахунку."
    }

    private func amountTextBinding(for id: UUID) -> Binding<String> {
        bindingAdapter.amountTextBinding(for: id)
    }

    private func solPercentTextBinding(for id: UUID) -> Binding<String> {
        bindingAdapter.solPercentTextBinding(for: id)
    }

    private func solVolumeMlTextBinding(for id: UUID) -> Binding<String> {
        bindingAdapter.solVolumeMlTextBinding(for: id)
    }

    private func unitSelectionBinding(for id: UUID) -> Binding<ExtempUnit?> {
        bindingAdapter.unitSelectionBinding(for: id)
    }

    private func flagBinding(
        for id: UUID,
        get: @escaping (IngredientDraft) -> Bool,
        set: @escaping (inout IngredientDraft, Bool) -> Void
    ) -> Binding<Bool> {
        bindingAdapter.flagBinding(for: id, get: get, set: set)
    }

    private func adBinding(for id: UUID) -> Binding<Bool> {
        bindingAdapter.adBinding(for: id)
    }

    private var formModeBinding: Binding<FormMode> {
        bindingAdapter.formModeBinding()
    }

    private var liquidTechnologyModeBinding: Binding<LiquidTechnologyMode> {
        bindingAdapter.liquidTechnologyModeBinding()
    }

    private var ophthalmicDropsBinding: Binding<Bool> {
        bindingAdapter.ophthalmicDropsBinding()
    }

    private var useVmsColloidsBinding: Binding<Bool> {
        bindingAdapter.useVmsColloidsBinding()
    }

    private var useStandardSolutionsBinding: Binding<Bool> {
        bindingAdapter.useStandardSolutionsBinding()
    }

    private var useBuretteSystemBinding: Binding<Bool> {
        bindingAdapter.useBuretteSystemBinding()
    }

    private var metrologyScaleBinding: Binding<MetrologicalScaleSelection> {
        bindingAdapter.metrologyScaleBinding()
    }

    private var metrologyDropperModeBinding: Binding<MetrologicalDropperMode> {
        bindingAdapter.metrologyDropperModeBinding()
    }

    private var metrologyDropperDropsPerMlWaterBinding: Binding<String> {
        bindingAdapter.metrologyDropperDropsPerMlWaterBinding()
    }

    private var metrologyCorrectionVolumeMlBinding: Binding<String> {
        bindingAdapter.metrologyCorrectionVolumeMlBinding()
    }

    private var metrologyCorrectionActualPercentBinding: Binding<String> {
        bindingAdapter.metrologyCorrectionActualPercentBinding()
    }

    private var metrologyCorrectionTargetPercentBinding: Binding<String> {
        bindingAdapter.metrologyCorrectionTargetPercentBinding()
    }

    private var metrologyCorrectionStockPercentBinding: Binding<String> {
        bindingAdapter.metrologyCorrectionStockPercentBinding()
    }

    private var standardSolutionSourceBinding: Binding<SolutionKey?> {
        bindingAdapter.standardSolutionSourceBinding()
    }

    private var standardManualStockBinding: Binding<String> {
        bindingAdapter.standardManualStockBinding()
    }

    private var standardManualWaterBinding: Binding<String> {
        bindingAdapter.standardManualWaterBinding()
    }

    private var standardManualNoteBinding: Binding<String> {
        bindingAdapter.standardManualNoteBinding()
    }

    private var targetTextBinding: Binding<String> {
        bindingAdapter.targetTextBinding()
    }

    private var targetUnitIdBinding: Binding<Int?> {
        bindingAdapter.targetUnitIdBinding()
    }

    private var patientNameBinding: Binding<String> {
        bindingAdapter.patientNameBinding()
    }

    private var prescriptionNumberBinding: Binding<String> {
        bindingAdapter.prescriptionNumberBinding()
    }

    private var patientAgeYearsTextBinding: Binding<String> {
        bindingAdapter.patientAgeYearsTextBinding()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    searchCard
                    compositionCard
                    signaCard
                    patientAndFormCard
                    techPlanCard
                    outputsCard
                }
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Рецепт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Скрыть") {
                        hideKeyboard()
                    }
                }
            }
            .sheet(isPresented: $showResultSheet) {
                ExtempResultSheet(text: store.rxText)
            }
            .sheet(isPresented: $showPpkSheet) {
                ExtempPpkSheet(text: store.ppkText)
            }
            .sheet(isPresented: $showBuretteSheet) {
                ExtempBuretteSheet()
            }
            .sheet(isPresented: $showEthanolCalculatorSheet) {
                ExtempEthanolCalculatorSheet()
            }
            .sheet(isPresented: $showStandardSolutionsCatalogSheet) {
                NavigationStack {
                    ExtempStandardSolutionCatalogView(
                        showsCloseButton: true,
                        mode: .standard,
                        initialSourceKey: store.draft.standardSolutionSourceKey,
                        initialInputNameKind: store.draft.standardSolutionInputNameKind ?? .chemicalName,
                        initialTargetPercentText: store.draft.solPercent.map(ExtempViewFormatter.formatAmount) ?? "",
                        initialTargetVolumeText: store.draft.solVolumeMl.map(ExtempViewFormatter.formatAmount) ?? "",
                        initialSignaText: store.draft.signa,
                        onApplySelection: applyStandardSolutionSelection
                    )
                }
            }
            .sheet(isPresented: $showSpecialCasesCatalogSheet) {
                NavigationStack {
                    ExtempStandardSolutionCatalogView(
                        showsCloseButton: true,
                        mode: .special,
                        initialSourceKey: store.draft.standardSolutionSourceKey,
                        initialInputNameKind: store.draft.standardSolutionInputNameKind ?? .chemicalName,
                        initialTargetPercentText: store.draft.solPercent.map(ExtempViewFormatter.formatAmount) ?? "",
                        initialTargetVolumeText: store.draft.solVolumeMl.map(ExtempViewFormatter.formatAmount) ?? "",
                        initialSignaText: store.draft.signa,
                        onApplySelection: applyStandardSolutionSelection
                    )
                }
            }
            .sheet(item: $activeEditorSheet) { sheet in
                editorSheetView(for: sheet)
            }
            .onAppear {
                viewModel.syncDraftStateOnAppear(normalizedIngredients: normalizedIngredients)
                formMode = store.draft.formMode
                powderMassMode = store.draft.powderMassMode
                syncOutput()
            }
            .task {
                await viewModel.loadInitialData()
                viewModel.reloadStorage(for: normalizedIngredients)
                syncOutput()
            }
            .onChange(of: store.draft.ingredients) { _, _ in
                viewModel.reloadStorage(for: normalizedIngredients)
                if store.draft.formMode == .auto {
                    let resolvedMode = autoDetectedFormMode
                    viewModel.syncAutoResolvedFormMode(in: store, resolvedMode: resolvedMode)
                }
                syncOutput()
            }
            .onChange(of: viewModel.outputLookupContext) { _, _ in syncOutput() }
            .onChange(of: outputRenderState) { _, _ in syncOutput() }
            .onChange(of: powderMassMode) { _, newValue in
                viewModel.setDraftValue(in: store, \.powderMassMode, to: newValue)
            }
        }
    }

    private var isSystemUkrainianLanguage: Bool {
        let languageCode = Locale.preferredLanguages.first?
            .split(separator: "-")
            .first?
            .lowercased() ?? "ru"
        return languageCode == "uk"
    }

    private var signaSuggestions: [String] {
        if isSystemUkrainianLanguage {
            return [
                "По 1 дозі 2 рази на день",
                "По 1 дозі 3 рази на день",
                "Зовнішньо",
                "В очі",
                "У ніс"
            ]
        }
        return [
            "По 1 дозе 2 раза в день",
            "По 1 дозе 3 раза в день",
            "Наружно",
            "В глаза",
            "В нос"
        ]
    }

    private func openIngredientEditor(_ id: UUID) {
        Haptics.tap()
        activeEditorSheet = .ingredient(id)
    }

    private func openSignaEditor() {
        Haptics.tap()
        activeEditorSheet = .signa
    }

    @ViewBuilder
    private func editorSheetView(for sheet: EditorSheet) -> some View {
        switch sheet {
        case .ingredient(let id):
            ingredientEditorSheet(for: id)
        case .signa:
            signaEditorSheet
        }
    }

    @ViewBuilder
    private func ingredientEditorSheet(for id: UUID) -> some View {
        let dBinding = bindingForDraftIngredient(id)
        let substance = viewModel.ingredientSubstanceById[id]
        let warningText: String? = {
            guard let legacy = legacyIngredientOrNil(from: dBinding.wrappedValue) else { return nil }
            return ExtempFormSupport.vrdWarning(for: legacy, formMode: formMode)
        }()

        ExtempIngredientEditorSheet(
            ingredient: dBinding,
            substance: substance,
            units: viewModel.units,
            amountText: amountTextBinding(for: id),
            selectedUnit: unitSelectionBinding(for: id),
            anaFlag: flagBinding(for: id, get: { $0.isAna }, set: { $0.isAna = $1 }),
            qsFlag: flagBinding(for: id, get: { $0.isQS }, set: { $0.isQS = $1 }),
            adFlag: adBinding(for: id),
            showAdToggle: isLastIngredient(id),
            solPercentText: solPercentTextBinding(for: id),
            solVolumeText: solVolumeMlTextBinding(for: id),
            warningText: warningText,
            onDelete: {
                activeEditorSheet = nil
                removeIngredient(id)
            },
            onClose: { activeEditorSheet = nil },
            onHideKeyboard: hideKeyboard
        )
    }

    private var signaEditorSheet: some View {
        ExtempSignaEditorSheet(
            signaText: Binding(
                get: { store.draft.signa },
                set: { newValue in viewModel.setDraftValue(in: store, \.signa, to: newValue) }
            ),
            suggestions: signaSuggestions,
            onAppendSuggestion: { suggestion in
                viewModel.appendSignaSuggestion(in: store, suggestion: suggestion)
            },
            onClose: { activeEditorSheet = nil },
            onHideKeyboard: hideKeyboard
        )
    }

    private var searchCard: some View {
        ExtempSearchCard(
            query: $viewModel.query,
            results: viewModel.results,
            isLoading: viewModel.isLoading,
            incompatibilityMessage: viewModel.incompatibilityMessage,
            incompatibilityIsBlocking: viewModel.incompatibilityIsBlocking,
            canClearComposition: !store.draft.ingredients.isEmpty,
            onQueryChanged: { _ in },
            onClearQuery: {
                viewModel.clearSearch()
                hideKeyboard()
            },
            onClearComposition: clearAll,
            onSelectSubstance: addIngredient(_:),
            debugInfo: { substance in
                viewModel.debugSearchCaption(for: substance)
            }
        )
    }

    private var compositionCard: some View {
        ExtempCompositionCard(
            ingredients: draftIngredients,
            ingredientSubstanceById: viewModel.ingredientSubstanceById,
            showReorderSheet: $showReorderSheet,
            amountSummary: { ingredient in
                ExtempFormSupport.amountSummary(
                    for: ingredient,
                    targetValue: store.draft.normalizedTargetValue,
                    targetUnit: store.draft.resolvedTargetUnit
                )
            },
            ingredientBadges: { ingredient in
                ExtempFormSupport.ingredientBadges(for: ingredient)
            },
            solutionSummary: { ingredient in
                ExtempFormSupport.solutionSummary(
                    for: ingredient,
                    percentText: solPercentTextBinding(for: ingredient.id).wrappedValue,
                    volumeText: solVolumeMlTextBinding(for: ingredient.id).wrappedValue
                )
            },
            warningText: { ingredient in
                guard let legacy = legacyIngredientOrNil(from: ingredient) else { return nil }
                return ExtempFormSupport.vrdWarning(for: legacy, formMode: formMode)
            },
            onOpenIngredient: openIngredientEditor(_:),
            onRemoveIngredient: removeIngredient(_:),
            onMove: { from, to in
                viewModel.moveIngredients(in: store, from: from, to: to)
            }
        )
    }

    private var patientAndFormCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ExtempPatientFieldsPanel(
                isExpanded: $isPatientExpanded,
                patientName: patientNameBinding,
                prescriptionNumber: prescriptionNumberBinding,
                patientDobText: $patientDobText,
                patientAgeYearsText: patientAgeYearsTextBinding,
                doctorFullName: $doctorFullName,
                clinicName: $clinicName,
                blankType: $blankType
            )

            ExtempExpertiseNumeroPanel(
                isAutoMode: store.draft.formMode == .auto,
                autoDetectedFormDescription: autoDetectedFormDescription,
                expertise: formExpertiseSummary,
                standardSolutionHint: standardSolutionExpertiseHint,
                buretteHint: buretteExpertiseHint,
                isLivingDeathActive: LivingDeathEasterEgg.isActive(draft: store.draft),
                shouldShowNumeroField: shouldShowNumeroField,
                numeroText: numeroTextBinding
            )

            ExtempFormOptionsPanel(
                isExpanded: $isFormExpanded,
                formMode: formModeBinding,
                availableFormModes: availableFormModes,
                isAutoMode: store.draft.formMode == .auto,
                effectiveFormMode: effectiveFormModeForUI,
                liquidTechnologyMode: liquidTechnologyModeBinding,
                ophthalmicDrops: ophthalmicDropsBinding,
                useBuretteSystem: useBuretteSystemBinding,
                useVmsColloids: useVmsColloidsBinding,
                useStandardSolutions: useStandardSolutionsBinding,
                isStandardSolutionsEnabled: store.draft.useStandardSolutionsBlock,
                showPpkSteps: $showPpkSteps,
                showExtendedTech: $showExtendedTech,
                powderMassMode: $powderMassMode,
                metrologyScale: metrologyScaleBinding,
                metrologyDropperMode: metrologyDropperModeBinding,
                metrologyDropperDropsPerMlWaterText: metrologyDropperDropsPerMlWaterBinding,
                metrologyCorrectionVolumeMlText: metrologyCorrectionVolumeMlBinding,
                metrologyCorrectionActualPercentText: metrologyCorrectionActualPercentBinding,
                metrologyCorrectionTargetPercentText: metrologyCorrectionTargetPercentBinding,
                metrologyCorrectionStockPercentText: metrologyCorrectionStockPercentBinding,
                targetText: targetTextBinding,
                targetUnitId: targetUnitIdBinding,
                units: viewModel.units,
                hasAdIngredient: hasAdIngredient,
                selectedStandardSolutionName: selectedStandardSolutionName,
                onOpenStandardSolutionsCatalog: { showStandardSolutionsCatalogSheet = true },
                onOpenSpecialCasesCatalog: { showSpecialCasesCatalogSheet = true }
            ) {
                standardSolutionsPanel
            }
        }
        .padding(12)
        .uranCard(background: SolarizedTheme.secondarySurfaceColor, cornerRadius: 16, padding: nil)
        .padding(.horizontal, 12)
    }

    private var signaCard: some View {
        ExtempSignaCard(
            signaText: store.draft.signa,
            precisionHint: signaPrecisionHint,
            onOpen: openSignaEditor
        )
    }

    private var signaPrecisionHint: String? {
        let signa = store.draft.signa.trimmingCharacters(in: .whitespacesAndNewlines)
        if signa.isEmpty {
            if isSystemUkrainianLanguage {
                return "Для точнішого результату введіть повну Signa: спосіб застосування, дозу та кратність."
            }
            return "Для более точного результата введите полную Signa: способ применения, дозу и кратность."
        }

        let semantics = SignaUsageAnalyzer.analyze(signa: signa)
        let hasUsefulRouteMarker = semantics.isExternalRoute
            || semantics.isEyeRoute
            || semantics.isNasalRoute
            || semantics.isRectalOrVaginalRoute
            || semantics.isRinseOrGargle
            || semantics.hasDropsDose
            || semantics.hasSpoonDose

        if !hasUsefulRouteMarker || signa.count < 12 {
            if isSystemUkrainianLanguage {
                return "Для точнішої класифікації бажано уточнити Signa: куди застосовувати, скільки та як часто."
            }
            return "Для более точной классификации лучше уточнить Signa: куда применять, сколько и как часто."
        }

        return nil
    }

    private var standardSolutionsPanel: some View {
        ExtempStandardSolutionsPanel(
            sourceKey: standardSolutionSourceBinding,
            stockText: standardManualStockBinding,
            waterText: standardManualWaterBinding,
            noteText: standardManualNoteBinding,
            manualTotalMl: store.draft.standardSolutionManualTotalMl
        )
    }

    private var techPlanCard: some View {
        ExtempTechPlanCard(
            steps: store.techPlan.steps,
            showExtendedTech: showExtendedTech
        )
    }

    private var outputsCard: some View {
        ExtempOutputsCard(
            topBlockingIssueText: topBlockingIssueText,
            shadowReport: store.derived.solutionEngineShadowReport,
            isResultExpanded: $isResultExpanded,
            isPpkExpanded: $isPpkExpanded,
            rxText: store.rxText,
            ppkText: store.ppkText,
            hasRxOutputText: hasRxOutputText,
            hasPpkOutputText: hasPpkOutputText,
            combinedOutputText: combinedOutputText,
            hasCombinedOutputText: hasCombinedOutputText,
            onOpenResult: { showResultSheet = true },
            onOpenBurette: { showBuretteSheet = true },
            onOpenEthanolCalculator: { showEthanolCalculatorSheet = true },
            onOpenPpk: { showPpkSheet = true },
            onCopyCombined: {
                UIPasteboard.general.string = combinedOutputText
                showToast("Скопировано")
            }
        )
    }

    private var topBlockingIssueText: String? {
        store.issues.first(where: { $0.severity == .blocking })?.message
    }

    private var hasRxOutputText: Bool {
        !store.rxText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasPpkOutputText: Bool {
        !store.ppkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasCombinedOutputText: Bool {
        !combinedOutputText.isEmpty
    }

    private var combinedOutputText: String {
        let rx = store.rxText.trimmingCharacters(in: .whitespacesAndNewlines)
        let ppk = normalizedPpkForCombinedCopy(store.ppkText)

        if rx.isEmpty { return ppk }
        if ppk.isEmpty { return rx }
        return "\(rx)\n\nППК:\n\(ppk)"
    }

    private func normalizedPpkForCombinedCopy(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let rows = trimmed.components(separatedBy: .newlines)
        guard let first = rows.first else { return trimmed }
        let firstNormalized = first
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard firstNormalized == "ППК" else { return trimmed }

        return rows.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var outputRenderState: ExtempOutputRenderState {
        ExtempFormSupport.outputRenderState(
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

    private func syncOutput() {
        ExtempOutputCoordinator.sync(
            store: store,
            lookup: viewModel.outputLookupContext,
            state: outputRenderState
        )
    }

    private func showToast(_ text: String) {
        toastText = text
        isToastVisible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isToastVisible = false
        }
    }

    private var normalizedIngredients: [ExtempIngredientDraft] {
        ExtempFormSupport.normalizedIngredients(
            normalizedDraft: store.normalizedDraft,
            ingredientSubstanceById: viewModel.ingredientSubstanceById,
            units: viewModel.units
        )
    }

    private func isLastIngredient(_ id: UUID) -> Bool {
        store.draft.ingredients.last?.id == id
    }

    private func addIngredient(_ substance: ExtempSubstance) {
        Task { @MainActor in
            guard let newDraft = await viewModel.prepareIngredientDraft(
                for: substance,
                currentDrafts: store.draft.ingredients,
                normalizedDraft: store.normalizedDraft,
                existingDraft: store.draft
            )
            else { return }

            hideKeyboard()
            viewModel.appendIngredient(in: store, newDraft)
            syncOutput()
        }
    }

    private func removeIngredient(_ id: UUID) {
        Haptics.tap()
        if case .ingredient(let activeId) = activeEditorSheet, activeId == id {
            activeEditorSheet = nil
        }
        hideKeyboard()

        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            viewModel.removeIngredientReference(id)
            viewModel.removeIngredient(in: store, id: id)
            syncOutput()
        }
    }

    private func clearAll() {
        Haptics.tap()
        activeEditorSheet = nil
        hideKeyboard()

        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            viewModel.clearIngredients(in: store)
            viewModel.clearDraftScopedState()
            syncOutput()
        }
    }

    private func applyStandardSolutionSelection(_ selection: StandardSolutionCatalogSelection) {
        guard StandardSolutionsRepository.shared.get(selection.sourceKey) != nil else { return }

        let parsedPercent = parseDoubleLocal(selection.targetPercentText)
        let parsedVolume = parseDoubleLocal(selection.targetVolumeText)
        let targetVolumeMl = max(0, parsedVolume ?? 0)

        if (selection.specialCase == .lugolWaterTopical || selection.specialCase == .lugolGlycerinTopical), targetVolumeMl > 0 {
            store.update { draft in
                let factor = targetVolumeMl / 10.0
                draft.useStandardSolutionsBlock = false
                draft.standardSolutionSourceKey = selection.sourceKey
                draft.standardSolutionInputNameKind = selection.inputNameKind
                draft.standardSolutionSpecialCase = selection.specialCase
                draft.solPercentInputText = ""
                draft.solPercent = nil
                draft.solVolumeMl = targetVolumeMl
                draft.targetValue = targetVolumeMl
                draft.targetUnit = UnitCode(rawValue: "ml")
                draft.formMode = .solutions
                draft.liquidTechnologyMode = .waterSolution
                draft.signa = selection.signaText.trimmingCharacters(in: .whitespacesAndNewlines)
                let isGlycerinLugol = selection.specialCase == .lugolGlycerinTopical
                if isGlycerinLugol {
                    draft.ingredients = [
                        IngredientDraft(
                            displayName: "Iodum",
                            role: .active,
                            amountValue: 0.1 * factor,
                            unit: UnitCode(rawValue: "g"),
                            refType: "act",
                            refNameLatNom: "Iodum"
                        ),
                        IngredientDraft(
                            displayName: "Kalii iodidum",
                            role: .active,
                            amountValue: 0.2 * factor,
                            unit: UnitCode(rawValue: "g"),
                            refType: "act",
                            refNameLatNom: "Kalii iodidum"
                        ),
                        IngredientDraft(
                            displayName: "Aqua purificata",
                            role: .solvent,
                            amountValue: 0.3 * factor,
                            unit: UnitCode(rawValue: "ml"),
                            refType: "solvent"
                        ),
                        IngredientDraft(
                            displayName: "Glycerinum",
                            role: .solvent,
                            amountValue: 9.4 * factor,
                            unit: UnitCode(rawValue: "g"),
                            refType: "solvent"
                        )
                    ]
                } else {
                    draft.ingredients = [
                        IngredientDraft(
                            displayName: "Iodum",
                            role: .active,
                            amountValue: 0.1 * factor,
                            unit: UnitCode(rawValue: "g"),
                            refType: "act",
                            refNameLatNom: "Iodum"
                        ),
                        IngredientDraft(
                            displayName: "Kalii iodidum",
                            role: .active,
                            amountValue: 0.2 * factor,
                            unit: UnitCode(rawValue: "g"),
                            refType: "act",
                            refNameLatNom: "Kalii iodidum"
                        ),
                        IngredientDraft(
                            displayName: "Aqua purificata",
                            role: .solvent,
                            amountValue: targetVolumeMl,
                            unit: UnitCode(rawValue: "ml"),
                            isAd: true,
                            refType: "solvent"
                        )
                    ]
                }
            }

            hideKeyboard()
            syncOutput()
            return
        }

        store.update { draft in
            draft.useStandardSolutionsBlock = true
            draft.standardSolutionSourceKey = selection.sourceKey
            draft.standardSolutionInputNameKind = selection.inputNameKind
            draft.standardSolutionSpecialCase = selection.specialCase
            draft.solPercentInputText = selection.targetPercentText.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.solPercent = parsedPercent
            draft.solVolumeMl = parsedVolume
            draft.signa = selection.signaText.trimmingCharacters(in: .whitespacesAndNewlines)

            let matchedIndex = draft.ingredients.firstIndex(where: {
                !$0.isAd && !$0.isQS && $0.presentationKind == .solution
            }) ?? draft.ingredients.firstIndex(where: {
                guard !$0.isAd && !$0.isQS else { return false }
                return StandardSolutionsRepository.shared.matchIngredient($0, parsedPercent: parsedPercent)?.solution.id == selection.sourceKey
            })

            if let matchedIndex {
                for idx in draft.ingredients.indices where idx != matchedIndex && draft.ingredients[idx].presentationKind == .solution {
                    draft.ingredients[idx].presentationKind = .substance
                    if draft.ingredients[idx].rpPrefix == .sol {
                        draft.ingredients[idx].rpPrefix = .none
                    }
                }

                draft.ingredients[matchedIndex].displayName = selection.displayName
                draft.ingredients[matchedIndex].refNameLatNom = selection.latinNameNom
                draft.ingredients[matchedIndex].refNameLatGen = selection.latinNameGen
                draft.ingredients[matchedIndex].presentationKind = .solution
                draft.ingredients[matchedIndex].rpPrefix = .sol
                draft.ingredients[matchedIndex].unit = UnitCode(rawValue: "ml")
                draft.ingredients[matchedIndex].role = .active
                if let parsedVolume, parsedVolume > 0 {
                    draft.ingredients[matchedIndex].amountValue = parsedVolume
                }
            } else {
                let amountValue = max(0, parsedVolume ?? 0)
                draft.ingredients.append(
                    IngredientDraft(
                        displayName: selection.displayName,
                        role: .active,
                        amountValue: amountValue,
                        unit: UnitCode(rawValue: "ml"),
                        presentationKind: .solution,
                        rpPrefix: .sol,
                        refNameLatNom: selection.latinNameNom,
                        refNameLatGen: selection.latinNameGen
                    )
                )
            }
        }

        hideKeyboard()
        syncOutput()
    }

    private func legacyIngredientOrNil(from d: IngredientDraft) -> ExtempIngredientDraft? {
        guard let substance = viewModel.ingredientSubstanceById[d.id] else { return nil }
        return ExtempLegacyAdapter.makeLegacyIngredient(
            from: d,
            substance: substance,
            units: viewModel.units,
            solutionPercent: store.normalizedDraft.solPercent,
            solutionVolumeMl: store.normalizedDraft.solVolumeMl
        )
    }
}
