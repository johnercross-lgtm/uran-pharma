import SwiftUI

struct StandardSolutionCatalogSelection {
    let sourceKey: SolutionKey
    let inputNameKind: DilutionInputNameKind
    let specialCase: StandardSolutionSpecialCase?
    let displayName: String
    let latinNameNom: String
    let latinNameGen: String
    let targetPercentText: String
    let targetVolumeText: String
    let signaText: String
}

struct ExtempStandardSolutionCatalogView: View {
    enum CatalogMode {
        case standard
        case special
    }

    @Environment(\.dismiss) private var dismiss

    let showsCloseButton: Bool
    let mode: CatalogMode
    let onApplySelection: ((StandardSolutionCatalogSelection) -> Void)?

    @State private var selectedEntryId: String?
    @State private var targetPercentText: String
    @State private var targetVolumeText: String
    @State private var signaText: String

    private let entries = StandardSolutionCatalogEntry.defaultCatalog
    private let engine = DefaultRuleEngine()
    private let outputPipeline = RxOutputPipeline()

    private var specialEntries: [StandardSolutionCatalogEntry] {
        entries.filter { $0.category == .special }
    }

    private var standardEntries: [StandardSolutionCatalogEntry] {
        entries.filter { $0.category == .standard }
    }

    private var visibleEntries: [StandardSolutionCatalogEntry] {
        mode == .special ? specialEntries : standardEntries
    }

    init(
        showsCloseButton: Bool,
        mode: CatalogMode = .standard,
        initialSourceKey: SolutionKey? = nil,
        initialInputNameKind: DilutionInputNameKind = .chemicalName,
        initialTargetPercentText: String = "",
        initialTargetVolumeText: String = "",
        initialSignaText: String = "",
        onApplySelection: ((StandardSolutionCatalogSelection) -> Void)? = nil
    ) {
        self.showsCloseButton = showsCloseButton
        self.mode = mode
        self.onApplySelection = onApplySelection

        let _ = StandardSolutionCatalogEntry.defaultCatalog.first(where: {
            $0.solutionKey == initialSourceKey && $0.inputNameKind == initialInputNameKind
        })

        _selectedEntryId = State(initialValue: nil)
        _targetPercentText = State(initialValue: initialTargetPercentText)
        _targetVolumeText = State(initialValue: initialTargetVolumeText)
        _signaText = State(initialValue: initialSignaText)
    }

    var body: some View {
        List {
            Section("Шаблон розчину") {
                if let selectedEntry {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(selectedEntry.title)
                            .font(.headline)

                        Text(selectedEntry.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        TextField("Концентрація, %", text: $targetPercentText)
                            .keyboardType(.decimalPad)

                        TextField("Кінцевий об’єм, ml", text: $targetVolumeText)
                            .keyboardType(.decimalPad)

                        TextField("Signa / D.S.", text: $signaText, axis: .vertical)
                            .lineLimit(2...4)

                        if let onApplySelection {
                            Button("Вставити в рецепт") {
                                Haptics.success()
                                onApplySelection(currentSelection)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("Вибери розчин зі списку нижче. Після вибору відкриється готовий шаблон Rp., ППК і технології.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if let preview {
                Section("Rp.") {
                    Text(preview.rxText)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                }

                Section("ППК") {
                    PpkPrettyText(text: preview.ppkText)
                        .padding(.vertical, 4)
                }

                Section("Блоки та секції") {
                    VStack(alignment: .leading, spacing: 8) {
                        if !preview.activatedBlocks.isEmpty {
                            Text("Активні блоки: \(preview.activatedBlocks.joined(separator: ", "))")
                                .font(.system(size: 12))
                        }

                        if !preview.sectionTitles.isEmpty {
                            Text("Секції ППК:")
                                .font(.system(size: 12, weight: .semibold))
                            ForEach(preview.sectionTitles, id: \.self) { title in
                                Text("• \(title)")
                                    .font(.system(size: 12))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section(mode == .special ? "Каталог особливих випадків" : "Каталог стандартних розчинів") {
                ForEach(visibleEntries) { entry in
                    Button {
                        Haptics.tap()
                        applyEntryPreset(entry)
                    } label: {
                        entryRow(entry)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Вибрати") {
                            Haptics.success()
                            applyEntryPreset(entry)
                        }
                        .tint(SolarizedTheme.accentColor)
                    }
                }
            }
        }
        .navigationTitle(mode == .special ? "Особливі випадки" : "Стандартні розчини")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var selectedEntry: StandardSolutionCatalogEntry? {
        guard let selectedEntryId else { return nil }
        return entries.first(where: { $0.id == selectedEntryId })
    }

    private var currentSelection: StandardSolutionCatalogSelection {
        let entry = selectedEntry ?? entries[0]
        return .init(
            sourceKey: entry.solutionKey,
            inputNameKind: entry.inputNameKind,
            specialCase: entry.specialCase,
            displayName: entry.displayName,
            latinNameNom: entry.latinNameNom,
            latinNameGen: entry.latinNameGen,
            targetPercentText: targetPercentText,
            targetVolumeText: targetVolumeText,
            signaText: signaText
        )
    }

    private var preview: StandardSolutionRenderPreview? {
        guard let entry = selectedEntry,
              let volume = parseDouble(targetVolumeText),
              volume > 0
        else {
            return nil
        }

        var draft = ExtempRecipeDraft()
        if entry.specialCase == .lugolWaterTopical {
            draft = makeLugolWaterDraft(volumeMl: volume, signa: signaText)
        } else if entry.specialCase == .lugolGlycerinTopical {
            draft = makeLugolGlycerinDraft(volumeMl: volume, signa: signaText)
        } else {
            draft.formMode = .solutions
            draft.liquidTechnologyMode = entry.liquidTechnologyMode
            draft.useStandardSolutionsBlock = true
            draft.standardSolutionSourceKey = entry.solutionKey
            draft.standardSolutionInputNameKind = entry.inputNameKind
            draft.standardSolutionSpecialCase = entry.specialCase
            draft.solPercent = parseDouble(targetPercentText)
            draft.solVolumeMl = volume
            draft.signa = signaText.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.ingredients = [
                IngredientDraft(
                    displayName: entry.displayName,
                    role: .active,
                    amountValue: volume,
                    unit: UnitCode(rawValue: "ml"),
                    presentationKind: .solution,
                    rpPrefix: .sol,
                    refNameLatNom: entry.latinNameNom,
                    refNameLatGen: entry.latinNameGen
                )
            ]
        }

        let result = engine.evaluate(draft: draft)
        let filteredIssues = result.issues.filter { issue in
            issue.code != "patient.name.required" && issue.code != "patient.rxNumber.required"
        }

        let output = outputPipeline.render(
            draft: result.normalizedDraft,
            derived: result.derived,
            issues: filteredIssues,
            techPlan: result.techPlan,
            config: RxOutputRenderConfig(showPpkSteps: true, showExtendedTech: true)
        )

        return .init(
            rxText: output.rxText,
            ppkText: output.ppkText,
            activatedBlocks: result.derived.activatedBlocks,
            sectionTitles: result.derived.ppkSections.map(\.title)
        )
    }

    private func applyEntryPreset(_ entry: StandardSolutionCatalogEntry) {
        selectedEntryId = entry.id
        targetPercentText = entry.defaultPercentText
        targetVolumeText = entry.defaultVolumeText
        signaText = entry.defaultSigna
    }

    @ViewBuilder
    private func entryRow(_ entry: StandardSolutionCatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if selectedEntryId == entry.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SolarizedTheme.accentColor)
                }
            }

            Text(entry.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func parseDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    private func makeLugolWaterDraft(volumeMl: Double, signa: String) -> ExtempRecipeDraft {
        var draft = ExtempRecipeDraft()
        let factor = volumeMl / 10.0
        draft.formMode = .solutions
        draft.liquidTechnologyMode = .waterSolution
        draft.useStandardSolutionsBlock = false
        draft.standardSolutionSpecialCase = .lugolWaterTopical
        draft.signa = signa.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.targetValue = volumeMl
        draft.targetUnit = UnitCode(rawValue: "ml")
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
                amountValue: volumeMl,
                unit: UnitCode(rawValue: "ml"),
                isAd: true,
                refType: "solvent"
            )
        ]
        return draft
    }

    private func makeLugolGlycerinDraft(volumeMl: Double, signa: String) -> ExtempRecipeDraft {
        var draft = ExtempRecipeDraft()
        let factor = volumeMl / 10.0
        draft.formMode = .solutions
        draft.liquidTechnologyMode = .waterSolution
        draft.useStandardSolutionsBlock = false
        draft.standardSolutionSpecialCase = .lugolGlycerinTopical
        draft.signa = signa.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.targetValue = volumeMl
        draft.targetUnit = UnitCode(rawValue: "ml")
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
        return draft
    }
}

struct ExtempStandardSolutionCatalogSheet: View {
    var body: some View {
        NavigationStack {
            ExtempStandardSolutionCatalogView(showsCloseButton: true)
        }
    }
}

private struct StandardSolutionRenderPreview {
    let rxText: String
    let ppkText: String
    let activatedBlocks: [String]
    let sectionTitles: [String]
}

private struct StandardSolutionCatalogEntry: Identifiable {
    enum Category {
        case standard
        case special
    }

    let id: String
    let category: Category
    let solutionKey: SolutionKey
    let inputNameKind: DilutionInputNameKind
    let specialCase: StandardSolutionSpecialCase?
    let title: String
    let subtitle: String
    let displayName: String
    let latinNameNom: String
    let latinNameGen: String
    let defaultPercentText: String
    let defaultVolumeText: String
    let defaultSigna: String
    let liquidTechnologyMode: LiquidTechnologyMode

    init(
        id: String,
        category: Category = .standard,
        solutionKey: SolutionKey,
        inputNameKind: DilutionInputNameKind,
        specialCase: StandardSolutionSpecialCase?,
        title: String,
        subtitle: String,
        displayName: String,
        latinNameNom: String,
        latinNameGen: String,
        defaultPercentText: String,
        defaultVolumeText: String,
        defaultSigna: String,
        liquidTechnologyMode: LiquidTechnologyMode
    ) {
        self.id = id
        self.category = category
        self.solutionKey = solutionKey
        self.inputNameKind = inputNameKind
        self.specialCase = specialCase
        self.title = title
        self.subtitle = subtitle
        self.displayName = displayName
        self.latinNameNom = latinNameNom
        self.latinNameGen = latinNameGen
        self.defaultPercentText = defaultPercentText
        self.defaultVolumeText = defaultVolumeText
        self.defaultSigna = defaultSigna
        self.liquidTechnologyMode = liquidTechnologyMode
    }

    static let defaultCatalog: [StandardSolutionCatalogEntry] = {
        let repo = StandardSolutionsRepository.shared
        let ammonia = repo.get(.ammoniaSolution)!
        let aceticDiluted = repo.get(.aceticAcidDiluted)!
        let hclDiluted = repo.get(.hydrochloricAcidDiluted)!
        let h2o2Concentrated = repo.get(.hydrogenPeroxideConcentrated)!
        let h2o2Diluted = repo.get(.hydrogenPeroxideDiluted)!
        let formaldehyde = repo.get(.formaldehydeSolution)!
        let burov = repo.get(.aluminumAcetateBasicSolution)!
        let lugol = repo.get(.lugolWaterSolution)!
        let lugolGlycerin = repo.get(.lugolGlycerinSolution)!

        return [
            .init(
                id: "lugol_water_topical",
                category: .special,
                solutionKey: .lugolWaterSolution,
                inputNameKind: .chemicalName,
                specialCase: .lugolWaterTopical,
                title: "Solutionis Lugoli — 10 ml",
                subtitle: "Офіцинальна водна система Люголя: Iodum 0,1 + Kalii iodidum 0,2 + Aqua purificata ad 10 ml.",
                displayName: lugol.chemicalName,
                latinNameNom: lugol.latinNameNom,
                latinNameGen: lugol.latinNameGen,
                defaultPercentText: "",
                defaultVolumeText: "10",
                defaultSigna: "Для змазування зева.",
                liquidTechnologyMode: .waterSolution
            ),
            .init(
                id: "lugol_glycerin_topical",
                category: .special,
                solutionKey: .lugolGlycerinSolution,
                inputNameKind: .chemicalName,
                specialCase: .lugolGlycerinTopical,
                title: "Solutionis Lugoli cum Glycerino — 10 ml",
                subtitle: "Офіцинальна гліцеринова система Люголя: Iodum 0,1 + Kalii iodidum 0,2 + Aqua 0,3 + Glycerinum 9,4.",
                displayName: lugolGlycerin.chemicalName,
                latinNameNom: lugolGlycerin.latinNameNom,
                latinNameGen: lugolGlycerin.latinNameGen,
                defaultPercentText: "",
                defaultVolumeText: "10",
                defaultSigna: "Для змазування зева.",
                liquidTechnologyMode: .waterSolution
            ),
            .init(
                id: "ammonia_hands",
                solutionKey: .ammoniaSolution,
                inputNameKind: .chemicalName,
                specialCase: nil,
                title: "Sol. Ammonii caustici 1% — 300 ml",
                subtitle: "Раствор аммиака по химическому названию; расчет идет по фактическим 10%.",
                displayName: ammonia.chemicalName,
                latinNameNom: ammonia.latinNameNom,
                latinNameGen: ammonia.latinNameGen,
                defaultPercentText: "1",
                defaultVolumeText: "300",
                defaultSigna: "Для обработки рук.",
                liquidTechnologyMode: .waterSolution
            ),
            .init(
                id: "ammonia_default_no_percent",
                solutionKey: .ammoniaSolution,
                inputNameKind: .chemicalName,
                specialCase: nil,
                title: "Sol. Ammonii caustici — 100 ml",
                subtitle: "Якщо концентрацію не вказано, відпускають 10% розчин аміаку.",
                displayName: ammonia.chemicalName,
                latinNameNom: ammonia.latinNameNom,
                latinNameGen: ammonia.latinNameGen,
                defaultPercentText: "",
                defaultVolumeText: "100",
                defaultSigna: "Для зовнішнього застосування.",
                liquidTechnologyMode: .waterSolution
            ),
            .init(
                id: "hcl_internal",
                solutionKey: .hydrochloricAcidDiluted,
                inputNameKind: .chemicalName,
                specialCase: nil,
                title: "Sol. Acidi hydrochlorici 2% — 200 ml",
                subtitle: "Внутреннее применение; разведенную кислоту 8,3% принимают за 100%.",
                displayName: hclDiluted.chemicalName,
                latinNameNom: hclDiluted.latinNameNom,
                latinNameGen: hclDiluted.latinNameGen,
                defaultPercentText: "2",
                defaultVolumeText: "200",
                defaultSigna: "По 1 столовой ложке 3 раза в день перед едой.",
                liquidTechnologyMode: .waterSolution
            ),
            .init(
                id: "hcl_default_no_percent",
                solutionKey: .hydrochloricAcidDiluted,
                inputNameKind: .chemicalName,
                specialCase: nil,
                title: "Sol. Acidi hydrochlorici — 200 ml",
                subtitle: "Якщо концентрацію не вказано, відпускають Acidum hydrochloricum dilutum 8,3%.",
                displayName: hclDiluted.chemicalName,
                latinNameNom: hclDiluted.latinNameNom,
                latinNameGen: hclDiluted.latinNameGen,
                defaultPercentText: "",
                defaultVolumeText: "200",
                defaultSigna: "Для внутрішнього застосування.",
                liquidTechnologyMode: .waterSolution
            ),
            .init(
                id: "hcl_demyanovich",
                solutionKey: .hydrochloricAcidDiluted,
                inputNameKind: .chemicalName,
                specialCase: .demyanovich2,
                title: "Sol. Acidi hydrochlorici 6% — 200 ml",
                subtitle: "Раствор №2 по Демьяновичу; preview учитывает приготовление из разведенной кислоты.",
                displayName: hclDiluted.chemicalName,
                latinNameNom: hclDiluted.latinNameNom,
                latinNameGen: hclDiluted.latinNameGen,
                defaultPercentText: "6",
                defaultVolumeText: "200",
                defaultSigna: "Раствор №2 по Демьяновичу (для смазывания кожи).",
                liquidTechnologyMode: .waterSolution
            ),
            .init(
                id: "hydrogen_peroxide_chemical",
                solutionKey: .hydrogenPeroxideConcentrated,
                inputNameKind: .chemicalName,
                specialCase: nil,
                title: "Sol. Hydrogenii peroxydi 6% — 3000 ml",
                subtitle: "Химическое название; расчет идет по фактическим 30% пероксида.",
                displayName: h2o2Concentrated.chemicalName,
                latinNameNom: "Hydrogenii peroxydum",
                latinNameGen: "Hydrogenii peroxydi",
                defaultPercentText: "6",
                defaultVolumeText: "3000",
                defaultSigna: "Для обработки инструментов.",
                liquidTechnologyMode: .waterSolution
            ),
            .init(
                id: "hydrogen_peroxide_default_no_percent",
                solutionKey: .hydrogenPeroxideDiluted,
                inputNameKind: .chemicalName,
                specialCase: nil,
                title: "Sol. Hydrogenii peroxydi — 100 ml",
                subtitle: "Якщо концентрацію не вказано, відпускають Hydrogenii peroxydi 3%.",
                displayName: h2o2Diluted.chemicalName,
                latinNameNom: h2o2Diluted.latinNameNom,
                latinNameGen: h2o2Diluted.latinNameGen,
                defaultPercentText: "",
                defaultVolumeText: "100",
                defaultSigna: "Для зовнішнього застосування.",
                liquidTechnologyMode: .waterSolution
            ),
            .init(
                id: "perhydrol_alias",
                solutionKey: .hydrogenPeroxideConcentrated,
                inputNameKind: .aliasName,
                specialCase: nil,
                title: "Sol. Perhydroli 5% — 100 ml",
                subtitle: "Условное название; пергидроль принимается за единицу (100%).",
                displayName: h2o2Concentrated.alias ?? h2o2Concentrated.chemicalName,
                latinNameNom: h2o2Concentrated.aliasLatinNameNom ?? h2o2Concentrated.latinNameNom,
                latinNameGen: h2o2Concentrated.aliasLatinNameGen ?? h2o2Concentrated.latinNameGen,
                defaultPercentText: "5",
                defaultVolumeText: "100",
                defaultSigna: "По 1 чайной ложке на стакан воды для полоскания.",
                liquidTechnologyMode: .waterSolution
            ),
            .init(
                id: "formalin_alias",
                solutionKey: .formaldehydeSolution,
                inputNameKind: .aliasName,
                specialCase: nil,
                title: "Sol. Formalini 5% — 100 ml",
                subtitle: "Условное название формалина; стандартный раствор принимается за 100%.",
                displayName: formaldehyde.alias ?? formaldehyde.chemicalName,
                latinNameNom: formaldehyde.aliasLatinNameNom ?? formaldehyde.latinNameNom,
                latinNameGen: formaldehyde.aliasLatinNameGen ?? formaldehyde.latinNameGen,
                defaultPercentText: "5",
                defaultVolumeText: "100",
                defaultSigna: "Для наружного применения.",
                liquidTechnologyMode: .waterSolution
            ),
            .init(
                id: "formalin_default_no_percent",
                solutionKey: .formaldehydeSolution,
                inputNameKind: .aliasName,
                specialCase: nil,
                title: "Sol. Formalini — 100 ml",
                subtitle: "Якщо концентрацію не вказано, відпускають Formalinum 37%.",
                displayName: formaldehyde.alias ?? formaldehyde.chemicalName,
                latinNameNom: formaldehyde.aliasLatinNameNom ?? formaldehyde.latinNameNom,
                latinNameGen: formaldehyde.aliasLatinNameGen ?? formaldehyde.latinNameGen,
                defaultPercentText: "",
                defaultVolumeText: "100",
                defaultSigna: "Для зовнішнього застосування.",
                liquidTechnologyMode: .waterSolution
            ),
            .init(
                id: "acetic_diluted_default_no_percent",
                solutionKey: .aceticAcidDiluted,
                inputNameKind: .chemicalName,
                specialCase: nil,
                title: "Sol. Acidi acetici diluti — 100 ml",
                subtitle: "Якщо концентрацію не вказано, відпускають Acidum aceticum dilutum 30%.",
                displayName: aceticDiluted.chemicalName,
                latinNameNom: aceticDiluted.latinNameNom,
                latinNameGen: aceticDiluted.latinNameGen,
                defaultPercentText: "",
                defaultVolumeText: "100",
                defaultSigna: "Для зовнішнього застосування.",
                liquidTechnologyMode: .waterSolution
            ),
            .init(
                id: "burov_alias",
                solutionKey: .aluminumAcetateBasicSolution,
                inputNameKind: .aliasName,
                specialCase: nil,
                title: "Sol. Liquoris Burovi 10% — 200 ml",
                subtitle: "Условное название жидкости Бурова; стандартный раствор принимается за 100%.",
                displayName: burov.alias ?? burov.chemicalName,
                latinNameNom: burov.aliasLatinNameNom ?? burov.latinNameNom,
                latinNameGen: burov.aliasLatinNameGen ?? burov.latinNameGen,
                defaultPercentText: "10",
                defaultVolumeText: "200",
                defaultSigna: "Для примочек.",
                liquidTechnologyMode: .waterSolution
            )
        ]
    }()
}
